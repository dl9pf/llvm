; RUN: opt < %s -simplifycfg -S | FileCheck %s

target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v64:64:64-v128:128:128-a0:0:64-s0:64:64-f80:128:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

; The table for @f
; CHECK: @switch.table = private unnamed_addr constant [7 x i32] [i32 55, i32 123, i32 0, i32 -1, i32 27, i32 62, i32 1]

; The float table for @h
; CHECK: @switch.table1 = private unnamed_addr constant [4 x float] [float 0x40091EB860000000, float 0x3FF3BE76C0000000, float 0x4012449BA0000000, float 0x4001AE1480000000]

; The table for @foostring
; CHECK: @switch.table2 = private unnamed_addr constant [4 x i8*] [i8* getelementptr inbounds ([4 x i8]* @.str, i64 0, i64 0), i8* getelementptr inbounds ([4 x i8]* @.str1, i64 0, i64 0), i8* getelementptr inbounds ([4 x i8]* @.str2, i64 0, i64 0), i8* getelementptr inbounds ([4 x i8]* @.str3, i64 0, i64 0)]

; The table for @earlyreturncrash
; CHECK: @switch.table3 = private unnamed_addr constant [4 x i32] [i32 42, i32 9, i32 88, i32 5]

; The table for @large.
; CHECK: @switch.table4 = private unnamed_addr constant [199 x i32] [i32 1, i32 4, i32 9,

; A simple int-to-int selection switch.
; It is dense enough to be replaced by table lookup.
; The result is directly by a ret from an otherwise empty bb,
; so we return early, directly from the lookup bb.

define i32 @f(i32 %c) {
entry:
  switch i32 %c, label %sw.default [
    i32 42, label %return
    i32 43, label %sw.bb1
    i32 44, label %sw.bb2
    i32 45, label %sw.bb3
    i32 46, label %sw.bb4
    i32 47, label %sw.bb5
    i32 48, label %sw.bb6
  ]

sw.bb1: br label %return
sw.bb2: br label %return
sw.bb3: br label %return
sw.bb4: br label %return
sw.bb5: br label %return
sw.bb6: br label %return
sw.default: br label %return
return:
  %retval.0 = phi i32 [ 15, %sw.default ], [ 1, %sw.bb6 ], [ 62, %sw.bb5 ], [ 27, %sw.bb4 ], [ -1, %sw.bb3 ], [ 0, %sw.bb2 ], [ 123, %sw.bb1 ], [ 55, %entry ]
  ret i32 %retval.0

; CHECK: @f
; CHECK: entry:
; CHECK-NEXT: %switch.tableidx = sub i32 %c, 42
; CHECK-NEXT: %0 = icmp ult i32 %switch.tableidx, 7
; CHECK-NEXT: br i1 %0, label %switch.lookup, label %return
; CHECK: switch.lookup:
; CHECK-NEXT: %switch.gep = getelementptr inbounds [7 x i32]* @switch.table, i32 0, i32 %switch.tableidx
; CHECK-NEXT: %switch.load = load i32* %switch.gep
; CHECK-NEXT: ret i32 %switch.load
; CHECK: return:
; CHECK-NEXT: ret i32 15
}

; A switch used to initialize two variables, an i8 and a float.

declare void @dummy(i8 signext, float)
define void @h(i32 %x) {
entry:
  switch i32 %x, label %sw.default [
    i32 0, label %sw.epilog
    i32 1, label %sw.bb1
    i32 2, label %sw.bb2
    i32 3, label %sw.bb3
  ]

sw.bb1: br label %sw.epilog
sw.bb2: br label %sw.epilog
sw.bb3: br label %sw.epilog
sw.default: br label %sw.epilog

sw.epilog:
  %a.0 = phi i8 [ 7, %sw.default ], [ 5, %sw.bb3 ], [ 88, %sw.bb2 ], [ 9, %sw.bb1 ], [ 42, %entry ]
  %b.0 = phi float [ 0x4023FAE140000000, %sw.default ], [ 0x4001AE1480000000, %sw.bb3 ], [ 0x4012449BA0000000, %sw.bb2 ], [ 0x3FF3BE76C0000000, %sw.bb1 ], [ 0x40091EB860000000, %entry ]
  call void @dummy(i8 signext %a.0, float %b.0)
  ret void

; CHECK: @h
; CHECK: entry:
; CHECK-NEXT: %switch.tableidx = sub i32 %x, 0
; CHECK-NEXT: %0 = icmp ult i32 %switch.tableidx, 4
; CHECK-NEXT: br i1 %0, label %switch.lookup, label %sw.epilog
; CHECK: switch.lookup:
; CHECK-NEXT: %switch.shiftamt = mul i32 %switch.tableidx, 8
; CHECK-NEXT: %switch.downshift = lshr i32 89655594, %switch.shiftamt
; CHECK-NEXT: %switch.masked = trunc i32 %switch.downshift to i8
; CHECK-NEXT: %switch.gep = getelementptr inbounds [4 x float]* @switch.table1, i32 0, i32 %switch.tableidx
; CHECK-NEXT: %switch.load = load float* %switch.gep
; CHECK-NEXT: br label %sw.epilog
; CHECK: sw.epilog:
; CHECK-NEXT: %a.0 = phi i8 [ %switch.masked, %switch.lookup ], [ 7, %entry ]
; CHECK-NEXT: %b.0 = phi float [ %switch.load, %switch.lookup ], [ 0x4023FAE140000000, %entry ]
; CHECK-NEXT: call void @dummy(i8 signext %a.0, float %b.0)
; CHECK-NEXT: ret void
}


; Switch used to return a string.

@.str = private unnamed_addr constant [4 x i8] c"foo\00", align 1
@.str1 = private unnamed_addr constant [4 x i8] c"bar\00", align 1
@.str2 = private unnamed_addr constant [4 x i8] c"baz\00", align 1
@.str3 = private unnamed_addr constant [4 x i8] c"qux\00", align 1
@.str4 = private unnamed_addr constant [6 x i8] c"error\00", align 1

define i8* @foostring(i32 %x)  {
entry:
  switch i32 %x, label %sw.default [
    i32 0, label %return
    i32 1, label %sw.bb1
    i32 2, label %sw.bb2
    i32 3, label %sw.bb3
  ]

sw.bb1: br label %return
sw.bb2: br label %return
sw.bb3: br label %return
sw.default: br label %return

return:
  %retval.0 = phi i8* [ getelementptr inbounds ([6 x i8]* @.str4, i64 0, i64 0), %sw.default ],
                      [ getelementptr inbounds ([4 x i8]* @.str3, i64 0, i64 0), %sw.bb3 ],
                      [ getelementptr inbounds ([4 x i8]* @.str2, i64 0, i64 0), %sw.bb2 ],
                      [ getelementptr inbounds ([4 x i8]* @.str1, i64 0, i64 0), %sw.bb1 ],
                      [ getelementptr inbounds ([4 x i8]* @.str, i64 0, i64 0), %entry ]
  ret i8* %retval.0

; CHECK: @foostring
; CHECK: entry:
; CHECK-NEXT: %switch.tableidx = sub i32 %x, 0
; CHECK-NEXT: %0 = icmp ult i32 %switch.tableidx, 4
; CHECK-NEXT: br i1 %0, label %switch.lookup, label %return
; CHECK: switch.lookup:
; CHECK-NEXT: %switch.gep = getelementptr inbounds [4 x i8*]* @switch.table2, i32 0, i32 %switch.tableidx
; CHECK-NEXT: %switch.load = load i8** %switch.gep
; CHECK-NEXT: ret i8* %switch.load
}

; Switch used to initialize two values. The first value is returned, the second
; value is not used. This used to make the transformation generate illegal code.

define i32 @earlyreturncrash(i32 %x)  {
entry:
  switch i32 %x, label %sw.default [
    i32 0, label %sw.epilog
    i32 1, label %sw.bb1
    i32 2, label %sw.bb2
    i32 3, label %sw.bb3
  ]

sw.bb1: br label %sw.epilog
sw.bb2: br label %sw.epilog
sw.bb3: br label %sw.epilog
sw.default: br label %sw.epilog

sw.epilog:
  %a.0 = phi i32 [ 7, %sw.default ], [ 5, %sw.bb3 ], [ 88, %sw.bb2 ], [ 9, %sw.bb1 ], [ 42, %entry ]
  %b.0 = phi i32 [ 10, %sw.default ], [ 5, %sw.bb3 ], [ 1, %sw.bb2 ], [ 4, %sw.bb1 ], [ 3, %entry ]
  ret i32 %a.0

; CHECK: @earlyreturncrash
; CHECK: switch.lookup:
; CHECK-NEXT: %switch.gep = getelementptr inbounds [4 x i32]* @switch.table3, i32 0, i32 %switch.tableidx
; CHECK-NEXT: %switch.load = load i32* %switch.gep
; CHECK-NEXT: ret i32 %switch.load
; CHECK: sw.epilog:
; CHECK-NEXT: ret i32 7
}


; Example 7 from http://blog.regehr.org/archives/320
; It is not dense enough for a regular table, but the results
; can be packed into a bitmap.

define i32 @crud(i8 zeroext %c)  {
entry:
  %cmp = icmp ult i8 %c, 33
  br i1 %cmp, label %lor.end, label %switch.early.test

switch.early.test:
  switch i8 %c, label %lor.rhs [
    i8 92, label %lor.end
    i8 62, label %lor.end
    i8 60, label %lor.end
    i8 59, label %lor.end
    i8 58, label %lor.end
    i8 46, label %lor.end
    i8 44, label %lor.end
    i8 34, label %lor.end
    i8 39, label %switch.edge
  ]

switch.edge: br label %lor.end
lor.rhs: br label %lor.end

lor.end:
  %0 = phi i1 [ true, %switch.early.test ],
              [ false, %lor.rhs ],
              [ true, %entry ],
              [ true, %switch.early.test ],
              [ true, %switch.early.test ],
              [ true, %switch.early.test ],
              [ true, %switch.early.test ],
              [ true, %switch.early.test ],
              [ true, %switch.early.test ],
              [ true, %switch.early.test ],
              [ true, %switch.edge ]
  %lor.ext = zext i1 %0 to i32
  ret i32 %lor.ext

; CHECK: @crud
; CHECK: entry:
; CHECK-NEXT: %cmp = icmp ult i8 %c, 33
; CHECK-NEXT: br i1 %cmp, label %lor.end, label %switch.early.test
; CHECK: switch.early.test:
; CHECK-NEXT: %switch.tableidx = sub i8 %c, 34
; CHECK-NEXT: %0 = icmp ult i8 %switch.tableidx, 59
; CHECK-NEXT: br i1 %0, label %switch.lookup, label %lor.end
; CHECK: switch.lookup:
; CHECK-NEXT: %switch.cast = zext i8 %switch.tableidx to i59
; CHECK-NEXT: %switch.shiftamt = mul i59 %switch.cast, 1
; CHECK-NEXT: %switch.downshift = lshr i59 -288230375765830623, %switch.shiftamt
; CHECK-NEXT: %switch.masked = trunc i59 %switch.downshift to i1
; CHECK-NEXT: br label %lor.end
; CHECK: lor.end:
; CHECK-NEXT: %1 = phi i1 [ true, %entry ], [ %switch.masked, %switch.lookup ], [ false, %switch.early.test ]
; CHECK-NEXT: %lor.ext = zext i1 %1 to i32
; CHECK-NEXT: ret i32 %lor.ext
}

; PR13946
define i32 @overflow(i32 %type) {
entry:
  switch i32 %type, label %sw.default [
    i32 -2147483648, label %sw.bb
    i32 0, label %sw.bb
    i32 1, label %sw.bb1
    i32 2, label %sw.bb2
    i32 -2147483645, label %sw.bb3
    i32 3, label %sw.bb3
  ]

sw.bb: br label %if.end
sw.bb1: br label %if.end
sw.bb2: br label %if.end
sw.bb3: br label %if.end
sw.default: br label %if.end
if.else: br label %if.end

if.end:
  %dirent_type.0 = phi i32 [ 3, %sw.default ], [ 6, %sw.bb3 ], [ 5, %sw.bb2 ], [ 0, %sw.bb1 ], [ 3, %sw.bb ], [ 0, %if.else ]
  ret i32 %dirent_type.0
; CHECK: define i32 @overflow
; CHECK: switch
; CHECK: phi
}

; PR13985
define i1 @undef(i32 %tmp) {
bb:
  switch i32 %tmp, label %bb3 [
    i32 0, label %bb1
    i32 1, label %bb1
    i32 7, label %bb2
    i32 8, label %bb2
  ]

bb1: br label %bb3
bb2: br label %bb3

bb3:
  %tmp4 = phi i1 [ undef, %bb ], [ false, %bb2 ], [ true, %bb1 ]
  ret i1 %tmp4
; CHECK: define i1 @undef
; CHECK: %switch.cast = trunc i32 %switch.tableidx to i9
; CHECK: %switch.downshift = lshr i9 3, %switch.shiftamt
}

; Also handle large switches that would be rejected by
; isValueEqualityComparison()
; CHECK: large
; CHECK-NOT: switch i32
define i32 @large(i32 %x) {
entry:
  %cmp = icmp slt i32 %x, 0
  br i1 %cmp, label %if.then, label %if.end

if.then:
  %mul = mul i32 %x, -10
  br label %if.end

if.end:
  %x.addr.0 = phi i32 [ %mul, %if.then ], [ %x, %entry ]
  switch i32 %x.addr.0, label %return [
    i32 199, label %sw.bb203
    i32 1, label %sw.bb1
    i32 2, label %sw.bb2
    i32 3, label %sw.bb3
    i32 4, label %sw.bb4
    i32 5, label %sw.bb5
    i32 6, label %sw.bb6
    i32 7, label %sw.bb7
    i32 8, label %sw.bb8
    i32 9, label %sw.bb9
    i32 10, label %sw.bb10
    i32 11, label %sw.bb11
    i32 12, label %sw.bb12
    i32 13, label %sw.bb13
    i32 14, label %sw.bb14
    i32 15, label %sw.bb15
    i32 16, label %sw.bb16
    i32 17, label %sw.bb17
    i32 18, label %sw.bb18
    i32 19, label %sw.bb19
    i32 20, label %sw.bb20
    i32 21, label %sw.bb21
    i32 22, label %sw.bb22
    i32 23, label %sw.bb23
    i32 24, label %sw.bb24
    i32 25, label %sw.bb25
    i32 26, label %sw.bb26
    i32 27, label %sw.bb27
    i32 28, label %sw.bb28
    i32 29, label %sw.bb29
    i32 30, label %sw.bb30
    i32 31, label %sw.bb31
    i32 32, label %sw.bb32
    i32 33, label %sw.bb33
    i32 34, label %sw.bb34
    i32 35, label %sw.bb35
    i32 36, label %sw.bb37
    i32 37, label %sw.bb38
    i32 38, label %sw.bb39
    i32 39, label %sw.bb40
    i32 40, label %sw.bb41
    i32 41, label %sw.bb42
    i32 42, label %sw.bb43
    i32 43, label %sw.bb44
    i32 44, label %sw.bb45
    i32 45, label %sw.bb47
    i32 46, label %sw.bb48
    i32 47, label %sw.bb49
    i32 48, label %sw.bb50
    i32 49, label %sw.bb51
    i32 50, label %sw.bb52
    i32 51, label %sw.bb53
    i32 52, label %sw.bb54
    i32 53, label %sw.bb55
    i32 54, label %sw.bb56
    i32 55, label %sw.bb58
    i32 56, label %sw.bb59
    i32 57, label %sw.bb60
    i32 58, label %sw.bb61
    i32 59, label %sw.bb62
    i32 60, label %sw.bb63
    i32 61, label %sw.bb64
    i32 62, label %sw.bb65
    i32 63, label %sw.bb66
    i32 64, label %sw.bb67
    i32 65, label %sw.bb68
    i32 66, label %sw.bb69
    i32 67, label %sw.bb70
    i32 68, label %sw.bb71
    i32 69, label %sw.bb72
    i32 70, label %sw.bb73
    i32 71, label %sw.bb74
    i32 72, label %sw.bb76
    i32 73, label %sw.bb77
    i32 74, label %sw.bb78
    i32 75, label %sw.bb79
    i32 76, label %sw.bb80
    i32 77, label %sw.bb81
    i32 78, label %sw.bb82
    i32 79, label %sw.bb83
    i32 80, label %sw.bb84
    i32 81, label %sw.bb85
    i32 82, label %sw.bb86
    i32 83, label %sw.bb87
    i32 84, label %sw.bb88
    i32 85, label %sw.bb89
    i32 86, label %sw.bb90
    i32 87, label %sw.bb91
    i32 88, label %sw.bb92
    i32 89, label %sw.bb93
    i32 90, label %sw.bb94
    i32 91, label %sw.bb95
    i32 92, label %sw.bb96
    i32 93, label %sw.bb97
    i32 94, label %sw.bb98
    i32 95, label %sw.bb99
    i32 96, label %sw.bb100
    i32 97, label %sw.bb101
    i32 98, label %sw.bb102
    i32 99, label %sw.bb103
    i32 100, label %sw.bb104
    i32 101, label %sw.bb105
    i32 102, label %sw.bb106
    i32 103, label %sw.bb107
    i32 104, label %sw.bb108
    i32 105, label %sw.bb109
    i32 106, label %sw.bb110
    i32 107, label %sw.bb111
    i32 108, label %sw.bb112
    i32 109, label %sw.bb113
    i32 110, label %sw.bb114
    i32 111, label %sw.bb115
    i32 112, label %sw.bb116
    i32 113, label %sw.bb117
    i32 114, label %sw.bb118
    i32 115, label %sw.bb119
    i32 116, label %sw.bb120
    i32 117, label %sw.bb121
    i32 118, label %sw.bb122
    i32 119, label %sw.bb123
    i32 120, label %sw.bb124
    i32 121, label %sw.bb125
    i32 122, label %sw.bb126
    i32 123, label %sw.bb127
    i32 124, label %sw.bb128
    i32 125, label %sw.bb129
    i32 126, label %sw.bb130
    i32 127, label %sw.bb131
    i32 128, label %sw.bb132
    i32 129, label %sw.bb133
    i32 130, label %sw.bb134
    i32 131, label %sw.bb135
    i32 132, label %sw.bb136
    i32 133, label %sw.bb137
    i32 134, label %sw.bb138
    i32 135, label %sw.bb139
    i32 136, label %sw.bb140
    i32 137, label %sw.bb141
    i32 138, label %sw.bb142
    i32 139, label %sw.bb143
    i32 140, label %sw.bb144
    i32 141, label %sw.bb145
    i32 142, label %sw.bb146
    i32 143, label %sw.bb147
    i32 144, label %sw.bb148
    i32 145, label %sw.bb149
    i32 146, label %sw.bb150
    i32 147, label %sw.bb151
    i32 148, label %sw.bb152
    i32 149, label %sw.bb153
    i32 150, label %sw.bb154
    i32 151, label %sw.bb155
    i32 152, label %sw.bb156
    i32 153, label %sw.bb157
    i32 154, label %sw.bb158
    i32 155, label %sw.bb159
    i32 156, label %sw.bb160
    i32 157, label %sw.bb161
    i32 158, label %sw.bb162
    i32 159, label %sw.bb163
    i32 160, label %sw.bb164
    i32 161, label %sw.bb165
    i32 162, label %sw.bb166
    i32 163, label %sw.bb167
    i32 164, label %sw.bb168
    i32 165, label %sw.bb169
    i32 166, label %sw.bb170
    i32 167, label %sw.bb171
    i32 168, label %sw.bb172
    i32 169, label %sw.bb173
    i32 170, label %sw.bb174
    i32 171, label %sw.bb175
    i32 172, label %sw.bb176
    i32 173, label %sw.bb177
    i32 174, label %sw.bb178
    i32 175, label %sw.bb179
    i32 176, label %sw.bb180
    i32 177, label %sw.bb181
    i32 178, label %sw.bb182
    i32 179, label %sw.bb183
    i32 180, label %sw.bb184
    i32 181, label %sw.bb185
    i32 182, label %sw.bb186
    i32 183, label %sw.bb187
    i32 184, label %sw.bb188
    i32 185, label %sw.bb189
    i32 186, label %sw.bb190
    i32 187, label %sw.bb191
    i32 188, label %sw.bb192
    i32 189, label %sw.bb193
    i32 190, label %sw.bb194
    i32 191, label %sw.bb195
    i32 192, label %sw.bb196
    i32 193, label %sw.bb197
    i32 194, label %sw.bb198
    i32 195, label %sw.bb199
    i32 196, label %sw.bb200
    i32 197, label %sw.bb201
    i32 198, label %sw.bb202
  ]

sw.bb1: br label %return
sw.bb2: br label %return
sw.bb3: br label %return
sw.bb4: br label %return
sw.bb5: br label %return
sw.bb6: br label %return
sw.bb7: br label %return
sw.bb8: br label %return
sw.bb9: br label %return
sw.bb10: br label %return
sw.bb11: br label %return
sw.bb12: br label %return
sw.bb13: br label %return
sw.bb14: br label %return
sw.bb15: br label %return
sw.bb16: br label %return
sw.bb17: br label %return
sw.bb18: br label %return
sw.bb19: br label %return
sw.bb20: br label %return
sw.bb21: br label %return
sw.bb22: br label %return
sw.bb23: br label %return
sw.bb24: br label %return
sw.bb25: br label %return
sw.bb26: br label %return
sw.bb27: br label %return
sw.bb28: br label %return
sw.bb29: br label %return
sw.bb30: br label %return
sw.bb31: br label %return
sw.bb32: br label %return
sw.bb33: br label %return
sw.bb34: br label %return
sw.bb35: br label %return
sw.bb37: br label %return
sw.bb38: br label %return
sw.bb39: br label %return
sw.bb40: br label %return
sw.bb41: br label %return
sw.bb42: br label %return
sw.bb43: br label %return
sw.bb44: br label %return
sw.bb45: br label %return
sw.bb47: br label %return
sw.bb48: br label %return
sw.bb49: br label %return
sw.bb50: br label %return
sw.bb51: br label %return
sw.bb52: br label %return
sw.bb53: br label %return
sw.bb54: br label %return
sw.bb55: br label %return
sw.bb56: br label %return
sw.bb58: br label %return
sw.bb59: br label %return
sw.bb60: br label %return
sw.bb61: br label %return
sw.bb62: br label %return
sw.bb63: br label %return
sw.bb64: br label %return
sw.bb65: br label %return
sw.bb66: br label %return
sw.bb67: br label %return
sw.bb68: br label %return
sw.bb69: br label %return
sw.bb70: br label %return
sw.bb71: br label %return
sw.bb72: br label %return
sw.bb73: br label %return
sw.bb74: br label %return
sw.bb76: br label %return
sw.bb77: br label %return
sw.bb78: br label %return
sw.bb79: br label %return
sw.bb80: br label %return
sw.bb81: br label %return
sw.bb82: br label %return
sw.bb83: br label %return
sw.bb84: br label %return
sw.bb85: br label %return
sw.bb86: br label %return
sw.bb87: br label %return
sw.bb88: br label %return
sw.bb89: br label %return
sw.bb90: br label %return
sw.bb91: br label %return
sw.bb92: br label %return
sw.bb93: br label %return
sw.bb94: br label %return
sw.bb95: br label %return
sw.bb96: br label %return
sw.bb97: br label %return
sw.bb98: br label %return
sw.bb99: br label %return
sw.bb100: br label %return
sw.bb101: br label %return
sw.bb102: br label %return
sw.bb103: br label %return
sw.bb104: br label %return
sw.bb105: br label %return
sw.bb106: br label %return
sw.bb107: br label %return
sw.bb108: br label %return
sw.bb109: br label %return
sw.bb110: br label %return
sw.bb111: br label %return
sw.bb112: br label %return
sw.bb113: br label %return
sw.bb114: br label %return
sw.bb115: br label %return
sw.bb116: br label %return
sw.bb117: br label %return
sw.bb118: br label %return
sw.bb119: br label %return
sw.bb120: br label %return
sw.bb121: br label %return
sw.bb122: br label %return
sw.bb123: br label %return
sw.bb124: br label %return
sw.bb125: br label %return
sw.bb126: br label %return
sw.bb127: br label %return
sw.bb128: br label %return
sw.bb129: br label %return
sw.bb130: br label %return
sw.bb131: br label %return
sw.bb132: br label %return
sw.bb133: br label %return
sw.bb134: br label %return
sw.bb135: br label %return
sw.bb136: br label %return
sw.bb137: br label %return
sw.bb138: br label %return
sw.bb139: br label %return
sw.bb140: br label %return
sw.bb141: br label %return
sw.bb142: br label %return
sw.bb143: br label %return
sw.bb144: br label %return
sw.bb145: br label %return
sw.bb146: br label %return
sw.bb147: br label %return
sw.bb148: br label %return
sw.bb149: br label %return
sw.bb150: br label %return
sw.bb151: br label %return
sw.bb152: br label %return
sw.bb153: br label %return
sw.bb154: br label %return
sw.bb155: br label %return
sw.bb156: br label %return
sw.bb157: br label %return
sw.bb158: br label %return
sw.bb159: br label %return
sw.bb160: br label %return
sw.bb161: br label %return
sw.bb162: br label %return
sw.bb163: br label %return
sw.bb164: br label %return
sw.bb165: br label %return
sw.bb166: br label %return
sw.bb167: br label %return
sw.bb168: br label %return
sw.bb169: br label %return
sw.bb170: br label %return
sw.bb171: br label %return
sw.bb172: br label %return
sw.bb173: br label %return
sw.bb174: br label %return
sw.bb175: br label %return
sw.bb176: br label %return
sw.bb177: br label %return
sw.bb178: br label %return
sw.bb179: br label %return
sw.bb180: br label %return
sw.bb181: br label %return
sw.bb182: br label %return
sw.bb183: br label %return
sw.bb184: br label %return
sw.bb185: br label %return
sw.bb186: br label %return
sw.bb187: br label %return
sw.bb188: br label %return
sw.bb189: br label %return
sw.bb190: br label %return
sw.bb191: br label %return
sw.bb192: br label %return
sw.bb193: br label %return
sw.bb194: br label %return
sw.bb195: br label %return
sw.bb196: br label %return
sw.bb197: br label %return
sw.bb198: br label %return
sw.bb199: br label %return
sw.bb200: br label %return
sw.bb201: br label %return
sw.bb202: br label %return
sw.bb203: br label %return

return:
  %retval.0 = phi i32 [ 39204, %sw.bb202 ], [ 38809, %sw.bb201 ], [ 38416, %sw.bb200 ], [ 38025, %sw.bb199 ], [ 37636, %sw.bb198 ], [ 37249, %sw.bb197 ], [ 36864, %sw.bb196 ], [ 36481, %sw.bb195 ], [ 36100, %sw.bb194 ], [ 35721, %sw.bb193 ], [ 35344, %sw.bb192 ], [ 34969, %sw.bb191 ], [ 34596, %sw.bb190 ], [ 34225, %sw.bb189 ], [ 33856, %sw.bb188 ], [ 33489, %sw.bb187 ], [ 33124, %sw.bb186 ], [ 32761, %sw.bb185 ], [ 32400, %sw.bb184 ], [ 32041, %sw.bb183 ], [ 31684, %sw.bb182 ], [ 31329, %sw.bb181 ], [ 30976, %sw.bb180 ], [ 30625, %sw.bb179 ], [ 30276, %sw.bb178 ], [ 29929, %sw.bb177 ], [ 29584, %sw.bb176 ], [ 29241, %sw.bb175 ], [ 28900, %sw.bb174 ], [ 28561, %sw.bb173 ], [ 28224, %sw.bb172 ], [ 27889, %sw.bb171 ], [ 27556, %sw.bb170 ], [ 27225, %sw.bb169 ], [ 26896, %sw.bb168 ], [ 26569, %sw.bb167 ], [ 26244, %sw.bb166 ], [ 25921, %sw.bb165 ], [ 25600, %sw.bb164 ], [ 25281, %sw.bb163 ], [ 24964, %sw.bb162 ], [ 24649, %sw.bb161 ], [ 24336, %sw.bb160 ], [ 24025, %sw.bb159 ], [ 23716, %sw.bb158 ], [ 23409, %sw.bb157 ], [ 23104, %sw.bb156 ], [ 22801, %sw.bb155 ], [ 22500, %sw.bb154 ], [ 22201, %sw.bb153 ], [ 21904, %sw.bb152 ], [ 21609, %sw.bb151 ], [ 21316, %sw.bb150 ], [ 21025, %sw.bb149 ], [ 20736, %sw.bb148 ], [ 20449, %sw.bb147 ], [ 20164, %sw.bb146 ], [ 19881, %sw.bb145 ], [ 19600, %sw.bb144 ], [ 19321, %sw.bb143 ], [ 19044, %sw.bb142 ], [ 18769, %sw.bb141 ], [ 18496, %sw.bb140 ], [ 18225, %sw.bb139 ], [ 17956, %sw.bb138 ], [ 17689, %sw.bb137 ], [ 17424, %sw.bb136 ], [ 17161, %sw.bb135 ], [ 16900, %sw.bb134 ], [ 16641, %sw.bb133 ], [ 16384, %sw.bb132 ], [ 16129, %sw.bb131 ], [ 15876, %sw.bb130 ], [ 15625, %sw.bb129 ], [ 15376, %sw.bb128 ], [ 15129, %sw.bb127 ], [ 14884, %sw.bb126 ], [ 14641, %sw.bb125 ], [ 14400, %sw.bb124 ], [ 14161, %sw.bb123 ], [ 13924, %sw.bb122 ], [ 13689, %sw.bb121 ], [ 13456, %sw.bb120 ], [ 13225, %sw.bb119 ], [ 12996, %sw.bb118 ], [ 12769, %sw.bb117 ], [ 12544, %sw.bb116 ], [ 12321, %sw.bb115 ], [ 12100, %sw.bb114 ], [ 11881, %sw.bb113 ], [ 11664, %sw.bb112 ], [ 11449, %sw.bb111 ], [ 11236, %sw.bb110 ], [ 11025, %sw.bb109 ], [ 10816, %sw.bb108 ], [ 10609, %sw.bb107 ], [ 10404, %sw.bb106 ], [ 10201, %sw.bb105 ], [ 10000, %sw.bb104 ], [ 9801, %sw.bb103 ], [ 9604, %sw.bb102 ], [ 9409, %sw.bb101 ], [ 9216, %sw.bb100 ], [ 9025, %sw.bb99 ], [ 8836, %sw.bb98 ], [ 8649, %sw.bb97 ], [ 8464, %sw.bb96 ], [ 8281, %sw.bb95 ], [ 8100, %sw.bb94 ], [ 7921, %sw.bb93 ], [ 7744, %sw.bb92 ], [ 7569, %sw.bb91 ], [ 7396, %sw.bb90 ], [ 7225, %sw.bb89 ], [ 7056, %sw.bb88 ], [ 6889, %sw.bb87 ], [ 6724, %sw.bb86 ], [ 6561, %sw.bb85 ], [ 6400, %sw.bb84 ], [ 6241, %sw.bb83 ], [ 6084, %sw.bb82 ], [ 5929, %sw.bb81 ], [ 5776, %sw.bb80 ], [ 5625, %sw.bb79 ], [ 5476, %sw.bb78 ], [ 5329, %sw.bb77 ], [ 5184, %sw.bb76 ], [ 5112, %sw.bb74 ], [ 4900, %sw.bb73 ], [ 4761, %sw.bb72 ], [ 4624, %sw.bb71 ], [ 4489, %sw.bb70 ], [ 4356, %sw.bb69 ], [ 4225, %sw.bb68 ], [ 4096, %sw.bb67 ], [ 3969, %sw.bb66 ], [ 3844, %sw.bb65 ], [ 3721, %sw.bb64 ], [ 3600, %sw.bb63 ], [ 3481, %sw.bb62 ], [ 3364, %sw.bb61 ], [ 3249, %sw.bb60 ], [ 3136, %sw.bb59 ], [ 3025, %sw.bb58 ], [ 2970, %sw.bb56 ], [ 2809, %sw.bb55 ], [ 2704, %sw.bb54 ], [ 2601, %sw.bb53 ], [ 2500, %sw.bb52 ], [ 2401, %sw.bb51 ], [ 2304, %sw.bb50 ], [ 2209, %sw.bb49 ], [ 2116, %sw.bb48 ], [ 2025, %sw.bb47 ], [ 1980, %sw.bb45 ], [ 1849, %sw.bb44 ], [ 1764, %sw.bb43 ], [ 1681, %sw.bb42 ], [ 1600, %sw.bb41 ], [ 1521, %sw.bb40 ], [ 1444, %sw.bb39 ], [ 1369, %sw.bb38 ], [ 1296, %sw.bb37 ], [ 1260, %sw.bb35 ], [ 1156, %sw.bb34 ], [ 1089, %sw.bb33 ], [ 1024, %sw.bb32 ], [ 961, %sw.bb31 ], [ 900, %sw.bb30 ], [ 841, %sw.bb29 ], [ 784, %sw.bb28 ], [ 729, %sw.bb27 ], [ 676, %sw.bb26 ], [ 625, %sw.bb25 ], [ 576, %sw.bb24 ], [ 529, %sw.bb23 ], [ 484, %sw.bb22 ], [ 441, %sw.bb21 ], [ 400, %sw.bb20 ], [ 361, %sw.bb19 ], [ 342, %sw.bb18 ], [ 289, %sw.bb17 ], [ 256, %sw.bb16 ], [ 225, %sw.bb15 ], [ 196, %sw.bb14 ], [ 169, %sw.bb13 ], [ 144, %sw.bb12 ], [ 121, %sw.bb11 ], [ 100, %sw.bb10 ], [ 81, %sw.bb9 ], [ 64, %sw.bb8 ], [ 49, %sw.bb7 ], [ 36, %sw.bb6 ], [ 25, %sw.bb5 ], [ 16, %sw.bb4 ], [ 9, %sw.bb3 ], [ 4, %sw.bb2 ], [ 1, %sw.bb1 ], [ 39601, %sw.bb203 ], [ 0, %if.end ]
  ret i32 %retval.0
}
