// REQUIRES: cdm-registered-target
// RUN: %clang --target=cdm -gdwarf-4 -O2 -c %s -o %t.o
// RUN: llvm-dwarfdump --verify %t.o
// RUN: llvm-dwarfdump --debug-info %t.o | FileCheck %s --check-prefix=INFO
// RUN: llvm-dwarfdump --debug-line %t.o | FileCheck %s --check-prefix=LINE
// RUN: llvm-objdump -d --no-show-raw-insn %t.o | FileCheck %s --check-prefix=ASM

// A CDM long occupies R0:R1. The debug location must describe two two-byte
// pieces, in low-to-high order, rather than a single four-byte register.
// Returning the argument keeps the register assignment stable at O2.
#line 100 "wide.c"
long wide_argument(long value) {
  return value;
}

// INFO: Compile Unit: {{.*}}version = 0x0004,{{.*}}addr_size = 0x04
// INFO: DW_AT_name ("wide_argument")
// INFO: DW_TAG_formal_parameter
// INFO: DW_OP_reg0 R0, DW_OP_piece 0x2, DW_OP_reg1 R1, DW_OP_piece 0x2
// INFO-NEXT: DW_AT_name ("value")
// INFO: DW_TAG_base_type
// INFO-NEXT: DW_AT_name ("long")
// INFO-NEXT: DW_AT_encoding (DW_ATE_signed)
// INFO-NEXT: DW_AT_byte_size (0x04)

// The only instruction is a two-byte return. Its line row and the end of
// the sequence must agree with that instruction, not ELF's address size.
// ASM-LABEL: <wide_argument>:
// ASM-NEXT: {{[0-9a-f]+}}: rts
// LINE: version: 4
// LINE: min_inst_length: 2
// LINE: name: "wide.c"
// LINE: Address {{.*}}Line {{.*}}Column
// LINE: 0x0000000000000000 101 3 1 0 0 0 is_stmt prologue_end
// LINE-NEXT: 0x0000000000000002 101 3 1 0 0 0 is_stmt end_sequence
