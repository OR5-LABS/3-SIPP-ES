#!/usr/bin/env python3
"""Hand-assemble directed HW-trigger (mcontrol6) tests for 3-SIPP-ES.

Emits programs/build/trig_<name>.hex (one 32-bit word/line, for $readmemh).
Exit protocol (family TB): store 1 -> PASS, other -> FAIL(code) to tohost.

The trigger unit is inlined in three_sipp_es_core (tselect 0x7A0 / tdata1 0x7A1 /
tdata2 0x7A2 / tinfo 0x7A4). Two slots, each an mcontrol6 type-6 trigger:
  tdata1 bits: [31:28]=type(6) [21]=hit0(sticky) [15:12]=action(0=exc,1=debug)
               [6]=m(match-in-M) [2]=execute [1]=store [0]=load
We drive action=0 so a match raises a BREAKPOINT EXCEPTION (mcause=3, mtval=
matched PC/addr) — fully observable through the same tohost/trap protocol the
priv tests use (no debug-module dance needed).

Tests (each with a load-bearing NEGATIVE CONTROL):
  exec  : an EXECUTE (PC-match) trigger armed at the PC of a marker instruction
          fires a breakpoint exc (mcause=3, mtval==that PC) BEFORE it commits.
          NEG CONTROL (exec_miss): arm the trigger one instruction EARLIER's
          neighbour PC (a near-miss address that is never fetched as a distinct
          match) -> no fire, program runs to a clean PASS.
  store : a STORE (address-match) watchpoint armed at a data address fires a
          breakpoint exc (mcause=3, mtval==that addr) when the store executes.
          NEG CONTROL (store_miss): arm it at addr+4 (a near-miss) -> the store
          to addr does NOT fire; program completes the store and PASSes.
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
def add(rd,rs1,rs2):return R(0,rs2,rs1,0,rd,0x33)
def lui(rd,i):  return U(i,rd,0x37)
def lw(rd,rs1,i):  return I(i,rs1,2,rd,0x03)
def sw(rs2,rs1,i): return S(i,rs2,rs1,2,0x23)
def bne(rs1,rs2,i):return B(i,rs2,rs1,1,0x63)
def jal(rd,i):  return J(i,rd,0x6F)
def csrrw(rd,csr,rs1): return I(csr,rs1,1,rd,0x73)
def csrrs(rd,csr,rs1): return I(csr,rs1,2,rd,0x73)
def csrrc(rd,csr,rs1): return I(csr,rs1,3,rd,0x73)
def ebreak(): return I(1,0,0,0,0x73)
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
MEPC, MCAUSE, MTVAL = 0x341, 0x342, 0x343
TSELECT, TDATA1, TDATA2 = 0x7A0, 0x7A1, 0x7A2
TOHOST, DRAM = 0x20000000, 0x80000000

TTYPE6 = 6 << 28
T_M    = 1 << 6      # match-in-M
T_EXEC = 1 << 2
T_STORE= 1 << 1
T_LOAD = 1 << 0
# action nibble at [15:12]; 0 = breakpoint exception

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
    p = OUT / f"trig_{name}.hex"
    p.write_text("".join(f"{w:08x}\n" for w in words))
    print(f"  wrote {p}  ({len(words)} words)")

# ---------------------------------------------------------------------------
# Two-pass emitter: we need the ABSOLUTE PC of a specific marker instruction to
# arm an EXECUTE trigger on it. So we build the body once to discover the marker
# PC, then patch tdata2 with it (arm=hit) or with a near-miss (arm=miss).
# ---------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Test 1: exec — PC-match EXECUTE breakpoint.
# --------------------------------------------------------------------------
def build_exec(hit):
    """hit=True  -> arm trigger at the marker's real PC -> breakpoint exc fires.
       hit=False -> arm at (marker_pc + 2), a halfword-misaligned address that
                    NO 4-byte-aligned instruction fetch ever equals -> no fire
                    (load-bearing negative control), clean PASS."""
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER = 0x400

    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    # select slot 0, program tdata1 = exec trigger, action=0 (exception)
    pc = emit(pc, addi(5,0,0), csrrw(0, TSELECT, 5))
    pc = emit(pc, *li(5, TTYPE6 | T_M | T_EXEC), csrrw(0, TDATA1, 5))
    # tdata2 patched after we know the marker PC. Reserve a FIXED 2-word (lui+addi)
    # placeholder regardless of the value, so patching never shifts later PCs.
    tdata2_slot = pc
    pc = emit(pc, lui(6, 0x80000), addi(6, 6, 0), csrrw(0, TDATA2, 6))
    # x18 marks "reached marker"; the MARKER instruction is the one we trigger on.
    pc = emit(pc, addi(18,0,0))
    marker_pc = pc
    pc = emit(pc, addi(18,0,1))          # MARKER: sets x18=1
    # if execution reaches here in the HIT case, the trigger did NOT fire -> FAIL
    if hit:
        pc = emit(pc, *li(1,TOHOST), addi(2,0,6), sw(2,1,0), jal(0,0))  # code 6: no fire
    else:
        # negative control: no trigger expected. marker ran; verify x18==1, PASS.
        pc = emit(pc, addi(19,0,1), bne(18,19, 0)); b = pc-4
        pc = emit(pc, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        f = pc; pc = emit(pc, *li(1,TOHOST), addi(2,0,7), sw(2,1,0), jal(0,0))
        prog[b] = bne(18,19, f-b)

    # ---- handler: expect breakpoint (mcause=3), mtval==marker_pc ----
    h = HANDLER
    h = emit(h, csrrs(20, MCAUSE, 0), csrrs(21, MTVAL, 0))
    if hit:
        h = emit(h, addi(22,0,3), bne(20,22, 0)); bc = h-4          # breakpoint = 3
        h = emit(h, *li(23, marker_pc), bne(21,23, 0)); bt = h-4    # mtval == marker PC
        # x18 must still be 0 (trigger fired BEFORE the marker committed)
        h = emit(h, bne(18,0, 0)); bx = h-4
        h = emit(h, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        fc = h; h = emit(h, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))  # wrong cause
        ft = h; h = emit(h, *li(1,TOHOST), addi(2,0,4), sw(2,1,0), jal(0,0))  # wrong tval
        fx = h; h = emit(h, *li(1,TOHOST), addi(2,0,5), sw(2,1,0), jal(0,0))  # x18 already set
        prog[bc] = bne(20,22, fc-bc)
        prog[bt] = bne(21,23, ft-bt)
        prog[bx] = bne(18,0, fx-bx)
    else:
        # neg control: ANY trap here is wrong.
        h = emit(h, *li(1,TOHOST), addi(2,0,8), sw(2,1,0), jal(0,0))  # code 8: unexpected trap

    # ---- patch tdata2 with marker PC (hit) or a near-miss neighbour (miss) ----
    tgt = marker_pc if hit else (marker_pc + 2)
    lo = tgt & 0xFFF
    hi_v = (tgt - (lo if lo < 0x800 else lo - 0x1000)) & 0xFFFFFFFF
    lo_s = lo if lo < 0x800 else lo - 0x1000
    prog[tdata2_slot]   = lui(6, hi_v)
    prog[tdata2_slot+4] = addi(6, 6, lo_s)
    return prog

# --------------------------------------------------------------------------
# Test 2: store — address-match STORE watchpoint.
# --------------------------------------------------------------------------
def build_store(hit):
    """hit=True  -> watchpoint at DRAM addr == the store target -> exc fires.
       hit=False -> watchpoint at DRAM+4 (near-miss) -> store to DRAM proceeds,
                    program reads it back and PASSes (negative control)."""
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER = 0x400
    WADDR   = DRAM + 0x40
    watch   = WADDR if hit else (WADDR + 4)

    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    pc = emit(pc, addi(5,0,0), csrrw(0, TSELECT, 5))
    pc = emit(pc, *li(5, TTYPE6 | T_M | T_STORE), csrrw(0, TDATA1, 5))
    pc = emit(pc, *li(6, watch), csrrw(0, TDATA2, 6))
    # the guarded store: sw x7 -> [x6=WADDR]
    pc = emit(pc, *li(6, WADDR), addi(7,0,0x77))
    store_pc = pc
    pc = emit(pc, sw(7,6,0))
    # if we get past the store in the HIT case, the watchpoint failed to fire.
    if hit:
        pc = emit(pc, *li(1,TOHOST), addi(2,0,6), sw(2,1,0), jal(0,0))  # code 6: no fire
    else:
        # neg control: store must have completed. Read back, verify, PASS.
        pc = emit(pc, lw(8,6,0), addi(9,0,0x77), bne(8,9, 0)); b = pc-4
        pc = emit(pc, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        f = pc; pc = emit(pc, *li(1,TOHOST), addi(2,0,7), sw(2,1,0), jal(0,0))
        prog[b] = bne(8,9, f-b)

    h = HANDLER
    h = emit(h, csrrs(20, MCAUSE, 0), csrrs(21, MTVAL, 0))
    if hit:
        h = emit(h, addi(22,0,3), bne(20,22, 0)); bc = h-4           # breakpoint = 3
        h = emit(h, *li(23, WADDR), bne(21,23, 0)); bt = h-4         # mtval == store addr
        # the store must NOT have taken effect (fired before commit): [WADDR]==0
        h = emit(h, *li(24, WADDR), lw(25,24,0), bne(25,0, 0)); bs = h-4
        h = emit(h, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        fc = h; h = emit(h, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))  # wrong cause
        ft = h; h = emit(h, *li(1,TOHOST), addi(2,0,4), sw(2,1,0), jal(0,0))  # wrong tval
        fs = h; h = emit(h, *li(1,TOHOST), addi(2,0,5), sw(2,1,0), jal(0,0))  # store leaked
        prog[bc] = bne(20,22, fc-bc)
        prog[bt] = bne(21,23, ft-bt)
        prog[bs] = bne(25,0, fs-bs)
    else:
        h = emit(h, *li(1,TOHOST), addi(2,0,8), sw(2,1,0), jal(0,0))  # code 8: unexpected trap
    return prog

if __name__ == "__main__":
    write_hex("exec_hit",   build_exec(hit=True))
    write_hex("exec_miss",  build_exec(hit=False))
    write_hex("store_hit",  build_store(hit=True))
    write_hex("store_miss", build_store(hit=False))
    print("done.")
