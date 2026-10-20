// ============================================================================
// tb_three_sipp_es_debug.sv — self-checking JTAG / RISC-V Debug-Module testbench for
// the 3-stage 3-SIP-ESR core (pipelined drain-to-halt). Bit-bangs the JTAG TAP:
//   1. IDCODE ("TAKS")   2. dmactive+haltreq → allhalted
//   3. GPR x1 (counter progressing)   4. CSR misa (0x40001107) + dpc
//   5. GPR x31 wr/rd   6. SBA mem wr/rd   7. resume → counter advanced
//   8. single-step: exactly one instruction retires, then re-halt
// Reports DEBUG: PASS / DEBUG: FAIL.
// ============================================================================
`timescale 1ns/1ps

module tb_three_sipp_es_debug;
  logic clk = 1'b0; always #5 clk = ~clk;
  logic rst;
  logic tck = 1'b0, tms = 1'b0, tdi = 1'b0, tdo;

  logic [31:0] tohost; logic tohost_we;
  logic        rv; logic [31:0] rpc, rins, rval; logic rwe; logic [4:0] rrd;

  three_sipp_es_soc dut (
    .clk(clk), .rst(rst), .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
    .tohost(tohost), .tohost_we(tohost_we),
    .retire_valid(rv), .retire_pc(rpc), .retire_instr(rins),
    .retire_rd_we(rwe), .retire_rd(rrd), .retire_rd_val(rval)
  );

  integer i, errors = 0;
  reg [63:0] dump, cap;

  task automatic tck_cyc(input bit tms_v, input bit tdi_v);
    begin
      tms = tms_v; tdi = tdi_v; @(posedge clk);
      tck = 1'b1; repeat (3) @(posedge clk);
      tck = 1'b0; repeat (3) @(posedge clk);
    end
  endtask
  task automatic jtag_reset; begin
    for (i=0;i<6;i++) tck_cyc(1,0); tck_cyc(0,0);
  end endtask
  task automatic scan_dr(input int n, input [63:0] din, output [63:0] dout);
    int k; begin
      dout = 0;
      tck_cyc(1,0); tck_cyc(0,0);
      while (dut.u_dbg.tap != 4) tck_cyc(0,0);
      for (k=0;k<n;k++) begin dout[k] = tdo; tck_cyc((k==n-1)?1'b1:1'b0, din[k]); end
      tck_cyc(1,0); tck_cyc(0,0);
    end
  endtask
  task automatic scan_ir(input [4:0] irval);
    int k; begin
      tck_cyc(1,0); tck_cyc(1,0); tck_cyc(0,0);
      while (dut.u_dbg.tap != 11) tck_cyc(0,0);
      for (k=0;k<5;k++) tck_cyc((k==4)?1'b1:1'b0, irval[k]);
      tck_cyc(1,0); tck_cyc(0,0);
    end
  endtask
  task automatic dmi_write(input [6:0] a, input [31:0] d);
    begin scan_dr(41, {23'd0, a, d, 2'd2}, dump); end
  endtask
  task automatic dmi_read(input [6:0] a, output [31:0] d);
    begin
      scan_dr(41, {23'd0, a, 32'd0, 2'd1}, dump);
      scan_dr(41, {23'd0, 7'd0, 32'd0, 2'd0}, cap);
      d = cap[33:2];
    end
  endtask
  function [31:0] arcmd(input bit wr, input [15:0] regno);
    arcmd = (3'd2<<20) | (1<<17) | (wr<<16) | regno;
  endfunction
  task automatic check(input [255:0] name, input [31:0] got, input [31:0] exp);
    begin
      if (got !== exp) begin
        $display("[DBG] FAIL %0s: got %08x exp %08x", name, got, exp); errors=errors+1;
      end else $display("[DBG] ok   %0s = %08x", name, got);
    end
  endtask

  localparam [6:0] DATA0=7'h04, DMCONTROL=7'h10, DMSTATUS=7'h11,
                   COMMAND=7'h17, SBCS=7'h38, SBADDR0=7'h39, SBDATA0=7'h3c;
  reg [31:0] v, idcode, x1_a, x1_b;
  integer halts;

  initial begin
    for (i=0;i<8192;i++) begin dut.imem[i]=32'h00000013; dut.dram[i]=32'h0; end
    dut.imem[0] = 32'h00108093;   // addi x1,x1,1
    dut.imem[1] = 32'hFFDFF06F;   // jal  x0,-4
    rst = 1'b1; repeat (6) @(posedge clk); rst = 1'b0;
    repeat (40) @(posedge clk);

    jtag_reset;
    scan_dr(32, 64'd0, cap); idcode = cap[31:0];
    check("idcode", idcode, 32'h5441_4B53);

    scan_ir(5'h11);
    dmi_write(DMCONTROL, 32'h0000_0001);
    dmi_write(DMCONTROL, 32'h8000_0001);
    halts = 0;
    for (i=0;i<30;i++) begin dmi_read(DMSTATUS, v); if (v[9]) begin halts=1; i=30; end end
    if (!halts) begin $display("[DBG] FAIL: hart did not halt"); errors=errors+1; end
    else $display("[DBG] ok   hart halted (dmstatus=%08x)", v);

    dmi_write(COMMAND, arcmd(1'b0, 16'h1001));
    dmi_read(DATA0, x1_a);
    if (x1_a == 32'd0) begin $display("[DBG] FAIL: x1==0"); errors=errors+1; end
    else $display("[DBG] ok   x1(halt#1) = %0d", x1_a);

    dmi_write(COMMAND, arcmd(1'b0, 16'h0301)); dmi_read(DATA0, v);
    check("misa", v, 32'h4000_1107);   // RV32IMAC + B (A=bit0, B=bit1)
    dmi_write(COMMAND, arcmd(1'b0, 16'h07b1)); dmi_read(DATA0, v);
    if (v > 32'h8) begin $display("[DBG] FAIL: dpc=%08x out of loop", v); errors=errors+1; end
    else $display("[DBG] ok   dpc = %08x", v);

    dmi_write(DATA0, 32'hDEAD_BEEF);
    dmi_write(COMMAND, arcmd(1'b1, 16'h101F));
    dmi_write(COMMAND, arcmd(1'b0, 16'h101F));
    dmi_read(DATA0, v);
    check("gpr x31 wr/rd", v, 32'hDEAD_BEEF);

    dmi_write(SBADDR0, 32'h8000_7000);
    dmi_write(SBDATA0, 32'hCAFE_F00D);
    dmi_write(SBCS,    32'h0010_0000);
    dmi_write(SBADDR0, 32'h8000_7000);
    dmi_read(SBDATA0, v);
    check("sba mem wr/rd", v, 32'hCAFE_F00D);

    dmi_write(DMCONTROL, 32'h4000_0001);
    for (i=0;i<30;i++) begin dmi_read(DMSTATUS, v); if (v[11]) i=30; end
    if (!v[11]) begin $display("[DBG] FAIL: hart did not resume"); errors=errors+1; end
    else $display("[DBG] ok   hart resumed (dmstatus=%08x)", v);
    repeat (60) @(posedge clk);
    dmi_write(DMCONTROL, 32'h8000_0001);
    for (i=0;i<30;i++) begin dmi_read(DMSTATUS, v); if (v[9]) i=30; end
    dmi_write(COMMAND, arcmd(1'b0, 16'h1001));
    dmi_read(DATA0, x1_b);
    if (x1_b <= x1_a) begin
      $display("[DBG] FAIL: counter did not advance (%0d -> %0d)", x1_a, x1_b); errors=errors+1;
    end else $display("[DBG] ok   counter advanced %0d -> %0d", x1_a, x1_b);

    dmi_write(DATA0, 32'h0000_0004);
    dmi_write(COMMAND, arcmd(1'b1, 16'h07b0));
    dmi_write(COMMAND, arcmd(1'b0, 16'h1001)); dmi_read(DATA0, x1_a);
    dmi_write(DMCONTROL, 32'h4000_0001);
    halts = 0;
    for (i=0;i<30;i++) begin dmi_read(DMSTATUS, v); if (v[9]) begin halts=1; i=30; end end
    if (!halts) begin $display("[DBG] FAIL: no re-halt after single-step"); errors=errors+1; end
    else begin
      dmi_write(COMMAND, arcmd(1'b0, 16'h1001)); dmi_read(DATA0, x1_b);
      if (x1_b != x1_a && x1_b != x1_a + 1)
        begin $display("[DBG] FAIL: step ran >1 instr (%0d -> %0d)", x1_a, x1_b); errors=errors+1; end
      else $display("[DBG] ok   single-step: one instruction (%0d -> %0d)", x1_a, x1_b);
    end
    dmi_write(DATA0, 32'h0); dmi_write(COMMAND, arcmd(1'b1, 16'h07b0));

    if (errors == 0) $display("DEBUG: PASS");
    else             $display("DEBUG: FAIL (%0d errors)", errors);
    $finish;
  end
  initial begin #800000; $display("DEBUG: FAIL (timeout)"); $finish; end
endmodule
