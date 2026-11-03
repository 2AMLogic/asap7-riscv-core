// RV32IMC configuration wrapper around the unmodified upstream cve2_top
// (openhwgroup/cve2 @ d7f21568028a1114be663599bd42145dccf28928, see
// reuse.lock.json and spec/decisions/0010-*.md).
//
// Configuration (spec/core.md, decision 0007): RV32E=0, RV32M=RV32MFast,
// no debug module, no CV-X-IF coprocessor. The upstream sources are not
// edited; this file only selects parameters and ties off the interfaces the
// configuration does not use.
module cve2_rv32imc_wrapper
  import cve2_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [31:0] hart_id_i,
  input  logic [31:0] boot_addr_i,

  // Instruction memory interface
  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,

  // Data memory interface
  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,

  // Interrupts
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,
  input  logic [15:0] irq_fast_i,
  input  logic        irq_nm_i,

  // CPU control
  input  logic        fetch_enable_i,
  output logic        core_sleep_o
);

  cve2_top #(
    .MHPMCounterNum   (10),
    .MHPMCounterWidth (40),
    .RV32E            (1'b0),
    .RV32M            (RV32MFast),
    .XInterface       (1'b0)
  ) u_cve2_top (
    .clk_i,
    .rst_ni,
    .test_en_i          (1'b0),
    .ram_cfg_i          ('0),
    .hart_id_i,
    .boot_addr_i,

    .instr_req_o,
    .instr_gnt_i,
    .instr_rvalid_i,
    .instr_addr_o,
    .instr_rdata_i,
    .instr_err_i,

    .data_req_o,
    .data_gnt_i,
    .data_rvalid_i,
    .data_we_o,
    .data_be_o,
    .data_addr_o,
    .data_wdata_o,
    .data_rdata_i,
    .data_err_i,

    // CV-X-IF unused (XInterface = 0)
    .x_issue_valid_o    (),
    .x_issue_ready_i    (1'b0),
    .x_issue_req_o      (),
    .x_issue_resp_i     ('0),
    .x_register_o       (),
    .x_commit_valid_o   (),
    .x_commit_o         (),
    .x_result_valid_i   (1'b0),
    .x_result_ready_o   (),
    .x_result_i         ('0),

    .irq_software_i,
    .irq_timer_i,
    .irq_external_i,
    .irq_fast_i,
    .irq_nm_i,

    // No debug module
    .debug_req_i        (1'b0),
    .debug_halted_o     (),
    .dm_halt_addr_i     (32'b0),
    .dm_exception_addr_i(32'b0),
    .crash_dump_o       (),

    .fetch_enable_i,
    .core_sleep_o
  );

endmodule
