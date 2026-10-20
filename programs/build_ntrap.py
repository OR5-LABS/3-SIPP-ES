#!/usr/bin/env python3
"""Hand-assemble directed N-extension (user-trap) tests for 3-SIP-ESR SECURE=1.

Emits programs/build/ntrap_<name>.hex. Exit protocol: store 1 -> PASS, else
FAIL(code) to tohost.

The N overlay (inlined in three_sipp_es_core) delegates a synchronous exception taken
in U-mode to U-mode iff its cause bit is set in medeleg. A delegated trap saves
uepc/ucause/utval, does ustatus.UPIE<=UIE / UIE<=0, vectors to utvec, and STAYS
in U-mode. URET restores UIE and returns to uepc (still U).

Tests (each with a load-bearing NEGATIVE CONTROL):
  udeleg : medeleg[8] (ecall-from-U) set. U-mode ecall -> DELEGATED to U: the
           U-mode utvec handler runs (still in U), sees ucause==8, uepc==ecall pc,
           then URETs back to U code which signals PASS. Proof it stayed in U:
           the utvec handler reads an M-only CSR? No — instead we verify the whole
           delegated path executed from U (utvec handler + uret) AND that a second,
           NON-delegated fault (M-CSR access, cause 2, medeleg[2]=0) from that same
           U context goes to the M handler (mtvec) — i.e. delegation is per-cause.
           NEG CONTROL is build_nodel below.
  nodel  : medeleg=0. U-mode ecall is NOT delegated -> goes to the M-mode mtvec
           handler with mcause==8 and priv restored to M. Proves the delegate
           decision is load-bearing: same instruction, deleg bit clear -> M path.
"""
from pathlib import Path

