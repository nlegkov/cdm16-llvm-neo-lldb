// REQUIRES: cdm-registered-target
// RUN: %clang --target=cdm -g -O0 -S -emit-llvm %s -o - | FileCheck %s
// RUN: %clang --target=cdm -g -O0 -c %s -o - | llvm-dwarfdump --eh-frame - | FileCheck %s --check-prefix=EH

int identity(int x) { return x; } // CHECK: define{{.*}} @identity({{.*}} !dbg

// Debug info must preserve the interrupt signal-frame marker without -funwind-tables.
__attribute__((interrupt)) void irq(void *ctx) {}

// CHECK: !DICompileUnit(
// CHECK: !DISubprogram(name: "identity"
// EH: Augmentation: "zRS"
// EH: FDE cie=
// EH: CFA=SP+4: PC=[CFA-4], PSR=[CFA-2]
