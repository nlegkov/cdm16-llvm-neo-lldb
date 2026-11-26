# RUN: not llvm-mc -triple=cdm -filetype=obj %s -o /dev/null 2>&1 | FileCheck %s

.data
.short external - . # CHECK: :[[@LINE]]:{{[0-9]+}}: error: PC-relative relocations are not supported
.long external - .  # CHECK: :[[@LINE]]:{{[0-9]+}}: error: PC-relative relocations are not supported