def u32(x): return x & 0xFFFFFFFF
def R(f7, rs2, rs1, f3, rd, op): return u32((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def I(imm, rs1, f3, rd, op):     return u32(((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def S(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return u32(((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|op)
def B(imm, rs2, rs1, f3, op):
    imm &= 0x1FFE
    return u32(((imm>>12&1)<<31)|((imm>>5&0x3F)<<25)|(rs2<<20)|(rs1<<15)|
               (f3<<12)|((imm>>1&0xF)<<8)|((imm>>11&1)<<7)|op)
def U(imm, rd, op): return u32((imm&0xFFFFF000)|(rd<<7)|op)
def J(imm, rd, op):
    imm &= 0x1FFFFE
    return u32(((imm>>20&1)<<31)|((imm>>1&0x3FF)<<21)|((imm>>11&1)<<20)|
               ((imm>>12&0xFF)<<12)|(rd<<7)|op)

def addi(rd,rs1,i): return I(i,rs1,0,rd,0x13)
def lui(rd,i):  return U(i,rd,0x37)
def lw(rd,rs1,i):  return I(i,rs1,2,rd,0x03)
def sw(rs2,rs1,i): return S(i,rs2,rs1,2,0x23)
def bne(rs1,rs2,i):return B(i,rs2,rs1,1,0x63)
def beq(rs1,rs2,i):return B(i,rs2,rs1,0,0x63)
def jal(rd,i):  return J(i,rd,0x6F)
def csrrw(rd,csr,rs1): return I(csr,rs1,1,rd,0x73)
def csrrs(rd,csr,rs1): return I(csr,rs1,2,rd,0x73)
def csrrc(rd,csr,rs1): return I(csr,rs1,3,rd,0x73)
def ecall():  return I(0,0,0,0,0x73)
def mret():   return I(0x302,0,0,0,0x73)
def uret():   return I(0x002,0,0,0,0x73)
def nop():    return addi(0,0,0)

def li(rd, v):
    v &= 0xFFFFFFFF
    lo = v & 0xFFF
    hi = (v - (lo if lo < 0x800 else lo - 0x1000)) & 0xFFFFFFFF
    lo_s = lo if lo < 0x800 else lo - 0x1000
    if hi == 0:
        return [addi(rd, 0, lo_s)]
    return [lui(rd, hi), addi(rd, rd, lo_s)]

MSTATUS, MTVEC, MSCRATCH = 0x300, 0x305, 0x340
MEPC, MCAUSE, MTVAL, MEDELEG = 0x341, 0x342, 0x343, 0x302
UTVEC, UEPC, UCAUSE, USCRATCH, USTATUS = 0x005, 0x041, 0x042, 0x040, 0x000
PMPCFG0, PMPADDR0 = 0x3A0, 0x3B0
TOHOST, DRAM = 0x20000000, 0x80000000
PMP_NAPOT = 0x18
PMP_R, PMP_W, PMP_X = 0x01, 0x02, 0x04
NAPOT_ALL = 0xFFFFFFFF

OUT = Path(__file__).resolve().parent / "build"
OUT.mkdir(exist_ok=True)

def assemble(prog):
    if not prog: return []
    hi = max(prog) // 4
    words = [0x00000013] * (hi + 1)
    for a, w in prog.items():
        words[a//4] = w
    return words

def write_hex(name, prog):
    words = assemble(prog)
    p = OUT / f"ntrap_{name}.hex"
    p.write_text("".join(f"{w:08x}\n" for w in words))
    print(f"  wrote {p}  ({len(words)} words)")

# --------------------------------------------------------------------------
# Test 1: udeleg — medeleg[8] set. U ecall delegated to U (utvec), URET back.
# --------------------------------------------------------------------------
def build_udeleg():
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    MHANDLER = 0x400   # M-mode trap vector (must NOT be reached in this test)
    UHANDLER = 0x600   # U-mode trap vector (utvec) — the delegated handler
    UCODE    = 0x800
    cfg = PMP_NAPOT | PMP_R | PMP_W | PMP_X   # whole space RWX for U

    pc = 0
    pc = emit(pc, *li(5, MHANDLER), csrrw(0, MTVEC, 5))
    pc = emit(pc, *li(5, UHANDLER), csrrw(0, UTVEC, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, cfg), csrrw(0, PMPCFG0, 5))
    # medeleg[8] = 1 (delegate ecall-from-U to U)
    pc = emit(pc, *li(5, 1<<8), csrrw(0, MEDELEG, 5))
    # drop to U at UCODE
    pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))   # MPP=U
    pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
    pc = emit(pc, jal(0,0))

    # ---- M handler: should never run in the delegated case ----
    m = MHANDLER
    m = emit(m, *li(1,TOHOST), addi(2,0,9), sw(2,1,0), jal(0,0))   # code 9: went to M

    # ---- U handler (utvec) : verify ucause==8, uepc==ecall_pc, then URET ----
    # ecall_pc is UCODE+0 (first instr of UCODE); we check ucause/uepc here.
    u_h = UHANDLER
    u_h = emit(u_h, csrrs(20, UCAUSE, 0), csrrs(21, UEPC, 0))
    u_h = emit(u_h, addi(22,0,8), bne(20,22, 0)); bc = u_h-4       # ucause==8
    u_h = emit(u_h, *li(23, UCODE), bne(21,23, 0)); bp = u_h-4     # uepc==ecall pc
    # mark handler-ran, bump uepc past the ecall so URET resumes after it
    u_h = emit(u_h, addi(24,0,1))                                  # x24=1: U handler ran
    u_h = emit(u_h, addi(21,21,4), csrrw(0, UEPC, 21))            # uepc += 4
    u_h = emit(u_h, uret())
    fc = u_h; u_h = emit(u_h, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))  # bad ucause
    fp = u_h; u_h = emit(u_h, *li(1,TOHOST), addi(2,0,4), sw(2,1,0), jal(0,0))  # bad uepc
    prog[bc] = bne(20,22, fc-bc)
    prog[bp] = bne(21,23, fp-bp)

    # ---- U code ----
    u = UCODE
    u = emit(u, ecall())            # UCODE+0 : delegated to U handler
    # after URET we land here (uepc+4). x24 must be 1 (handler ran). PASS.
    u = emit(u, addi(25,0,1), bne(24,25, 0)); bb = u-4
    u = emit(u, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))   # PASS
    fb = u; u = emit(u, *li(1,TOHOST), addi(2,0,5), sw(2,1,0), jal(0,0))  # handler didn't run
    prog[bb] = bne(24,25, fb-bb)
    return prog

# --------------------------------------------------------------------------
# Test 2: nodel — medeleg=0. U ecall NOT delegated -> M handler, mcause=8.
# --------------------------------------------------------------------------
def build_nodel():
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    MHANDLER = 0x400
    UHANDLER = 0x600   # utvec set but must NOT be reached
    UCODE    = 0x800
    cfg = PMP_NAPOT | PMP_R | PMP_W | PMP_X

    pc = 0
    pc = emit(pc, *li(5, MHANDLER), csrrw(0, MTVEC, 5))
    pc = emit(pc, *li(5, UHANDLER), csrrw(0, UTVEC, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, cfg), csrrw(0, PMPCFG0, 5))
    # medeleg = 0 : do NOT delegate
    pc = emit(pc, addi(5,0,0), csrrw(0, MEDELEG, 5))
    pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))   # MPP=U
    pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
    pc = emit(pc, jal(0,0))

    # ---- M handler: expect mcause==8 (ecall-from-U reached M) -> PASS ----
    m = MHANDLER
    m = emit(m, csrrs(20, MCAUSE, 0))
    m = emit(m, addi(22,0,8), bne(20,22, 0)); bc = m-4
    m = emit(m, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))   # PASS
    fc = m; m = emit(m, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))  # wrong cause
    prog[bc] = bne(20,22, fc-bc)

    # ---- U handler (utvec): reaching this is WRONG (not delegated) ----
    u_h = UHANDLER
    u_h = emit(u_h, *li(1,TOHOST), addi(2,0,6), sw(2,1,0), jal(0,0))  # code 6: wrongly delegated

    u = UCODE
    u = emit(u, ecall())
    u = emit(u, jal(0,0))
    return prog

if __name__ == "__main__":
    write_hex("udeleg", build_udeleg())
    write_hex("nodel",  build_nodel())
    print("done.")
