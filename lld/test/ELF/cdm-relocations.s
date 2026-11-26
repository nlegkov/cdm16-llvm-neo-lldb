# REQUIRES: cdm
# RUN: split-file %s %t.dir
# RUN: llvm-mc -triple=cdm -filetype=obj %t.dir/relocs.s -o %t.o
# RUN: llvm-readobj -r %t.o | FileCheck %s --check-prefix=RELOC
# RUN: ld.lld -e 0 --defsym=target=0x12345678 --defsym=small=0x5678 %t.o -o %t
# RUN: llvm-objdump -s -j .data %t | FileCheck %s --check-prefix=DATA

# RUN: llvm-mc -triple=cdm -filetype=obj -I %t.dir %t.dir/first.s -o %t.first.o
# RUN: llvm-mc -triple=cdm -filetype=obj -I %t.dir %t.dir/second.s -o %t.second.o
# RUN: ld.lld -e irq -Ttext=0x1000 %t.first.o %t.second.o -o %t.dwarf
# RUN: llvm-dwarfdump --debug-info %t.dwarf | FileCheck %s --check-prefix=DWARF --implicit-check-not=warning:
# RUN: llvm-dwarfdump --verify %t.dwarf
# RUN: llvm-dwarfdump --eh-frame %t.dwarf 2>&1 | FileCheck %s --check-prefix=EH --implicit-check-not=warning:

# RUN: llc -mtriple=cdm -filetype=obj %t.dir/globals.ll -o %t.globals.o
# RUN: llvm-readobj -r %t.globals.o | FileCheck %s --check-prefix=ADDR-RELOC
# RUN: ld.lld -e 0 -Tdata=0x82000 --section-start=.progmem.data=0x2000 %t.globals.o -o %t.globals
# RUN: llvm-dwarfdump --debug-info --debug-addr %t.globals | FileCheck %s --check-prefix=ADDR
# RUN: llvm-dwarfdump --verify %t.globals

# RELOC: 0x4 R_CDM_32 target
# RELOC-NEXT: 0x8 R_CDM_32 target
# RELOC-NEXT: 0xC R_CDM_32 target
# RELOC-NEXT: 0x10 R_CDM_16 small
# DATA: 01000000 78563412 7c563412 74563412
# DATA-NEXT: {{[0-9a-f]+}} 7856aabb 00

# The second CU must use its relocated abbreviation and string references.
# DWARF: Compile Unit: {{.*}}abbr_offset = 0x0000, addr_size = 0x04
# DWARF: DW_AT_name ("first.c")
# DWARF: Compile Unit: {{.*}}abbr_offset = 0x{{0*[1-9a-f][0-9a-f]*}}, addr_size = 0x04
# DWARF: DW_AT_name ("second.c")

# Linking must relocate both FDEs and keep the signal CIE separate.
# EH: Augmentation: "zR"
# EH: Augmentation data: 02
# EH: FDE cie={{.*}} pc=00001000...00001002
# EH: 0x1000: CFA=SP+2: PC=[CFA-2]
# EH: Augmentation: "zRS"
# EH: Augmentation data: 02
# EH: FDE cie={{.*}} pc=00001004...00001006
# EH: 0x1004: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]

#--- relocs.s
# Check resolved 4-byte fixups and REL addends of both signs.
.data
.long .Lend - .Lstart
.long target
.long target + 4
.long target - 4
.short small
.byte 0xaa, 0xbb
.Lstart:
.byte 0
.Lend:

#--- common.s
.section .debug_abbrev,"",@progbits
.Labbrev:
.byte 1, 0x11, 0
.byte 3, 0x0e
.byte 0, 0, 0

.section .debug_info,"",@progbits
.long .Lend - .Lunit
.Lunit:
.short 4
.long .Labbrev
.byte 4
.byte 1
.long .Lname
.Lend:

#--- first.s
.include "common.s"
.section .debug_str,"MS",@progbits,1
.Lname:
.asciz "first.c"

.text
.p2align 2
.globl helper
helper:
.cfi_sections .eh_frame
.cfi_startproc
rts
.cfi_endproc

#--- second.s
.include "common.s"
.section .debug_str,"MS",@progbits,1
.Lname:
.asciz "second.c"

.text
.p2align 2
.globl irq
irq:
.cfi_sections .eh_frame
.cfi_startproc
.cfi_signal_frame
.cfi_def_cfa sp, 4
.cfi_offset pc, -4
.cfi_offset psr, -2
rti
.cfi_endproc

#--- globals.ll
; Preserve the ELF memory-space distinction in four-byte DWARF addresses.
@data_value = global i16 7, align 2, !dbg !0
@program_value = addrspace(1) constant i16 9, align 2, !dbg !3

; ADDR-RELOC: .rel.debug_addr {
; ADDR-RELOC-NEXT: 0x8 R_CDM_32 data_value
; ADDR-RELOC-NEXT: 0xC R_CDM_32 program_value

; ADDR: DW_AT_name ("data_value")
; ADDR: DW_AT_location (DW_OP_addrx 0x0)
; ADDR: DW_AT_name ("program_value")
; ADDR: DW_AT_location (DW_OP_addrx 0x1)
; ADDR: Address table header: {{.*}}addr_size = 0x04
; ADDR-NEXT: Addrs: [
; ADDR-NEXT: 0x00082000
; ADDR-NEXT: 0x00002000
; ADDR-NEXT: ]

!llvm.dbg.cu = !{!1}
!llvm.module.flags = !{!7, !8}
!0 = !DIGlobalVariableExpression(var: !2, expr: !DIExpression())
!1 = distinct !DICompileUnit(language: DW_LANG_C11, file: !5, producer: "test", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, globals: !6)
!2 = distinct !DIGlobalVariable(name: "data_value", scope: !1, file: !5, line: 1, type: !4, isLocal: false, isDefinition: true)
!3 = !DIGlobalVariableExpression(var: !9, expr: !DIExpression())
!4 = !DIBasicType(name: "int", size: 16, encoding: DW_ATE_signed)
!5 = !DIFile(filename: "globals.c", directory: "/")
!6 = !{!0, !3}
!7 = !{i32 2, !"Dwarf Version", i32 5}
!8 = !{i32 2, !"Debug Info Version", i32 3}
!9 = distinct !DIGlobalVariable(name: "program_value", scope: !1, file: !5, line: 2, type: !4, isLocal: false, isDefinition: true)
