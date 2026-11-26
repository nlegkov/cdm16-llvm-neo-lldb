//
// Created by ilya on 15.10.23.
//

#include "CDMMCAsmInfo.h"

namespace llvm {
CDMMCAsmInfo::CDMMCAsmInfo(const Triple &TheTriple) {
  // Preserve memory-space information in DWARF; target pointers remain 16-bit.
  CodePointerSize = 4;
  MaxInstLength = 4;
  MinInstAlignment = 2;
  PrivateGlobalPrefix = ".L";
  PrivateLabelPrefix = ".L";
  SupportsDebugInformation = true;
  UsesCFIWithoutEH = true;
  CalleeSaveStackSlotSize = 2;
}
} // namespace llvm
