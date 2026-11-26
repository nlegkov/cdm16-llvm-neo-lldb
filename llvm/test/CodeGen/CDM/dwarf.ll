; RUN: llc -mtriple=cdm -verify-machineinstrs < %s | FileCheck %s --check-prefix=ASM
; RUN: llc -mtriple=cdm -verify-machineinstrs -filetype=obj < %s -o %t
; RUN: llvm-dwarfdump --debug-info %t 2>&1 | FileCheck %s --implicit-check-not=warning:
; RUN: llvm-dwarfdump --verify %t

declare void @llvm.dbg.declare(metadata, metadata, metadata)
declare void @llvm.dbg.value(metadata, metadata, metadata)
declare i16 @opt_helper(i16)

define i16 @locals(i16 %x) noinline optnone !dbg !4 {
entry:
  %arg = alloca i16, align 2
  %value = alloca i16, align 2
  call void @llvm.dbg.declare(metadata ptr %arg, metadata !7, metadata !DIExpression()), !dbg !9
  call void @llvm.dbg.declare(metadata ptr %value, metadata !8, metadata !DIExpression()), !dbg !9
  store i16 %x, ptr %arg, align 2, !dbg !9
  %a = load i16, ptr %arg, align 2, !dbg !9
  %b = add i16 %a, 3, !dbg !9
  store i16 %b, ptr %value, align 2, !dbg !9
  %c = load i16, ptr %value, align 2, !dbg !9
  ret i16 %c, !dbg !9
}

; CHECK: Compile Unit: {{.*}}addr_size = 0x04
; CHECK: DW_AT_frame_base (DW_OP_reg7 FP)
; CHECK: DW_TAG_formal_parameter
; CHECK-NEXT: DW_AT_location (DW_OP_fbreg -2)
; CHECK-NEXT: DW_AT_name ("x")
; CHECK: DW_TAG_variable
; CHECK-NEXT: DW_AT_location (DW_OP_fbreg -4)
; CHECK-NEXT: DW_AT_name ("value")

; Stack arguments must include both the return address and saved registers.
define i16 @stack_args(i16 %a, i16 %b, i16 %c, i16 %d, i16 %e, i16 %f) noinline optnone !dbg !11 {
entry:
  %e.addr = alloca i16, align 2
  %f.addr = alloca i16, align 2
  store i16 %e, ptr %e.addr, align 2
  store i16 %f, ptr %f.addr, align 2
  call void @llvm.dbg.declare(metadata ptr %e.addr, metadata !14, metadata !DIExpression()), !dbg !16
  call void @llvm.dbg.declare(metadata ptr %f.addr, metadata !15, metadata !DIExpression()), !dbg !16
  call void asm sideeffect "", "~{r4}"(), !dbg !16
  %ev = load i16, ptr %e.addr, align 2, !dbg !16
  %fv = load i16, ptr %f.addr, align 2, !dbg !16
  %sum = add i16 %ev, %fv, !dbg !16
  ret i16 %sum, !dbg !16
}

; ASM-LABEL: stack_args:
; ASM: push fp
; ASM: push r4
; ASM: ldsp fp
; ASM-DAG: lsw {{r[0-6]}}, 14
; ASM-DAG: lsw {{r[0-6]}}, 16
; CHECK: DW_AT_name ("stack_args")
; CHECK: DW_TAG_formal_parameter
; CHECK-NEXT: DW_AT_location (DW_OP_fbreg +14)
; CHECK-NEXT: DW_AT_name ("e")
; CHECK: DW_TAG_formal_parameter
; CHECK-NEXT: DW_AT_location (DW_OP_fbreg +16)
; CHECK-NEXT: DW_AT_name ("f")

; The VLA address is dynamic; its element count lives in a fixed frame slot.
define i16 @dynamic_array(i16 %n) noinline optnone !dbg !17 {
entry:
  %count = alloca i16, align 2
  store i16 %n, ptr %count, align 2
  call void @llvm.dbg.declare(metadata ptr %count, metadata !18, metadata !DIExpression()), !dbg !24
  %buffer = alloca i8, i16 %n, align 2
  call void @llvm.dbg.declare(metadata ptr %buffer, metadata !19, metadata !DIExpression()), !dbg !24
  store volatile i8 7, ptr %buffer, !dbg !24
  %byte = load volatile i8, ptr %buffer, !dbg !24
  %result = zext i8 %byte to i16
  ret i16 %result, !dbg !24
}

; ASM-LABEL: dynamic_array:
; ASM: ldsp fp
; ASM-NEXT: .cfi_def_cfa_register fp
; ASM: sub {{r[0-6]}}, {{r[0-6]}}, r0
; ASM-NOT: .cfi_def_cfa
; ASM: stsp r0
; ASM-NOT: .cfi_def_cfa
; ASM: stsp fp
; ASM-NEXT: .cfi_def_cfa sp, 4

