// ============================================================================
// tb_three_sipp_es_priv.sv — directed M/U + PMP testbench for 3-SIP-ESR SECURE=1.
//
//   vvp sim/tb_three_sipp_es_priv +IMEM=programs/build/priv_<name>.hex
//
// Instantiates three_sipp_es_core with SECURE(1) directly (no SoC), with a simple
// combinational memory covering IMEM (0x0000_0000..) and DRAM (0x8000_0000..).
// A store to tohost (0x2000_0000) ends the run: 1 => PASS, else FAIL(code).
// ============================================================================
`timescale 1ns/1ps

module tb_three_sipp_es_priv;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst;

  localparam int IMEM_WORDS = 8192;
  localparam int DRAM_WORDS = 8192;
  localparam [31:0] DRAM_BASE = 32'h8000_0000;
  localparam [31:0] TOHOST    = 32'h2000_0000;

  logic [31:0] mem  [0:IMEM_WORDS-1];   // low memory (fetch + data)
  logic [31:0] dram [0:DRAM_WORDS-1];   // high data window

  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic        dmem_re, dmem_we;
  logic [3:0]  dmem_be;

  // instruction fetch (combinational)
  assign imem_rdata = mem[imem_addr[$clog2(IMEM_WORDS)+1:2]];

  // data read (combinational)
  wire in_dram = (dmem_addr >= DRAM_BASE) && (dmem_addr < DRAM_BASE + DRAM_WORDS*4);
  wire in_low  = (dmem_addr < IMEM_WORDS*4);
  wire [$clog2(DRAM_WORDS)-1:0] dram_idx =
        dmem_addr[$clog2(DRAM_WORDS)+1:2] - DRAM_BASE[$clog2(DRAM_WORDS)+1:2];
  wire [$clog2(IMEM_WORDS)-1:0] low_idx = dmem_addr[$clog2(IMEM_WORDS)+1:2];
  assign dmem_rdata = in_dram ? dram[dram_idx] : in_low ? mem[low_idx] : 32'h0;

  logic        tohost_we;
  logic [31:0] tohost_val;

  wire [31:0] cur_dram = dram[dram_idx];
  wire [31:0] merged_dram = {
    dmem_be[3] ? dmem_wdata[31:24] : cur_dram[31:24],
    dmem_be[2] ? dmem_wdata[23:16] : cur_dram[23:16],
    dmem_be[1] ? dmem_wdata[15:8]  : cur_dram[15:8],
    dmem_be[0] ? dmem_wdata[7:0]   : cur_dram[7:0]
  };
  wire [31:0] cur_low = mem[low_idx];
  wire [31:0] merged_low = {
    dmem_be[3] ? dmem_wdata[31:24] : cur_low[31:24],
    dmem_be[2] ? dmem_wdata[23:16] : cur_low[23:16],
    dmem_be[1] ? dmem_wdata[15:8]  : cur_low[15:8],
    dmem_be[0] ? dmem_wdata[7:0]   : cur_low[7:0]
  };

  always_ff @(posedge clk) begin
    tohost_we <= 1'b0;
    if (dmem_we) begin
      if      (in_dram) dram[dram_idx] <= merged_dram;
      else if (dmem_addr == TOHOST) begin tohost_val <= dmem_wdata; tohost_we <= 1'b1; end
      else if (in_low)  mem[low_idx]   <= merged_low;
    end
  end

  three_sipp_es_core #(.SECURE(1'b1)) u_core (
    .clk(clk), .rst(rst),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
    .dmem_be(dmem_be), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
    .irq_timer(1'b0), .irq_soft(1'b0), .irq_ext(1'b0),
    .retire_valid(), .retire_pc(), .retire_instr(),
    .retire_rd_we(), .retire_rd(), .retire_rd_val(),
    .dbg_haltreq(1'b0), .dbg_resumereq(1'b0), .dbg_halted(),
    .dbg_ar_valid(1'b0), .dbg_ar_write(1'b0), .dbg_ar_csr(1'b0),
    .dbg_ar_regno(12'd0), .dbg_ar_wdata(32'd0), .dbg_ar_rdata(), .dbg_ar_done()
  );

  string imem_file;
  integer i, cycle = 0;
  initial begin
    if (!$value$plusargs("IMEM=%s", imem_file)) begin
      $display("FATAL: no +IMEM"); $finish;
    end
    for (i = 0; i < IMEM_WORDS; i = i + 1) mem[i]  = 32'h0000_0013;
    for (i = 0; i < DRAM_WORDS; i = i + 1) dram[i] = 32'h0;
    $readmemh(imem_file, mem);
    rst = 1'b1; repeat (4) @(posedge clk); rst = 1'b0;
  end

  always @(posedge clk) begin
    if (!rst) cycle <= cycle + 1;
    if (tohost_we) begin
      if (tohost_val == 32'd1) $display("RESULT: PASS");
      else                     $display("RESULT: FAIL code=%0d", tohost_val);
      $finish;
    end
    if (cycle > 200000) begin $display("RESULT: FAIL timeout"); $finish; end
  end
endmodule
