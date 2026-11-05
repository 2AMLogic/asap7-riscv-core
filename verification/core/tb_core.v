// Testbench shell around cve2_rv32imc_wrapper: a 2 MiB zero-wait RAM at
// 0x80000000 on both memory ports. A word store to `tohost` (address given by
// the +TOHOST plusarg, taken from the test ELF) sets `done`. The program image
// is loaded with $readmemh from +HEX. cocotb drives clock/reset and reads the
// signature region out of `mem` once `done` is set.
`timescale 1ns/1ps
module tb_core;
  reg clk = 0;
  reg rst_n = 0;
  wire done_o;

  localparam WORDS = 1 << 19;
  reg [31:0] mem [0:WORDS-1];
  reg [31:0] tohost_addr;
  reg        done = 0;
  assign done_o = done;

  wire        instr_req, data_req, data_we;
  wire [31:0] instr_addr, data_addr, data_wdata;
  wire [3:0]  data_be;
  reg         instr_rvalid = 0, data_rvalid = 0;
  reg  [31:0] instr_rdata = 0, data_rdata = 0;

  cve2_rv32imc_wrapper dut (
    .clk_i(clk), .rst_ni(rst_n),
    .hart_id_i(32'd0), .boot_addr_i(32'h8000_0080),
    .instr_req_o(instr_req), .instr_gnt_i(instr_req), .instr_rvalid_i(instr_rvalid),
    .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata), .instr_err_i(1'b0),
    .data_req_o(data_req), .data_gnt_i(data_req), .data_rvalid_i(data_rvalid),
    .data_we_o(data_we), .data_be_o(data_be), .data_addr_o(data_addr),
    .data_wdata_o(data_wdata), .data_rdata_i(data_rdata), .data_err_i(1'b0),
    .irq_software_i(1'b0), .irq_timer_i(1'b0), .irq_external_i(1'b0),
    .irq_fast_i(16'b0), .irq_nm_i(1'b0),
    .fetch_enable_i(1'b1), .core_sleep_o()
  );

  wire [18:0] iidx = instr_addr[20:2];
  wire [18:0] didx = data_addr[20:2];

  integer k;
  reg [1023:0] hexfile;
  initial begin
    for (k = 0; k < WORDS; k = k + 1) mem[k] = 32'h0;
`ifdef HEX_FILE
    // klt functional-verification requests carry no plusargs: verification/fv.sh
    // passes the program image path and the tohost address (hex digits) as -D
    // macros, which the runner renders as SV string literals.
    if ($sscanf(`TOHOST_HEX, "%h", tohost_addr) != 1) begin $display("tb_core: bad TOHOST_HEX"); $finish; end
    $readmemh(`HEX_FILE, mem);
`else
    if (!$value$plusargs("HEX=%s", hexfile)) begin $display("tb_core: +HEX missing"); $finish; end
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) begin $display("tb_core: +TOHOST missing"); $finish; end
    $readmemh(hexfile, mem);
`endif
  end

  always @(posedge clk) begin
    instr_rvalid <= instr_req;
    if (instr_req) instr_rdata <= mem[iidx];
    data_rvalid <= data_req;
    if (data_req) begin
      if (data_we) begin
        if (data_be[0]) mem[didx][7:0]   <= data_wdata[7:0];
        if (data_be[1]) mem[didx][15:8]  <= data_wdata[15:8];
        if (data_be[2]) mem[didx][23:16] <= data_wdata[23:16];
        if (data_be[3]) mem[didx][31:24] <= data_wdata[31:24];
        if ({data_addr[31:2], 2'b00} == tohost_addr) done <= 1;
      end else begin
        data_rdata <= mem[didx];
      end
    end
  end
endmodule
