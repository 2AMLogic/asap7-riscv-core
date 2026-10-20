// PLACEHOLDER DUT -- exists only to prove the cocotb + Icarus flow.
// Deleted or replaced when the core is pinned. Not part of the design.
`timescale 1ns/1ps
module counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    output logic [7:0] count
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) count <= 8'd0;
    else if (en) count <= count + 8'd1;
  end
endmodule
