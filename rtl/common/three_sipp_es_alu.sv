// ============================================================================
// three_sipp_es_alu.sv — Combinational RV32I ALU.
// ============================================================================
`include "three_sipp_es_pkg.sv"

module three_sipp_es_alu
  import three_sipp_es_pkg::*;
(
  input  alu_op_e          op,
  input  logic [XLEN-1:0]  a,
  input  logic [XLEN-1:0]  b,
  output logic [XLEN-1:0]  y
);
  logic [4:0] shamt;
  assign shamt = b[4:0];

  // ---- Zbb helpers ---------------------------------------------------------
  // count leading zeros of a (0..32)
  function automatic [5:0] clz32(input [31:0] v);
    integer i; logic done;
    clz32 = 6'd32; done = 1'b0;
    for (i = 31; i >= 0; i = i - 1) if (!done && v[i]) begin clz32 = 6'd31 - i[5:0]; done = 1'b1; end
  endfunction
  function automatic [5:0] ctz32(input [31:0] v);
    integer i; logic done;
    ctz32 = 6'd32; done = 1'b0;
    for (i = 0; i < 32; i = i + 1) if (!done && v[i]) begin ctz32 = i[5:0]; done = 1'b1; end
  endfunction
  function automatic [5:0] cpop32(input [31:0] v);
    integer i; cpop32 = 6'd0;
    for (i = 0; i < 32; i = i + 1) cpop32 = cpop32 + {5'd0, v[i]};
  endfunction

  // ---- Zbc helper: 64-bit carry-less product of a and b -------------------
  // clmul_full = XOR over i in 0..31 of (a << i) whenever b[i]==1.
  // Result is at most 63 bits (bit 63 always 0).
  function automatic [63:0] clmul_full(input [31:0] x, input [31:0] yv);
    integer i;
    clmul_full = 64'd0;
    for (i = 0; i < 32; i = i + 1)
      if (yv[i]) clmul_full = clmul_full ^ ({32'd0, x} << i);
  endfunction
  wire [63:0] clp = clmul_full(a, b);

  wire [31:0] rev8  = {a[7:0], a[15:8], a[23:16], a[31:24]};
  wire [31:0] orcb  = {{8{|a[31:24]}}, {8{|a[23:16]}}, {8{|a[15:8]}}, {8{|a[7:0]}}};
  wire [31:0] rol   = (a << shamt) | (a >> ((32 - shamt) & 6'd31));
  wire [31:0] ror   = (a >> shamt) | (a << ((32 - shamt) & 6'd31));

  always_comb begin
    unique case (op)
      ALU_ADD:    y = a + b;
      ALU_SUB:    y = a - b;
      ALU_SLL:    y = a << shamt;
      ALU_SLT:    y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU:   y = (a < b)                   ? 32'd1 : 32'd0;
      ALU_XOR:    y = a ^ b;
      ALU_SRL:    y = a >> shamt;
      ALU_SRA:    y = $unsigned($signed(a) >>> shamt);
      ALU_OR:     y = a | b;
      ALU_AND:    y = a & b;
      ALU_PASS_B: y = b;
      // ---- Zbb ----
      ALU_ANDN:   y = a & ~b;
      ALU_ORN:    y = a | ~b;
      ALU_XNOR:   y = ~(a ^ b);
      ALU_MIN:    y = ($signed(a) < $signed(b)) ? a : b;
      ALU_MINU:   y = (a < b) ? a : b;
      ALU_MAX:    y = ($signed(a) > $signed(b)) ? a : b;
      ALU_MAXU:   y = (a > b) ? a : b;
      ALU_CLZ:    y = {26'd0, clz32(a)};
      ALU_CTZ:    y = {26'd0, ctz32(a)};
      ALU_CPOP:   y = {26'd0, cpop32(a)};
      ALU_SEXTB:  y = {{24{a[7]}},  a[7:0]};
      ALU_SEXTH:  y = {{16{a[15]}}, a[15:0]};
      ALU_ZEXTH:  y = {16'd0, a[15:0]};
      ALU_ROL:    y = rol;
      ALU_ROR:    y = ror;
      ALU_REV8:   y = rev8;
      ALU_ORCB:   y = orcb;
      // ---- Zba ----
      ALU_SH1ADD: y = (a << 1) + b;
      ALU_SH2ADD: y = (a << 2) + b;
      ALU_SH3ADD: y = (a << 3) + b;
      // ---- Zbs (index = shamt = b[4:0]) ----
      ALU_BSET:   y = a |  (32'd1 << shamt);
      ALU_BCLR:   y = a & ~(32'd1 << shamt);
      ALU_BINV:   y = a ^  (32'd1 << shamt);
      ALU_BEXT:   y = {31'd0, a[shamt]};
      // ---- Zbc (carry-less multiply) ----
      ALU_CLMUL:  y = clp[31:0];    // low  32 bits
      ALU_CLMULH: y = clp[63:32];   // high bits (bit 63 == 0)
      ALU_CLMULR: y = clp[62:31];   // reversed variant (bits 62..31)
      // ---- Zicond (conditional zero; a=rs1, b=rs2) ----
      ALU_CZEQZ:  y = (b == 32'd0) ? 32'd0 : a;   // czero.eqz rd = (rs2==0)?0:rs1
      ALU_CZNEZ:  y = (b != 32'd0) ? 32'd0 : a;   // czero.nez rd = (rs2!=0)?0:rs1
      default:    y = '0;
    endcase
  end
endmodule
