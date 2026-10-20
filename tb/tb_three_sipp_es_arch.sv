// ============================================================================
// tb_three_sipp_es_arch.sv — Architectural compliance testbench for 3-SIPP-ES.
//
//   sim/tb_three_sipp_es_arch +IMEM=<hex> +SIGNATURE=<sig_out> \
//                             +SIG_BEGIN=0x... +SIG_END=0x...
// ============================================================================
`timescale 1ns/1ps

module tb_three_sipp_es_arch;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst;

  localparam int MEM_WORDS = 524288;  // 2 MB memory
  localparam [31:0] TOHOST = 32'h2000_0000;

  logic [31:0] mem [0:MEM_WORDS-1];

  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic        dmem_re, dmem_we;
  logic [3:0]  dmem_be;

  wire in_mem = (dmem_addr < MEM_WORDS*4);
  wire [$clog2(MEM_WORDS)-1:0] mem_idx  = dmem_addr[$clog2(MEM_WORDS)+1:2];
  wire [$clog2(MEM_WORDS)-1:0] ifetch_idx = imem_addr[$clog2(MEM_WORDS)+1:2];

  assign imem_rdata = mem[ifetch_idx];
  assign dmem_rdata = in_mem ? mem[mem_idx] : 32'h0;

  wire [31:0] cur_mem = mem[mem_idx];
  wire [31:0] merged_mem = {
    dmem_be[3] ? dmem_wdata[31:24] : cur_mem[31:24],
    dmem_be[2] ? dmem_wdata[23:16] : cur_mem[23:16],
    dmem_be[1] ? dmem_wdata[15:8]  : cur_mem[15:8],
    dmem_be[0] ? dmem_wdata[7:0]   : cur_mem[7:0]
  };

  logic        tohost_we;
  logic [31:0] tohost_val;

  always_ff @(posedge clk) begin
    tohost_we <= 1'b0;
    if (dmem_we) begin
      if (dmem_addr == TOHOST) begin
        tohost_val <= dmem_wdata;
        tohost_we  <= 1'b1;
      end else if (in_mem) begin
        mem[mem_idx] <= merged_mem;
      end
    end
  end

  three_sipp_es_core #(.SECURE(1'b0)) u_core (
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

  string imem_file, sig_file;
  integer sig_begin = 0, sig_end = 0;
  integer sig_fd;
  integer i, cycle = 0;
  integer max_cycles = 1000000;

  integer trace_en = 0;

  initial begin
    if (!$value$plusargs("IMEM=%s", imem_file)) begin
      $display("FATAL: no +IMEM=<file> given");
      $finish;
    end
    if ($value$plusargs("TRACE=%d", trace_en)) ;
    if ($value$plusargs("MAXCYCLES=%d", max_cycles)) ;
    for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 32'h0000_0013; // NOP fill
    $readmemh(imem_file, mem);

    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
  end

  always @(posedge clk) begin
    if (!rst) cycle <= cycle + 1;
    if (!rst && trace_en && cycle < 100)
      $display("cyc=%0d pc=%08x instr=%08x", cycle, u_core.pc, u_core.fx_instr);
    if (!rst && u_core.m_trap_set)
      $display("TRAP! cause=%0d epc=%08x tval=%08x", u_core.ex_cause, u_core.fx_pc, u_core.ex_tval);

    if (tohost_we) begin
      if ($value$plusargs("SIGNATURE=%s", sig_file) &&
          $value$plusargs("SIG_BEGIN=0x%x", sig_begin) &&
          $value$plusargs("SIG_END=0x%x", sig_end)) begin
        sig_fd = $fopen(sig_file, "w");
        if (sig_fd) begin
          for (integer a = sig_begin; a < sig_end; a = a + 4) begin
            $fdisplay(sig_fd, "%08x", mem[a >> 2]);
          end
          $fclose(sig_fd);
        end else begin
          $display("ERROR: could not open signature file: %s", sig_file);
        end
      end

      if (tohost_val == 32'd1) $display("RESULT: PASS");
      else                     $display("RESULT: FAIL code=%0d", tohost_val);
      $finish;
    end

    if (cycle > max_cycles) begin
      $display("RESULT: FAIL timeout pc=%08x instr=%08x", u_core.pc, u_core.fx_instr);
      $finish;
    end
  end
endmodule
