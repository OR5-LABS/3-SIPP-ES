// ============================================================================
// three_sipp_es_pkg.sv — Shared types, opcodes & CSR constants for 3-SIPP-ES.
//
// 3-SIPP-ES is a compact, high-performance 3-stage in-order RV32IMAC core.
// This package holds the datapath types used across the core and its leaf cells.
// ============================================================================
`ifndef THREE_SIPP_ES_PKG_SV
`define THREE_SIPP_ES_PKG_SV

package three_sipp_es_pkg;

  // ---- Word geometry -------------------------------------------------------
  localparam int unsigned XLEN = 32;

  // ---- Major opcodes (instr[6:0]) -----------------------------------------
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_OPIMM  = 7'b0010011;
  localparam logic [6:0] OP_OP     = 7'b0110011;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;

  // ---- ALU operations (base RV32I + Zbb/Zba/Zbs/Zbc bit-manipulation) -------
  // Enum stays [5:0]: base RV32I + Zbb = 28 ops, + Zba/Zbs = 35, + Zbc = 38 (<64).
  typedef enum logic [5:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND,
    ALU_PASS_B,  // pass operand B straight through (LUI)
    // ---- Zbb ----
    ALU_ANDN, ALU_ORN, ALU_XNOR,           // logical with negate
    ALU_MIN, ALU_MINU, ALU_MAX, ALU_MAXU,  // min/max
    ALU_CLZ, ALU_CTZ, ALU_CPOP,            // count leading/trailing zeros, popcount
    ALU_SEXTB, ALU_SEXTH, ALU_ZEXTH,       // sign/zero extend byte/half
    ALU_ROL, ALU_ROR,                      // rotate left/right
    ALU_REV8, ALU_ORCB,                    // byte-reverse, OR-combine bytes
    // ---- Zba (address generation) ----
    ALU_SH1ADD, ALU_SH2ADD, ALU_SH3ADD,    // (rs1 << {1,2,3}) + rs2
    // ---- Zbs (single-bit) ----
    ALU_BSET, ALU_BCLR, ALU_BINV, ALU_BEXT, // set/clear/invert/extract bit @ b[4:0]
    // ---- Zbc (carry-less multiply) ----
    ALU_CLMUL, ALU_CLMULH, ALU_CLMULR,     // carry-less mul: low / high / reversed
    // ---- Zicond (conditional zero) ----
    ALU_CZEQZ, ALU_CZNEZ                   // czero.eqz / czero.nez
  } alu_op_e;

  // ---- M-extension operations ---------------------------------------------
  typedef enum logic [2:0] {
    MD_MUL, MD_MULH, MD_MULHSU, MD_MULHU,
    MD_DIV, MD_DIVU, MD_REM, MD_REMU
  } md_op_e;

  // ---- Branch/compare functions -------------------------------------------
  typedef enum logic [2:0] {
    BR_EQ, BR_NE, BR_LT, BR_GE, BR_LTU, BR_GEU, BR_NONE
  } br_op_e;

  // ---- Writeback source ----------------------------------------------------
  typedef enum logic [2:0] {
    WB_ALU, WB_MEM, WB_PC4, WB_CSR, WB_MD
  } wb_sel_e;

  // ---- Trap causes (mcause, interrupt bit = 0) ----------------------------
  localparam logic [3:0] CAUSE_ILLEGAL    = 4'd2;
  localparam logic [3:0] CAUSE_BREAKPOINT = 4'd3;
  localparam logic [3:0] CAUSE_ECALL_M    = 4'd11;

  // ---- CSR addresses we implement -----------------------------------------
  localparam logic [11:0] CSR_MSTATUS  = 12'h300;
  localparam logic [11:0] CSR_MIE      = 12'h304;
  localparam logic [11:0] CSR_MTVEC    = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH = 12'h340;
  localparam logic [11:0] CSR_MEPC     = 12'h341;
  localparam logic [11:0] CSR_MCAUSE   = 12'h342;
  localparam logic [11:0] CSR_MTVAL    = 12'h343;
  localparam logic [11:0] CSR_MIP      = 12'h344;
  localparam logic [11:0] CSR_MCYCLE   = 12'hB00;
  localparam logic [11:0] CSR_MINSTRET = 12'hB02;
  localparam logic [11:0] CSR_MCYCLEH  = 12'hB80;
  localparam logic [11:0] CSR_MINSTRETH= 12'hB82;

  // ---- Zihpm/Zicntr hardware performance monitor counters -----------------
  // mhpmcounter3..6 (0xB03..0xB06) + high halves (0xB83..0xB86), and their
  // event selectors mhpmevent3..6 (0x323..0x326). Event codes (mhpmeventN):
  //   0 = disabled, 1 = cycle, 2 = instret(retire), 3 = branch,
  //   4 = taken-branch, 5 = load, 6 = store.
  localparam logic [11:0] CSR_MHPMCOUNTER3 = 12'hB03;
  localparam logic [11:0] CSR_MHPMCOUNTER4 = 12'hB04;
  localparam logic [11:0] CSR_MHPMCOUNTER5 = 12'hB05;
  localparam logic [11:0] CSR_MHPMCOUNTER6 = 12'hB06;
  localparam logic [11:0] CSR_MHPMCOUNTER3H = 12'hB83;
  localparam logic [11:0] CSR_MHPMCOUNTER4H = 12'hB84;
  localparam logic [11:0] CSR_MHPMCOUNTER5H = 12'hB85;
  localparam logic [11:0] CSR_MHPMCOUNTER6H = 12'hB86;
  localparam logic [11:0] CSR_MHPMEVENT3 = 12'h323;
  localparam logic [11:0] CSR_MHPMEVENT4 = 12'h324;
  localparam logic [11:0] CSR_MHPMEVENT5 = 12'h325;
  localparam logic [11:0] CSR_MHPMEVENT6 = 12'h326;

  // hpm event codes
  localparam logic [5:0] HPM_EV_CYCLE   = 6'd1;
  localparam logic [5:0] HPM_EV_INSTRET = 6'd2;
  localparam logic [5:0] HPM_EV_BRANCH  = 6'd3;
  localparam logic [5:0] HPM_EV_BRTAKEN = 6'd4;
  localparam logic [5:0] HPM_EV_LOAD    = 6'd5;
  localparam logic [5:0] HPM_EV_STORE   = 6'd6;
  localparam logic [11:0] CSR_MISA     = 12'h301;
  localparam logic [11:0] CSR_MVENDORID= 12'hF11;
  localparam logic [11:0] CSR_MARCHID  = 12'hF12;
  localparam logic [11:0] CSR_MHARTID  = 12'hF14;

endpackage : three_sipp_es_pkg

`endif