; CHECK: DW_AT_name ("dynamic_array")
; CHECK: 0x[[COUNT:[0-9a-f]+]]: DW_TAG_variable
; CHECK-NEXT: DW_AT_location (DW_OP_fbreg -2)
; CHECK-NEXT: DW_AT_name ("__vla_size")
; CHECK: DW_TAG_variable
; CHECK: DW_OP_breg0 R0+0
; CHECK: DW_AT_name ("buffer")

; Unlike the optnone functions above, keep debug values through register allocation.
define i16 @optimized_vars(i16 %x) noinline nounwind !dbg !26 {
entry:
  %before = add i16 %x, 3, !dbg !30
  call void @llvm.dbg.value(metadata i16 %before, metadata !27, metadata !DIExpression()), !dbg !30
  %result = call i16 @opt_helper(i16 %before), !dbg !31
  call void @llvm.dbg.value(metadata i16 %result, metadata !28, metadata !DIExpression()), !dbg !31
  %after = add i16 %before, %result, !dbg !32
  call void @llvm.dbg.value(metadata i16 %after, metadata !29, metadata !DIExpression()), !dbg !32
  ret i16 %after, !dbg !32
}

; ASM-LABEL: optimized_vars:
; ASM: push r4
; ASM: add r4, 3
; ASM: move r4, r0
; ASM: jsr opt_helper
; ASM: add r4, r0, r0
; ASM: pop r4
; ASM: rts

