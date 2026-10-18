// ============================================================================
// tb_three_sipp_es_rtos.sv — RTOS bring-up harness for three_sipp_es_soc.
//
//   vvp sim/tb_three_sipp_es_rtos +IMEM=rtos/build/rtos.hex     [+MAXCYC=<n>]
//
// Runs a FreeRTOS image on the 3-SIPP-ES SoC. The SoC UART $writes every TX
// byte to stdout, so the console transcript is captured verbatim. The run
// ends on a store to tohost (0x2000_0000):
//   tohost == 1  -> [TB] PASS   (demo reached [DONE]ok)
//   tohost != 1  -> [TB] FAIL
// A bounded cycle budget (+MAXCYC, default 2_000_000) makes the NEGATIVE
// CONTROL — where the tick is disabled and the demo can never complete —
// terminate deterministically as "[TB] TIMEOUT (no completion)" instead of
// spinning forever. The Python harness (rtos/run_rtos.py) asserts the exact
// transcript for the positive run and the *absence* of completion for the neg.
// ============================================================================
`timescale 1ns/1ps

module tb_three_sipp_es_rtos;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst;

  logic [31:0] tohost;
  logic        tohost_we;
  logic        retire_valid;
  logic [31:0] retire_pc, retire_instr, retire_rd_val;
  logic        retire_rd_we;
  logic [4:0]  retire_rd;

  three_sipp_es_soc dut (
    .clk(clk), .rst(rst),
    .tck(1'b0), .tms(1'b0), .tdi(1'b0), .tdo(),
    .tohost(tohost), .tohost_we(tohost_we),
    .retire_valid(retire_valid), .retire_pc(retire_pc),
    .retire_instr(retire_instr), .retire_rd_we(retire_rd_we),
    .retire_rd(retire_rd), .retire_rd_val(retire_rd_val)
  );

  string  imem_file;
  integer maxcyc;
  integer i;

  initial begin
    if (!$value$plusargs("IMEM=%s", imem_file)) begin
      $display("FATAL: no +IMEM=<file> given");
      $finish;
    end
    maxcyc = 2000000;
    if ($value$plusargs("MAXCYC=%d", maxcyc)) ;

    // clear memories
    for (i = 0; i < 8192; i = i + 1) begin
      dut.imem[i] = 32'h0000_0013;   // NOP fill
      dut.dram[i] = 32'h0;
    end

    $display("[TB] Loading IMEM from: %s (maxcyc=%0d)", imem_file, maxcyc);
    $readmemh(imem_file, dut.imem);

    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    $display("[TB] Reset released");
  end

  // exit on tohost, bounded by a cycle budget
  integer cycle = 0;
  always @(posedge clk) begin
    if (!rst) cycle <= cycle + 1;
    if (tohost_we) begin
      $display("\n[TB] tohost write: 0x%08x at cycle %0d", tohost, cycle);
      if (tohost == 32'd1) $display("[TB] PASS");
      else                 $display("[TB] FAIL (code %0d)", tohost);
      $finish;
    end
    if (cycle > maxcyc) begin
      $display("\n[TB] TIMEOUT (no completion) at cycle %0d", cycle);
      $finish;
    end
  end
endmodule
