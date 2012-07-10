# RUN: llvm-mc -triple i386-unknown-unknown %s | FileCheck %s

# CHECK: TEST0:
# CHECK: a = aaa
TEST0:
        a = 'aaa'

# CHECK: TEST1:
# CHECK: a = 97
TEST1:
        a = 'a'
