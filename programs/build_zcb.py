#!/usr/bin/env python3
"""Hand-assemble a directed Zcb (compressed sub-word LS + c.not/c.mul/ext) test
for the 3-SIPP-ES core. No GCC required.

Emits programs/build/zcb.hex (one 32-bit word per line) for $readmemh.
Convention: store 1 to tohost (0x2000_0000) on success, 2 on failure.

The stream is byte-addressed: 32-bit ops occupy 4 bytes, 16-bit (Zcb/RVC) ops
occupy 2 bytes. We assemble into a byte array then pack little-endian into
32-bit words, matching the halfword-granular fetch of the core.

IMPORTANT: every Zcb reg operand (rd'/rs1'/rs2') must be a compressed register
x8..x15. So all values under test live in x8..x15; scratch/compare regs use
the full 32-bit ops (which accept any register).

Each Zcb instruction is exercised, result compared against a hand-computed
value, guarded by `bne res, exp, FAIL`.
"""
import sys
from pathlib import Path

NEG = "--neg" in sys.argv   # negative control: corrupt one expected value

# ---------- 32-bit encoders --------------------------------------------------
def u32(x): return x & 0xFFFFFFFF
def R(f7,rs2,rs1,f3,rd,op): return u32((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def I(imm,rs1,f3,rd,op):    return u32(((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def S(imm,rs2,rs1,f3,op):
    imm&=0xFFF
    return u32(((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|op)
def B(imm,rs2,rs1,f3,op):
    imm&=0x1FFE
    return u32(((imm>>12&1)<<31)|((imm>>5&0x3F)<<25)|(rs2<<20)|(rs1<<15)|
               (f3<<12)|((imm>>1&0xF)<<8)|((imm>>11&1)<<7)|op)
def U(imm,rd,op): return u32((imm&0xFFFFF000)|(rd<<7)|op)
def J(imm,rd,op):
    imm&=0x1FFFFE
    return u32(((imm>>20&1)<<31)|((imm>>1&0x3FF)<<21)|((imm>>11&1)<<20)|
               ((imm>>12&0xFF)<<12)|(rd<<7)|op)

def addi(rd,rs1,i): return I(i,rs1,0,rd,0x13)
def lui(rd,i):  return U(i,rd,0x37)
def sw(rs2,rs1,i): return S(i,rs2,rs1,2,0x23)
def bne(rs1,rs2,i):return B(i,rs2,rs1,1,0x63)
def jal(rd,i):  return J(i,rd,0x6F)

def li(rd,v):
    v&=0xFFFFFFFF
    lo=v&0xFFF
    hi=(v-(lo if lo<0x800 else lo-0x1000))&0xFFFFFFFF
    los=lo if lo<0x800 else lo-0x1000
    if hi==0: return [addi(rd,0,los)]
    return [lui(rd,hi),addi(rd,rd,los)]

# ---------- 16-bit Zcb encoders (return a 16-bit int) ------------------------
def rp(x):  # 3-bit compressed reg field for x8..x15
    assert 8<=x<=15, f"reg x{x} not a compressed reg (x8..x15)"
    return x-8

# Q0 funct3=100 sub-word loads/stores.  rs1'=inst[9:7], rd'/rs2'=inst[4:2].
# Per Zcb spec:
#   C.LBU/C.SB (byte)     : uimm[1]=inst[5], uimm[0]=inst[6]        off 0..3
#   C.LHU/C.LH/C.SH (half): uimm[1]=inst[5]; inst[6] is funct bit   off 0 or 2
#                           (inst[6]=1 -> C.LH, inst[6]=0 -> LHU/SH)
def c_lbu(rd,rs1,off):
    assert off in (0,1,2,3)
    b_i5=(off>>1)&1; b_i6=off&1        # uimm[1]@inst5, uimm[0]@inst6
    return (0b100<<13)|(0b000<<10)|(rp(rs1)<<7)|(b_i5<<5)|(b_i6<<6)|(rp(rd)<<2)|0b00
def c_lhu(rd,rs1,off):
    assert off in (0,2)
    b_i5=(off>>1)&1
    return (0b100<<13)|(0b001<<10)|(rp(rs1)<<7)|(b_i5<<5)|(0<<6)|(rp(rd)<<2)|0b00
def c_lh(rd,rs1,off):
    assert off in (0,2)
    b_i5=(off>>1)&1
    return (0b100<<13)|(0b001<<10)|(rp(rs1)<<7)|(b_i5<<5)|(1<<6)|(rp(rd)<<2)|0b00
def c_sb(rs2,rs1,off):
    assert off in (0,1,2,3)
    b_i5=(off>>1)&1; b_i6=off&1
    return (0b100<<13)|(0b010<<10)|(rp(rs1)<<7)|(b_i5<<5)|(b_i6<<6)|(rp(rs2)<<2)|0b00
def c_sh(rs2,rs1,off):
    assert off in (0,2)
    b_i5=(off>>1)&1
    return (0b100<<13)|(0b011<<10)|(rp(rs1)<<7)|(b_i5<<5)|(0<<6)|(rp(rs2)<<2)|0b00

# Q1 funct3=100, inst[11:10]=11, inst[12]=1 -> Zcb.
def _q1_unary(rd,sel):  # inst[6:5]=11, inst[4:2]=sel
    return (0b100<<13)|(1<<12)|(0b11<<10)|(rp(rd)<<7)|(0b11<<5)|(sel<<2)|0b01
def c_zext_b(rd): return _q1_unary(rd,0b000)
def c_sext_b(rd): return _q1_unary(rd,0b001)
def c_zext_h(rd): return _q1_unary(rd,0b010)
def c_sext_h(rd): return _q1_unary(rd,0b011)
def c_not(rd):    return _q1_unary(rd,0b101)
def c_mul(rd,rs2):  # inst[6:5]=10, rs2'=inst[4:2]
    return (0b100<<13)|(1<<12)|(0b11<<10)|(rp(rd)<<7)|(0b10<<5)|(rp(rs2)<<2)|0b01

# ---------- assembler: byte stream -------------------------------------------
DMEM   = 0x80000000
TOHOST = 0x20000000

stream = []   # list of (size_in_bytes, value)
def w32(v): stream.append((4,u32(v)))
def w16(v): stream.append((2,v&0xFFFF))

fail_branches = []  # stream indices of guard branches
def guard(res_reg, exp_reg):
    fail_branches.append(len(stream))
    w32(bne(res_reg, exp_reg, 0))   # patched later

# ---- program ----------------------------------------------------------------
# compressed base register x8 = DMEM base
for ins in li(8, DMEM): w32(ins)

# ---- Test A: C.SB then C.LBU (unsigned byte round trip) ----
for ins in li(9,0xA5): w32(ins)      # x9 = 0xA5
w16(c_sb(9,8,3))                     # mem[base+3] = 0xA5
w16(c_lbu(10,8,3))                   # x10 = 0x000000A5
expA = 0xA5 if not NEG else 0xA6     # <-- negative control corrupts this one
for ins in li(15,expA): w32(ins)     # x15 = expected (full reg, ok)
guard(10,15)

# ---- Test B: C.SH then C.LHU (unsigned half round trip) ----
for ins in li(9,0xBEEF): w32(ins)
w16(c_sh(9,8,2))                    # mem[base+2..3] = 0xBEEF
w16(c_lhu(11,8,2))                  # x11 = 0x0000BEEF
for ins in li(15,0xBEEF): w32(ins)
guard(11,15)

# ---- Test C: C.SH then C.LH (signed half) ----
for ins in li(9,0x8001): w32(ins)   # stored low half; loads back sign-extended
w16(c_sh(9,8,0))                    # mem[base+0..1] = 0x8001
w16(c_lh(12,8,0))                   # x12 = 0xFFFF8001
for ins in li(15,0xFFFF8001): w32(ins)
guard(12,15)

# ---- Test D: C.MUL ----
for ins in li(13,7): w32(ins)
for ins in li(14,6): w32(ins)
w16(c_mul(13,14))                  # x13 = 7*6 = 42
for ins in li(15,42): w32(ins)
guard(13,15)

# ---- Test E: C.NOT ----
for ins in li(9,0x0F0F0F0F): w32(ins)
w16(c_not(9))                      # x9 = 0xF0F0F0F0
for ins in li(15,0xF0F0F0F0): w32(ins)
guard(9,15)

# ---- Test F: C.ZEXT.B ----
for ins in li(10,0x123456C7): w32(ins)
w16(c_zext_b(10))                  # x10 = 0x000000C7
for ins in li(15,0xC7): w32(ins)
guard(10,15)

# ---- Test G: C.SEXT.B ----
for ins in li(11,0x00000087): w32(ins)
w16(c_sext_b(11))                  # x11 = 0xFFFFFF87
for ins in li(15,0xFFFFFF87): w32(ins)
guard(11,15)

# ---- Test H: C.ZEXT.H ----
for ins in li(12,0xDEADBEEF): w32(ins)
w16(c_zext_h(12))                  # x12 = 0x0000BEEF
for ins in li(15,0xBEEF): w32(ins)
guard(12,15)

# ---- Test I: C.SEXT.H ----
for ins in li(13,0x00008123): w32(ins)
w16(c_sext_h(13))                  # x13 = 0xFFFF8123
for ins in li(15,0xFFFF8123): w32(ins)
guard(13,15)

# ---- success: tohost <- 1 ----
for ins in li(7,TOHOST): w32(ins)
for ins in li(6,1): w32(ins)
w32(sw(6,7,0))
spin_idx = len(stream); w32(jal(0,0))   # spin in place

# ---- FAIL block: tohost <- 2 ----
fail_idx = len(stream)
for ins in li(7,TOHOST): w32(ins)
for ins in li(6,2): w32(ins)
w32(sw(6,7,0))
w32(jal(0,0))

# ---------- compute byte offsets ---------------------------------------------
offsets=[]; acc=0
for sz,_ in stream:
    offsets.append(acc); acc+=sz
total_bytes=acc
fail_pc=offsets[fail_idx]

for idx in fail_branches:
    bpc=offsets[idx]; _,val=stream[idx]
    rs1=(val>>15)&0x1F; rs2=(val>>20)&0x1F
    stream[idx]=(4, bne(rs1,rs2, fail_pc-bpc))

# ---------- pack little-endian into 32-bit words -----------------------------
by=bytearray()
for sz,val in stream:
    for k in range(sz):
        by.append((val>>(8*k))&0xFF)
while len(by)%4: by.append(0x00)   # pad to word boundary

words=[]
for i in range(0,len(by),4):
    words.append(by[i] | (by[i+1]<<8) | (by[i+2]<<16) | (by[i+3]<<24))

out=Path(__file__).parent/"build"; out.mkdir(exist_ok=True)
hexpath=out/("zcb_neg.hex" if NEG else "zcb.hex")
hexpath.write_text("\n".join(f"{w:08x}" for w in words)+"\n")
print(f"Wrote {hexpath} — {len(words)} words, {total_bytes} bytes; "
      f"FAIL@0x{fail_pc:x} spin@0x{offsets[spin_idx]:x} NEG={NEG}")
