//
// Created by ilya on 21.11.23.
//

#include "CDMRegisterInfo.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/BinaryFormat/Dwarf.h"
#include "llvm/MC/MCDwarf.h"
#include "llvm/Support/LEB128.h"
#include "llvm/Support/raw_ostream.h"

#include "llvm/ADT/SmallSet.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include <map>

#include "CDMFrameLowering.h"
#include "CDMInstrInfo.h"
#include "CDMMachineFunctionInfo.h"
#include "MCTargetDesc/CDMMCTargetDesc.h"

#define DEBUG_TYPE "cdm-reg-info"

#define GET_REGINFO_TARGET_DESC
#include "CDMGenRegisterInfo.inc"

namespace llvm {

CDMRegisterInfo::CDMRegisterInfo() : CDMGenRegisterInfo(CDM::PC) {}

BitVector CDMRegisterInfo::getReservedRegs(const MachineFunction &MF) const {
  BitVector Reserved(getNumRegs());
  static const std::array ReservedCPURegs{CDM::FP, CDM::SP, CDM::PSR, CDM::PC};

  for (unsigned I = 0; I < ReservedCPURegs.size(); ++I)
    Reserved.set(ReservedCPURegs[I]);

  return Reserved;
}

const MCPhysReg *
CDMRegisterInfo::getCalleeSavedRegs(const MachineFunction *MF) const {
  switch (MF->getFunction().getCallingConv()) {
  case CallingConv::C:
  case CallingConv::Fast:
  case CallingConv::Cold:
    return CSR_O16_SaveList;
  case CallingConv::CDM_INTR:
    return CSR_O16_ALL_SaveList;
  }
  llvm_unreachable("Unknown calling convention");
}

bool CDMRegisterInfo::lowerFrameAddress(MachineBasicBlock::iterator II) const {
  MachineInstr &MI = *II;
  MachineFunction &MF = *MI.getParent()->getParent();
  const CDMMachineFunctionInfo &TFI = *MF.getInfo<CDMMachineFunctionInfo>();
  const TargetInstrInfo *InstrInfo = MF.getSubtarget().getInstrInfo();
  MachineBasicBlock &MBB = *MI.getParent();

  int FrameIndex = MI.getOperand(1).getIndex();
  int64_t FrameOffset = MF.getFrameInfo().getObjectOffset(FrameIndex);
  int64_t ObjectOffset = MI.getOperand(2).getImm();
  int64_t CSROffset = TFI.getCaleeSavedSize();
  // (Frame - FP) + (Object - Frame) + (Word - Object)
  int64_t FinalOffset = CSROffset + FrameOffset + ObjectOffset;

  LLVM_DEBUG(errs() << "ObjectOffset : " << ObjectOffset << "\n"
                    << "FinalOffset  : " << FinalOffset << "\n");

  const MachineOperand &SrcOperand = MI.getOperand(0);
  Register DstReg = SrcOperand.getReg();

  BuildMI(MBB, II, II->getDebugLoc(), InstrInfo->get(CDM::LDIImm6), DstReg)
      .addImm(FinalOffset);

  BuildMI(MBB, II, II->getDebugLoc(), InstrInfo->get(CDM::ADD))
      .add(SrcOperand)
      .addReg(MF.getSubtarget().getRegisterInfo()->getFrameRegister(MF))
      .addReg(DstReg, RegState::Kill);

  MI.getParent()->erase(II);
  return true;
}

bool CDMRegisterInfo::lowerFrameLoadStore(
    MachineBasicBlock::iterator II, unsigned int FIOperandNum,
    const FrameMemSubstitution &Subst) const {
  MachineInstr &MI = *II;
  MachineFunction &MF = *MI.getParent()->getParent();
  const CDMMachineFunctionInfo &TFI = *MF.getInfo<CDMMachineFunctionInfo>();
  const TargetInstrInfo *InstrInfo = MF.getSubtarget().getInstrInfo();
  MachineBasicBlock &MBB = *MI.getParent();

  int FrameIndex = MI.getOperand(FIOperandNum).getIndex();
  int64_t FrameOffset = MF.getFrameInfo().getObjectOffset(FrameIndex);
  int64_t ObjectOffset = MI.getOperand(FIOperandNum + 1).getImm();
  int64_t CSROffset = TFI.getCaleeSavedSize();
  // (Frame - FP) + (Object - Frame) + (Word - Object)
  int64_t FinalOffset = CSROffset + FrameOffset + ObjectOffset;

  LLVM_DEBUG(errs() << "ObjectOffset : " << ObjectOffset << "\n"
                    << "FinalOffset  : " << FinalOffset << "\n");

  const MachineOperand &SrcOperand = MI.getOperand(0);

  if (FinalOffset >= Subst.MemSize * 64 || FinalOffset < Subst.MemSize * -64) {
    const MachineOperand &SrcOperand = MI.getOperand(0);

    Register OffsetReg;
    if (Subst.CanReuseTargetRegister) {
      // if load
      OffsetReg = SrcOperand.getReg(); // just use same register since load will
                                       // re-define it anyway
    } else {
      // if store
      OffsetReg = huntRegister(MBB, CDM::CPURegsRegClass, MI, true);
      if (!OffsetReg) // should not happen, but report in case a bug occurs
        report_fatal_error("Couldn't find register to use");
    }

    BuildMI(MBB, II, II->getDebugLoc(), InstrInfo->get(CDM::LDIImm16),
            OffsetReg)
        .addImm(FinalOffset);

    BuildMI(MBB, II, II->getDebugLoc(), InstrInfo->get(Subst.LongOpcode))
        .add(SrcOperand)
        .addReg(OffsetReg, RegState::Kill)
        .addReg(MF.getSubtarget().getRegisterInfo()->getFrameRegister(MF));
  } else {
    BuildMI(MBB, II, II->getDebugLoc(), InstrInfo->get(Subst.ShortOpcode))
        .add(SrcOperand)
        .addImm(FinalOffset);
  }

  MI.getParent()->erase(II);
  return true;
}

bool CDMRegisterInfo::eliminateFrameIndex(MachineBasicBlock::iterator II,
                                          int SPAdj, unsigned int FIOperandNum,
                                          RegScavenger *RS) const {
  MachineInstr &MI = *II;
  MachineFunction &MF = *MI.getParent()->getParent();
  const CDMMachineFunctionInfo &TFI = *MF.getInfo<CDMMachineFunctionInfo>();

  LLVM_DEBUG(errs() << "\nFunction : " << MF.getFunction().getName() << "\n";
             errs() << "<--------->\n"
                    << MI);

  int FrameIndex = MI.getOperand(FIOperandNum).getIndex();
  int64_t FrameOffset = MF.getFrameInfo().getObjectOffset(FrameIndex);
  int64_t CSROffset = TFI.getCaleeSavedSize();
  uint64_t StackSize = MF.getFrameInfo().getStackSize();

  LLVM_DEBUG(errs() << "FrameIndex   : " << FrameIndex << "\n"
                    << "FrameOffset  : " << FrameOffset << "\n"
                    << "CSROffset    : " << CSROffset << "\n"
                    << "StackSize    : " << StackSize << "\n");

  if (MI.getOpcode() == CDM::PseudoFrameAddress) {
    return lowerFrameAddress(II);
  }

  static const std::map<unsigned, FrameMemSubstitution>
      FPRelSubstitutionOpcsTable = {
          {CDM::PseudoStoreFrameWord, {CDM::SSW, CDM::STW2Reg, 2, false}},
          {CDM::PseudoLoadFrameWord, {CDM::LSW, CDM::LDW2Reg, 2, true}},
          {CDM::PseudoStoreFrameByte, {CDM::SSB, CDM::STB2Reg, 1, false}},
          {CDM::PseudoLoadFrameByteZext, {CDM::LSB, CDM::LDB2Reg, 1, true}},
          {CDM::PseudoLoadFrameByteSext, {CDM::LSSB, CDM::LDSB2Reg, 1, true}},
      };

  const auto Opcode = MI.getOpcode();
  const auto OpcodeFindIter = FPRelSubstitutionOpcsTable.find(Opcode);

  if (OpcodeFindIter != FPRelSubstitutionOpcsTable.end()) {
    return lowerFrameLoadStore(II, FIOperandNum, OpcodeFindIter->second);
  }

  MI.getOperand(FIOperandNum).ChangeToImmediate(FrameOffset + CSROffset);
  return false;
}

Register CDMRegisterInfo::getFrameRegister(const MachineFunction &MF) const {
  return CDM::FP;
}

const uint32_t *
CDMRegisterInfo::getCallPreservedMask(const MachineFunction &MF,
                                      CallingConv::ID Id) const {
  switch (Id) {
  case CallingConv::C:
  case CallingConv::Fast:
  case CallingConv::Cold:
    return CSR_O16_RegMask;
  case CallingConv::CDM_INTR:
    return CSR_O16_ALL_RegMask;
  }
  llvm_unreachable("Unknown calling convention");
}

Register CDMRegisterInfo::huntRegister(MachineBasicBlock &MBB,
                                       const TargetRegisterClass &RC,
                                       MachineBasicBlock::iterator MI,
                                       bool AllowStackAdj) {
  using RegSmallSet = SmallSet<Register, CDM::NUM_TARGET_REGS>;

  assert(MI->getParent() == &MBB && "MI must belong to the MBB");
  assert(MI != MBB.end() && "MI must not be MBB.end()");

  const MachineRegisterInfo &MRegInfo = MBB.getParent()->getRegInfo();
  MachineFunction &MF = *MBB.getParent();

  RegSmallSet Used;
  for (const MCPhysReg *I = MRegInfo.getCalleeSavedRegs(); *I; I++) {
    if (!MRegInfo.isReserved(*I)) {
      Used.insert(*I);
    }
  }

  for (auto It = MBB.liveout_begin(); It != MBB.liveout_end(); ++It) {
    Used.insert(It->PhysReg);
  }

  for (auto It = std::prev(MBB.end()); It != MI; --It) {
    for (MachineOperand Op : It->operands()) {
      if (Op.isReg() && Op.getReg().isPhysical() && Op.isDef()) {
        Used.erase(Op.getReg());
      }
    }

    for (MachineOperand Op : It->operands()) {
      if (Op.isReg() && Op.getReg().isPhysical() && Op.isUse()) {
        Used.insert(Op.getReg());
      }
    }
  }

  RegSmallSet LiveInMI;
  for (MachineOperand Op : MI->operands()) {
    if (Op.isReg() && Op.getReg().isPhysical()) {
      LiveInMI.insert(Op.getReg());
    }
  }

  // wrapped in lambda instant call so it's initialized statically
  static const RegSmallSet GPR = [&RC, &MRegInfo, &MF]() {
    RegSmallSet S;
    for (auto Reg : RC.getRawAllocationOrder(MF)) {
      if (!MRegInfo.isReserved(Reg)) {
        S.insert(Reg);
      }
    }
    return S;
  }();

  auto Available = GPR;

  for (Register Reg : Used) {
    Available.erase(Reg);
  }
  for (Register Reg : LiveInMI) {
    Available.erase(Reg);
  }

  if (!Available.empty()) {
    return *Available.begin();
  }

  if (!AllowStackAdj) {
    return 0;
  }

  for (Register Reg : GPR) {
    if (LiveInMI.contains(Reg))
      continue;

    const auto *InstrInfo = MF.getSubtarget().getInstrInfo();
    const auto *RegInfo = MF.getSubtarget().getRegisterInfo();
    const auto &CSI = MF.getFrameInfo().getCalleeSavedInfo();

    bool DescribeSpill =
        MF.getInfo<CDMMachineFunctionInfo>()->isInterruptHandler() &&
        llvm::none_of(CSI, [Reg](const CalleeSavedInfo &Info) {
          return Info.getReg() == Reg.asMCReg();
        });

    auto EmitCFI = [&](MachineBasicBlock::iterator Pos,
                       const MCCFIInstruction &Inst) {
      unsigned Index = MF.addFrameInst(Inst);
      BuildMI(MBB, Pos, MI->getDebugLoc(),
              InstrInfo->get(TargetOpcode::CFI_INSTRUCTION))
          .addCFIIndex(Index);
    };

    if (DescribeSpill)
      EmitCFI(MI, MCCFIInstruction::createRememberState(nullptr));

    BuildMI(MBB, MI, MI->getDebugLoc(), InstrInfo->get(CDM::PUSH))
        .addReg(Reg, RegState::Kill);

    if (DescribeSpill) {
      unsigned DwarfReg = RegInfo->getDwarfRegNum(Reg, true);
      unsigned DwarfSP = RegInfo->getDwarfRegNum(CDM::SP, true);

      SmallString<8> Expr;
      raw_svector_ostream ExprOS(Expr);
      ExprOS << static_cast<char>(dwarf::DW_OP_bregx);
      encodeULEB128(DwarfSP, ExprOS);
      encodeSLEB128(0, ExprOS);

      SmallString<16> CFI;
      raw_svector_ostream CFIOS(CFI);
      CFIOS << static_cast<char>(dwarf::DW_CFA_expression);
      encodeULEB128(DwarfReg, CFIOS);
      encodeULEB128(Expr.size(), CFIOS);
      CFIOS << Expr;

      EmitCFI(MI, MCCFIInstruction::createEscape(nullptr, CFI));
    }

    auto AfterMI = std::next(MI);
    BuildMI(MBB, AfterMI, MI->getDebugLoc(), InstrInfo->get(CDM::POP), Reg);

    if (DescribeSpill)
      EmitCFI(AfterMI, MCCFIInstruction::createRestoreState(nullptr));

    return Reg;
  }

  return 0;
}

} // namespace llvm
