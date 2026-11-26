; RUN: llc -mtriple=cdm -verify-machineinstrs -force-dwarf-frame-section < %s | FileCheck %s
; RUN: llc -mtriple=cdm -verify-machineinstrs -force-dwarf-frame-section -filetype=obj < %s -o %t
; RUN: llvm-dwarfdump --debug-frame %t | FileCheck %s --check-prefix=FRAME
; RUN: llvm-dwarfdump --eh-frame %t | FileCheck %s --check-prefix=EH

; A large outgoing argument area requires multiple aligned SP adjustments.
declare void @callee([520 x i16])

define void @split_adjustment() nounwind {
; CHECK-LABEL: split_adjustment:
; CHECK: addsp -1024
; CHECK-NEXT: .cfi_def_cfa_offset 1026
; CHECK-NEXT: addsp -16
; CHECK-NEXT: .cfi_def_cfa_offset 1042
; CHECK: jsr callee
; CHECK: addsp 1022
; CHECK-NEXT: .cfi_def_cfa_offset 20
; CHECK-NEXT: addsp 18
; CHECK-NEXT: .cfi_def_cfa_offset 2
; CHECK-NEXT: rts
  call void @callee([520 x i16] undef)
  ret void
}

; Restore the frame rules between two machine returns.
define i16 @two_returns(i16 %x) noinline optnone {
; CHECK-LABEL: two_returns:
; CHECK: push fp
; CHECK-NEXT: .cfi_def_cfa_offset 4
; CHECK-NEXT: .cfi_offset fp, -4
; CHECK: ldsp fp
; CHECK-NEXT: .cfi_def_cfa_register fp
; CHECK: .cfi_remember_state
; CHECK: stsp fp
; CHECK-NEXT: .cfi_def_cfa sp, 4
; CHECK-NEXT: pop fp
; CHECK-NEXT: .cfi_restore fp
; CHECK-NEXT: .cfi_def_cfa_offset 2
; CHECK-NEXT: rts
; CHECK: .cfi_restore_state
; CHECK: stsp fp
; CHECK: rts
entry:
  %slot = alloca i16, align 2
  store i16 %x, ptr %slot, align 2
  %negative = icmp slt i16 %x, 0
  br i1 %negative, label %left, label %right
left:
  %a = load i16, ptr %slot, align 2
  ret i16 %a
right:
  ret i16 3
}

; A temporary R6 spill must not lose the rule for the ordinary R6 spill.
define void @large_frame() noinline optnone {
; CHECK-LABEL: large_frame:
; CHECK: push fp
; CHECK: push r6
; CHECK-NEXT: .cfi_def_cfa_offset 6
; CHECK-NEXT: .cfi_offset r6, -6
; CHECK: ldsp fp
; CHECK-NEXT: .cfi_def_cfa_register fp
; CHECK-NEXT: .cfi_remember_state
; CHECK-NEXT: push r6
; CHECK-NEXT: .cfi_offset r6, -8
; CHECK: addsp r6
; CHECK-NEXT: lsw r6, -2
; CHECK-NEXT: .cfi_restore_state
; CHECK: pop r6
; CHECK-NEXT: .cfi_restore r6
  %buffer = alloca [5000 x i8], align 2
  store volatile i8 1, ptr %buffer
  call void asm sideeffect "", "~{r6}"()
  ret void
}

; R6 used only by frame allocation must also be a live-in.
define void @large_frame_scratch_only() noinline optnone {
; CHECK-LABEL: large_frame_scratch_only:
; CHECK: push fp
; CHECK-NOT: push r6
; CHECK: ldsp fp
; CHECK-NEXT: .cfi_def_cfa_register fp
; CHECK-NEXT: .cfi_remember_state
; CHECK-NEXT: push r6
; CHECK-NEXT: .cfi_offset r6, -6
; CHECK: addsp r6
; CHECK-NEXT: lsw r6, -2
; CHECK-NEXT: .cfi_restore_state
; CHECK-NOT: pop r6
; CHECK: pop fp
; CHECK: rts
  %buffer = alloca [5000 x i8], align 2
  store volatile i8 1, ptr %buffer
  ret void
}

