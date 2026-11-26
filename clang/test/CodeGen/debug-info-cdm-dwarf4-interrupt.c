// REQUIRES: cdm-registered-target
// RUN: %clang --target=cdm -gdwarf-4 -O0 -c %s -o %t.O0.o
// RUN: llvm-dwarfdump --verify %t.O0.o
// RUN: llvm-dwarfdump --eh-frame %t.O0.o | FileCheck %s --check-prefix=FRAME
// RUN: llvm-objdump -d --no-show-raw-insn %t.O0.o | FileCheck %s --check-prefix=ASM
// RUN: %clang --target=cdm -gdwarf-4 -O2 -c %s -o %t.O2.o
// RUN: llvm-dwarfdump --verify %t.O2.o
// RUN: llvm-dwarfdump --eh-frame %t.O2.o | FileCheck %s --check-prefix=FRAME
// RUN: llvm-objdump -d --no-show-raw-insn %t.O2.o | FileCheck %s --check-prefix=ASM

// A local and a non-inlined call exercise an interrupt frame with an outgoing
// argument area. Clobber every GPR so that both O0 and O2 save the full context.
volatile int observed;

__attribute__((noinline)) int helper(int x) {
  return x + 1;
}

__attribute__((interrupt)) void irq(void *ctx) {
  volatile int local = 7;
  __asm__ volatile("" ::: "r0", "r1", "r2", "r3", "r4", "r5", "r6");
  observed = helper(local);
}

// The normal helper and interrupt handler must use different CIEs.
// Capture irq's entry address to tie each CFI row to its instruction boundary.
// FRAME: Augmentation: "zR"
// FRAME: Augmentation: "zRS"
// FRAME: FDE {{.*}}pc={{[0-9a-f]+}}...
// FRAME: 0x[[#%x, IRQ:]]: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+2]]: CFA=SP+6: FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+4]]: CFA=SP+8: R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+6]]: CFA=SP+10: R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+8]]: CFA=SP+12: R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+10]]: CFA=SP+14: R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+12]]: CFA=SP+16: R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+14]]: CFA=SP+18: R1=[CFA-18], R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+16]]: CFA=SP+20: R0=[CFA-20], R1=[CFA-18], R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, IRQ+18]]: CFA=FP+20: R0=[CFA-20], R1=[CFA-18], R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]

// After SP is reset from FP, each pop removes one saved-register rule.
// The hardware PC/PSR frame remains until rti executes.
// FRAME-NEXT: 0x[[#%x, POPS:]]: CFA=SP+20: R0=[CFA-20], R1=[CFA-18], R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+2]]: CFA=SP+18: R1=[CFA-18], R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+4]]: CFA=SP+16: R2=[CFA-16], R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+6]]: CFA=SP+14: R3=[CFA-14], R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+8]]: CFA=SP+12: R4=[CFA-12], R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+10]]: CFA=SP+10: R5=[CFA-10], R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+12]]: CFA=SP+8: R6=[CFA-8], FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+14]]: CFA=SP+6: FP=[CFA-6], PC=[CFA-4], PSR=[CFA-2]
// FRAME-NEXT: 0x[[#%x, POPS+16]]: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]

// ASM-LABEL: <irq>:
// ASM-NEXT: {{[0-9a-f]+}}: push fp
// ASM-NEXT: {{[0-9a-f]+}}: push r6
// ASM-NEXT: {{[0-9a-f]+}}: push r5
// ASM-NEXT: {{[0-9a-f]+}}: push r4
// ASM-NEXT: {{[0-9a-f]+}}: push r3
// ASM-NEXT: {{[0-9a-f]+}}: push r2
// ASM-NEXT: {{[0-9a-f]+}}: push r1
// ASM-NEXT: {{[0-9a-f]+}}: push r0
// ASM-NEXT: {{[0-9a-f]+}}: ldsp fp
// ASM: jsr
// ASM: stsp fp
// ASM-NEXT: {{[0-9a-f]+}}: pop r0
// ASM-NEXT: {{[0-9a-f]+}}: pop r1
// ASM-NEXT: {{[0-9a-f]+}}: pop r2
// ASM-NEXT: {{[0-9a-f]+}}: pop r3
// ASM-NEXT: {{[0-9a-f]+}}: pop r4
// ASM-NEXT: {{[0-9a-f]+}}: pop r5
// ASM-NEXT: {{[0-9a-f]+}}: pop r6
// ASM-NEXT: {{[0-9a-f]+}}: pop fp
// ASM-NEXT: {{[0-9a-f]+}}: rti
