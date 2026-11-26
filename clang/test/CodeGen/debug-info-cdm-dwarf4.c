// REQUIRES: cdm-registered-target
// RUN: %clang --target=cdm -gdwarf-4 -O0 -S -emit-llvm %s -o - | FileCheck %s --check-prefix=IR --implicit-check-not=checksumkind:
// RUN: %clang --target=cdm -gdwarf-4 -O0 -c %s -o %t.O0.o
// RUN: llvm-dwarfdump --verify %t.O0.o
// RUN: llvm-dwarfdump --debug-info %t.O0.o | FileCheck %s --check-prefixes=INFO,STACK,PTR
// RUN: %clang --target=cdm -gdwarf-4 -O2 -c %s -o %t.O2.o
// RUN: llvm-dwarfdump --verify %t.O2.o
// RUN: llvm-dwarfdump --debug-info %t.O2.o | FileCheck %s --check-prefixes=INFO,PTR
// RUN: %clang --target=cdm -gdwarf-5 -O2 -c %s -o - | llvm-dwarfdump --debug-info - | FileCheck %s --check-prefix=PTR

// DWARF 4 does not require a source checksum. Keep this input free of
// -gcodeview: it used to hide an unchecked getChecksum().value() in CDM.
// IR: !DICompileUnit(
// IR: !DIFile(
// IR: !{i32 7, !"Dwarf Version", i32 4}

// Debug addresses are four bytes, while CDM int is two bytes. Check the
// actual type layout as well as successful object generation at O0 and O2.
// INFO: Compile Unit: {{.*}}version = 0x0004,{{.*}}addr_size = 0x04
struct Pair {
  int value;
  unsigned char tag;
};

volatile struct Pair global_pair;
int *global_pointer;

// INFO: DW_AT_name ("global_pair")
// INFO: DW_AT_location (DW_OP_addr {{.*}})
// INFO: DW_TAG_structure_type
// INFO-NEXT: DW_AT_name ("Pair")
// INFO-NEXT: DW_AT_byte_size (0x04)
// INFO: DW_TAG_member
// INFO-NEXT: DW_AT_name ("value")
// INFO: DW_AT_data_member_location (0x00)
// INFO: DW_TAG_member
// INFO-NEXT: DW_AT_name ("tag")
// INFO: DW_AT_data_member_location (0x02)
// INFO: DW_TAG_base_type
// INFO-NEXT: DW_AT_name ("int")
// INFO-NEXT: DW_AT_encoding (DW_ATE_signed)
// INFO-NEXT: DW_AT_byte_size (0x02)
// INFO: DW_TAG_base_type
// INFO-NEXT: DW_AT_name ("unsigned char")
// INFO-NEXT: DW_AT_encoding (DW_ATE_unsigned_char)
// INFO-NEXT: DW_AT_byte_size (0x01)
// INFO: DW_AT_name ("global_pointer")
// PTR: DW_TAG_pointer_type
// PTR-NEXT: DW_AT_type
// PTR-NEXT: DW_AT_byte_size (0x02)

// At O0 both values live in fixed frame slots. Their debug locations must
// agree with the two-byte argument and local slots in the CDM frame.
int local_value(int argument) {
  volatile int local = argument + 1;
  return local;
}

// STACK: DW_AT_frame_base (DW_OP_reg7 FP)
// INFO: DW_AT_name ("local_value")
// STACK: DW_TAG_formal_parameter
// STACK-NEXT: DW_AT_location (DW_OP_fbreg -2)
// STACK-NEXT: DW_AT_name ("argument")
// STACK: DW_TAG_variable
// STACK-NEXT: DW_AT_location (DW_OP_fbreg -4)
// STACK-NEXT: DW_AT_name ("local")