; CHECK: DW_TAG_subprogram
; CHECK-NEXT: DW_AT_low_pc (0x[[#%x, OPT_BEGIN:]])
; CHECK-NEXT: DW_AT_high_pc (0x[[#%x, OPT_END:]])
; CHECK: DW_AT_name ("optimized_vars")
; CHECK: DW_TAG_variable
; CHECK: [0x[[#%.8x, OPT_BEGIN + 8]], 0x[[#%.8x, OPT_BEGIN + 20]]): DW_OP_reg4 R4
; CHECK: DW_AT_name ("before")
; CHECK: DW_TAG_variable
; CHECK: [0x[[#%.8x, OPT_BEGIN + 14]], 0x[[#%.8x, OPT_BEGIN + 16]]): DW_OP_reg0 R0
; CHECK: DW_AT_name ("result")
; CHECK: DW_TAG_variable
; CHECK: [0x[[#%.8x, OPT_BEGIN + 16]], 0x[[#%.8x, OPT_END]]): DW_OP_reg0 R0
; CHECK: DW_AT_name ("after")

; ASM-LABEL: hunt_register:
; ASM: push fp
; ASM: push r4
; ASM-NEXT: .cfi_def_cfa_offset 6
; ASM-NEXT: .cfi_offset r4, -6
; ASM-NEXT: ldsp fp
; ASM-NEXT: .cfi_def_cfa_register fp
; ASM-NEXT: addsp -256
; ASM-NOT: .cfi_
; ASM: push r0
; ASM-NEXT: ldi r0, -256
; ASM-NOT: .cfi_
; ASM: stb r0, fp, r4
; ASM-NEXT: pop r0
; ASM-NOT: .cfi_
; ASM: stsp fp
; ASM-NEXT: .cfi_def_cfa sp, 6

; R0 must not describe a variable while it contains the temporary offset.
; CHECK: DW_TAG_subprogram
; CHECK-NEXT: DW_AT_low_pc (0x[[#%x, HUNT_BEGIN:]])
; CHECK-NEXT: DW_AT_high_pc
; CHECK: DW_AT_name ("hunt_register")
; CHECK: DW_TAG_formal_parameter
; CHECK-NEXT: DW_AT_location ({{.*}}
; CHECK-NEXT: [0x[[#%.8x, HUNT_BEGIN]], 0x[[#%.8x, HUNT_BEGIN + 16]]): DW_OP_reg0 R0)
; CHECK-NEXT: DW_AT_name ("a")
; CHECK: DW_TAG_variable
; CHECK-NEXT: DW_AT_location ({{.*}}
; CHECK-NEXT: [0x[[#%.8x, HUNT_BEGIN + 8]], 0x[[#%.8x, HUNT_BEGIN + 16]]): DW_OP_reg0 R0
; CHECK-NEXT: [0x[[#%.8x, HUNT_BEGIN + 26]], 0x[[#%.8x, HUNT_BEGIN + 28]]): DW_OP_reg0 R0)
; CHECK-NEXT: DW_AT_name ("saved")

; CHECK: DW_TAG_array_type
; CHECK: DW_TAG_subrange_type
; CHECK: DW_AT_count (0x[[COUNT]])

; Keep R0-R3 live across a store whose offset needs a scratch register.
define i16 @hunt_register(i16 %a, i16 %b, i16 %c, i16 %d) nounwind !dbg !33 {
entry:
  %buffer = alloca [256 x i8], align 2
  call void @llvm.dbg.value(metadata i16 %a, metadata !36, metadata !DIExpression()), !dbg !38
  call void @llvm.dbg.value(metadata i16 %a, metadata !37, metadata !DIExpression()), !dbg !38
  store volatile i8 7, ptr %buffer, align 2, !dbg !38
  %regs = call { i16, i16, i16, i16 } asm sideeffect "", "={r0},={r1},={r2},={r3},r,{r0},{r1},{r2},{r3},~{memory}"(ptr %buffer, i16 %a, i16 %b, i16 %c, i16 %d), !dbg !38
  %r0 = extractvalue { i16, i16, i16, i16 } %regs, 0
  %r1 = extractvalue { i16, i16, i16, i16 } %regs, 1
  %r2 = extractvalue { i16, i16, i16, i16 } %regs, 2
  %r3 = extractvalue { i16, i16, i16, i16 } %regs, 3
  call void @llvm.dbg.value(metadata i16 %r0, metadata !37, metadata !DIExpression()), !dbg !38
  %ab = add i16 %r0, %r1, !dbg !38
  %abc = add i16 %ab, %r2, !dbg !38
  %result = add i16 %abc, %r3, !dbg !38
  ret i16 %result, !dbg !38
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!2, !3}
!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "test", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "locals.c", directory: "/", checksumkind: CSK_MD5, checksum: "00000000000000000000000000000000")
!2 = !{i32 2, !"Dwarf Version", i32 5}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = distinct !DISubprogram(name: "locals", scope: !1, file: !1, line: 1, type: !5, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!5 = !DISubroutineType(types: !6)
!6 = !{!10, !10}
!7 = !DILocalVariable(name: "x", arg: 1, scope: !4, file: !1, line: 1, type: !10)
!8 = !DILocalVariable(name: "value", scope: !4, file: !1, line: 2, type: !10)
!9 = !DILocation(line: 2, column: 1, scope: !4)
!10 = !DIBasicType(name: "int", size: 16, encoding: DW_ATE_signed)
!11 = distinct !DISubprogram(name: "stack_args", scope: !1, file: !1, line: 4, type: !12, scopeLine: 4, spFlags: DISPFlagDefinition, unit: !0)
!12 = !DISubroutineType(types: !13)
!13 = !{!10, !10, !10, !10, !10, !10, !10}
!14 = !DILocalVariable(name: "e", arg: 5, scope: !11, file: !1, line: 4, type: !10)
!15 = !DILocalVariable(name: "f", arg: 6, scope: !11, file: !1, line: 4, type: !10)
!16 = !DILocation(line: 5, column: 1, scope: !11)
!17 = distinct !DISubprogram(name: "dynamic_array", scope: !1, file: !1, line: 7, type: !5, scopeLine: 7, spFlags: DISPFlagDefinition, unit: !0)
!18 = !DILocalVariable(name: "__vla_size", scope: !17, type: !25, flags: DIFlagArtificial)
!19 = !DILocalVariable(name: "buffer", scope: !17, file: !1, line: 8, type: !20)
!20 = !DICompositeType(tag: DW_TAG_array_type, baseType: !21, elements: !22)
!21 = !DIBasicType(name: "unsigned char", size: 8, encoding: DW_ATE_unsigned_char)
!22 = !{!23}
!23 = !DISubrange(count: !18)
!24 = !DILocation(line: 8, column: 1, scope: !17)
!25 = !DIBasicType(name: "unsigned short", size: 16, encoding: DW_ATE_unsigned)
!26 = distinct !DISubprogram(name: "optimized_vars", scope: !1, file: !1, line: 10, type: !5, scopeLine: 10, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!27 = !DILocalVariable(name: "before", scope: !26, file: !1, line: 11, type: !10)
!28 = !DILocalVariable(name: "result", scope: !26, file: !1, line: 12, type: !10)
!29 = !DILocalVariable(name: "after", scope: !26, file: !1, line: 13, type: !10)
!30 = !DILocation(line: 11, column: 1, scope: !26)
!31 = !DILocation(line: 12, column: 1, scope: !26)
!32 = !DILocation(line: 13, column: 1, scope: !26)

!33 = distinct !DISubprogram(name: "hunt_register", scope: !1, file: !1, line: 15, type: !34, scopeLine: 15, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!34 = !DISubroutineType(types: !35)
!35 = !{!10, !10, !10, !10, !10}
!36 = !DILocalVariable(name: "a", arg: 1, scope: !33, file: !1, line: 15, type: !10)
!37 = !DILocalVariable(name: "saved", scope: !33, file: !1, line: 16, type: !10)
!38 = !DILocation(line: 17, column: 1, scope: !33)
