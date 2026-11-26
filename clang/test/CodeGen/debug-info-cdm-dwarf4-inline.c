// REQUIRES: cdm-registered-target
// RUN: %clang --target=cdm -gdwarf-4 -O2 -c %s -o %t.o
// RUN: llvm-dwarfdump --verify %t.o
// RUN: llvm-dwarfdump --debug-info %t.o | FileCheck %s --check-prefix=INFO
// RUN: llvm-objdump -d --no-show-raw-insn %t.o | FileCheck %s --check-prefix=ASM

// Keep the input and store observable so that O2 retains the inlined body.
// Fixed source coordinates make the call-site checks independent of comments.
#line 1 "inline.c"
volatile int input = 5;
volatile int observed;

static inline __attribute__((always_inline))
int twice(int x) {
  int result = x * 2;
  observed = result;
  return result;
}

int main(void) {
  return twice(input);
}

// The abstract function describes the original parameter and local variable.
// Capture DIE offsets rather than depending on abbreviation or string layout.
// INFO: Compile Unit: {{.*}}version = 0x0004,{{.*}}addr_size = 0x04
// INFO: 0x[[TWICE:[0-9a-f]+]]: DW_TAG_subprogram
// INFO-NEXT: DW_AT_name ("twice")
// INFO: DW_AT_inline (DW_INL_inlined)
// INFO: 0x[[ARG:[0-9a-f]+]]: DW_TAG_formal_parameter
// INFO-NEXT: DW_AT_name ("x")
// INFO: 0x[[RESULT:[0-9a-f]+]]: DW_TAG_variable
// INFO-NEXT: DW_AT_name ("result")

// The concrete inline instance belongs to main and identifies the source call.
// Its range covers the shift and store, ending before main's return.
// INFO: DW_TAG_subprogram
// INFO: DW_AT_name ("main")
// INFO: DW_TAG_inlined_subroutine
// INFO-NEXT: DW_AT_abstract_origin (0x[[TWICE]] "twice")
// INFO-NEXT: DW_AT_low_pc (0x00000006)
// INFO-NEXT: DW_AT_high_pc (0x0000000e)
// INFO-NEXT: DW_AT_call_file ("{{.*}}inline.c")
// INFO-NEXT: DW_AT_call_line (12)
// INFO-NEXT: DW_AT_call_column (10)

// R0 holds x before the shift and result afterwards. Check both the live
// ranges and their links back to the abstract parameter/local descriptions.
// INFO: DW_TAG_formal_parameter
// INFO-NEXT: DW_AT_location ({{.*}}
// INFO-NEXT: [0x00000006, 0x00000008): DW_OP_reg0 R0)
// INFO-NEXT: DW_AT_abstract_origin (0x[[ARG]] "x")
// INFO: DW_TAG_variable
// INFO-NEXT: DW_AT_location ({{.*}}
// INFO-NEXT: [0x00000008, 0x00000010): DW_OP_reg0 R0)
// INFO-NEXT: DW_AT_abstract_origin (0x[[RESULT]] "result")

// There is no call to twice: these instructions execute directly in main.
// Explicit instruction addresses tie the checks above to the machine code.
// ASM-LABEL: <main>:
// ASM-NEXT: 0: ldi r0, 0
// ASM-NEXT: 4: ldw r0, r0
// ASM-NEXT: 6: shl r0, r0, 1
// ASM-NEXT: 8: ldi r1, 0
// ASM-NEXT: c: stw r1, r0
// ASM-NEXT: e: rts