; Check the encoded CIE and the per-instruction CFA updates as well.
; FRAME: Address size: 4
; FRAME: Data alignment factor: -2
; FRAME: Return address column: 20
; FRAME: DW_CFA_def_cfa: SP +2
; FRAME: DW_CFA_offset: PC -2
; FRAME: DW_CFA_def_cfa_offset: +1026
; FRAME: DW_CFA_def_cfa_offset: +1042
; FRAME: DW_CFA_def_cfa_offset: +20
; FRAME: DW_CFA_def_cfa_offset: +2

; The decoded rows must switch to the temporary slot and back to the original.
; FRAME: DW_CFA_offset: R6 -6
; FRAME: DW_CFA_def_cfa_register: FP
; FRAME-NEXT: DW_CFA_remember_state:
; FRAME: DW_CFA_offset: R6 -8
; FRAME: DW_CFA_restore_state:
; FRAME: DW_CFA_restore: R6
; FRAME: CFA=FP+6: R6=[CFA-6], FP=[CFA-4], PC=[CFA-2]
; FRAME-NEXT: {{0x[0-9a-f]+}}: CFA=FP+6: R6=[CFA-8], FP=[CFA-4], PC=[CFA-2]
; FRAME-NEXT: {{0x[0-9a-f]+}}: CFA=FP+6: R6=[CFA-6], FP=[CFA-4], PC=[CFA-2]

; Interrupt entry saves PC and PSR before the software saves FP, R5 and R4.
define cc228 void @irq_saved() noinline nounwind optnone uwtable "frame-pointer"="all" {
; CHECK-LABEL: irq_saved:
; CHECK: .cfi_startproc
; CHECK-NEXT: .cfi_signal_frame
; CHECK: push fp
; CHECK: push r5
; CHECK: push r4
; CHECK: ldsp fp
; CHECK: stsp fp
; CHECK: pop r4
; CHECK: pop r5
; CHECK: pop fp
; CHECK: rti
  call void asm sideeffect "", "~{r4},~{r5}"()
  ret void
}

; EH: Augmentation: "zR"
; EH: DW_CFA_def_cfa: SP +2
; EH: DW_CFA_offset: PC -2
; EH: Augmentation: "zRS"
; EH: Return address column: 20
; EH-NEXT: Augmentation data: 02
; EH: FDE cie=
; EH: {{0x[0-9a-f]+}}: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+6: FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+8: R5=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+10: R4=[CFA-10], R5=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=FP+10: R4=[CFA-10], R5=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+10: R4=[CFA-10], R5=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+8: R5=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+6: FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]

; Using the context argument requires saving every general-purpose register.
define cc228 void @irq_context(ptr %ctx) nounwind uwtable {
; CHECK-LABEL: irq_context:
; CHECK: .cfi_signal_frame
; CHECK: push fp
; CHECK: push r6
; CHECK: push r5
; CHECK: push r4
; CHECK: push r3
; CHECK: push r2
; CHECK: push r1
; CHECK: push r0
; CHECK: ldsp fp
; CHECK: lsw [[REG:r[0-6]]], 0
; CHECK: ssw [[REG]], 0
; CHECK: pop r0
; CHECK: pop r1
; CHECK: pop r2
; CHECK: pop r3
; CHECK: pop r4
; CHECK: pop r5
; CHECK: pop r6
; CHECK: pop fp
; CHECK: rti
  %old = load i16, ptr %ctx, align 2
  %new = add i16 %old, 1
  store i16 %new, ptr %ctx, align 2
  ret void
}

; EH: FDE cie=
; EH: DW_CFA_offset: R6 -8
; EH: DW_CFA_offset: R5 -10
; EH: DW_CFA_offset: R4 -12
; EH: DW_CFA_offset: R3 -14
; EH: DW_CFA_offset: R2 -16
; EH: DW_CFA_offset: R1 -18
; EH: DW_CFA_offset: R0 -20
; EH: CFA=FP+20: R0=[CFA-20], R1=[CFA-18], R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]

@irq_result = internal global i16 0, align 2

; An ordinary call clobbers R0-R3; an ISR must preserve them without an FP.
define cc228 void @irq_call() nounwind uwtable {
; CHECK-LABEL: irq_call:
; CHECK: .cfi_signal_frame
; CHECK: push r3
; CHECK: push r2
; CHECK: push r1
; CHECK: push r0
; CHECK-NOT: ldsp fp
; CHECK: addsp -8
; CHECK-NEXT: .cfi_def_cfa_offset 20
; CHECK: jsr irq_helper
; CHECK: addsp 8
; CHECK-NEXT: .cfi_def_cfa_offset 12
; CHECK: pop r0
; CHECK: pop r1
; CHECK: pop r2
; CHECK: pop r3
; CHECK: rti
  %result = call i16 @irq_helper(i16 7)
  store volatile i16 %result, ptr @irq_result, align 2
  ret void
}

; EH: FDE cie=
; EH: CFA=SP+20: R0=[CFA-12], R1=[CFA-10], R2=[CFA-8], R3=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH: CFA=SP+12: R0=[CFA-12], R1=[CFA-10], R2=[CFA-8], R3=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+10: R1=[CFA-10], R2=[CFA-8], R3=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+8: R2=[CFA-8], R3=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+6: R3=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]

; The ordinary callee must not acquire the signal-frame marker.
define i16 @irq_helper(i16 %x) noinline nounwind uwtable {
; CHECK-LABEL: irq_helper:
; CHECK: .cfi_startproc
; CHECK-NOT: .cfi_signal_frame
; CHECK: add r0, 5
; CHECK-NOT: .cfi_signal_frame
; CHECK: rts
; CHECK-NOT: .cfi_signal_frame
; CHECK: .cfi_endproc
  %result = add i16 %x, 5
  ret i16 %result
}

; A scavenged ISR register not saved by the prologue needs a temporary rule.
define cc228 void @irq_hunt() nounwind uwtable {
; CHECK-LABEL: irq_hunt:
; CHECK: .cfi_remember_state
; CHECK-NEXT: push r1
; CHECK-NEXT: .cfi_escape
; CHECK-NEXT: ldi r1, -256
; CHECK-NEXT: stb r1, fp, r0
; CHECK-NEXT: pop r1
; CHECK-NEXT: .cfi_restore_state
; CHECK: rti
  %buffer = alloca [256 x i8], align 2
  store volatile i8 7, ptr %buffer, align 2
  call void asm sideeffect "", "r,~{memory}"(ptr %buffer)
  ret void
}

; EH: DW_CFA_expression: R1 DW_OP_bregx SP+0
; EH: DW_CFA_restore_state:
; EH: 0x[[#%x, HUNT:]]: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]
; EH: 0x[[#%x, HUNT+6]]: CFA=FP+8: R0=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: 0x[[#%x, HUNT+10]]: CFA=FP+8: R0=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: 0x[[#%x, HUNT+12]]: CFA=FP+8: R0=[CFA-8], R1=[DW_OP_bregx SP+0], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: 0x[[#%x, HUNT+20]]: CFA=FP+8: R0=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]

; Preserve the original rule when the prologue already saved the register.
define cc228 void @irq_hunt_saved() nounwind uwtable {
; CHECK-LABEL: irq_hunt_saved:
; CHECK: push r1
; CHECK-NEXT: .cfi_def_cfa_offset 8
; CHECK-NEXT: .cfi_offset r1, -8
; CHECK: ldsp fp
; CHECK: push r1
; CHECK-NEXT: ldi r1, -256
; CHECK-NEXT: stb r1, fp, r0
; CHECK-NEXT: pop r1
; CHECK-NEXT: ldi r0, -256
; CHECK: rti
  %value = load volatile i16, ptr @irq_result, align 2
  %buffer = alloca [256 x i8], align 2
  store volatile i8 7, ptr %buffer, align 2
  call void asm sideeffect "", "r,{r1},~{memory}"(ptr %buffer, i16 %value)
  ret void
}

; EH: FDE cie=
; EH: DW_CFA_offset: R1 -8
; EH-NOT: DW_CFA_expression:
; EH: CFA=FP+10: R0=[CFA-10], R1=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
; EH-NEXT: {{0x[0-9a-f]+}}: CFA=SP+10: R0=[CFA-10], R1=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
