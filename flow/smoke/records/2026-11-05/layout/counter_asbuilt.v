module counter (clk,
    en,
    rst_n,
    count);
 input clk;
 input en;
 input rst_n;
 output [7:0] count;

 wire _00_;
 wire _01_;
 wire _02_;
 wire _03_;
 wire _04_;
 wire _05_;
 wire _06_;
 wire _07_;
 wire _08_;
 wire _09_;
 wire _10_;
 wire _11_;
 wire _12_;
 wire _13_;
 wire _14_;
 wire _15_;
 wire _16_;
 wire _17_;
 wire _18_;
 wire _19_;
 wire _20_;
 wire _21_;
 wire _22_;
 wire _23_;
 wire _24_;
 wire _25_;
 wire _26_;
 wire _27_;
 wire _28_;
 wire _29_;
 wire _30_;
 wire clknet_0_clk;
 wire clknet_1_0__leaf_clk;
 wire clknet_1_1__leaf_clk;

 INVx1_ASAP7_75t_R _31_ (.A(_07_),
    .Y(count[6]));
 INVx1_ASAP7_75t_R _32_ (.A(_00_),
    .Y(count[7]));
 INVx1_ASAP7_75t_R _33_ (.A(_01_),
    .Y(count[0]));
 INVx1_ASAP7_75t_R _34_ (.A(_02_),
    .Y(count[1]));
 INVx1_ASAP7_75t_R _35_ (.A(_03_),
    .Y(count[2]));
 INVx1_ASAP7_75t_R _36_ (.A(_04_),
    .Y(count[3]));
 INVx1_ASAP7_75t_R _37_ (.A(_05_),
    .Y(count[4]));
 INVx1_ASAP7_75t_R _38_ (.A(_06_),
    .Y(count[5]));
 NAND2xp33_ASAP7_75t_R _39_ (.A(count[0]),
    .B(en),
    .Y(_16_));
 NOR3xp33_ASAP7_75t_R _40_ (.A(_02_),
    .B(_03_),
    .C(_16_),
    .Y(_17_));
 NAND5xp2_ASAP7_75t_R _41_ (.A(count[0]),
    .B(count[1]),
    .C(count[2]),
    .D(count[3]),
    .E(en),
    .Y(_18_));
 NOR3xp33_ASAP7_75t_R _42_ (.A(_05_),
    .B(_06_),
    .C(_18_),
    .Y(_19_));
 NOR4xp25_ASAP7_75t_R _43_ (.A(_07_),
    .B(_05_),
    .C(_06_),
    .D(_18_),
    .Y(_20_));
 XNOR2xp5_ASAP7_75t_R _44_ (.A(_07_),
    .B(_19_),
    .Y(_08_));
 OA21x2_ASAP7_75t_R _45_ (.A1(_05_),
    .A2(_18_),
    .B(_06_),
    .Y(_21_));
 NOR2xp33_ASAP7_75t_R _46_ (.A(_19_),
    .B(_21_),
    .Y(_09_));
 XNOR2xp5_ASAP7_75t_R _47_ (.A(count[4]),
    .B(_18_),
    .Y(_10_));
 XNOR2xp5_ASAP7_75t_R _48_ (.A(_04_),
    .B(_17_),
    .Y(_11_));
 AOI31xp33_ASAP7_75t_R _49_ (.A1(count[0]),
    .A2(count[1]),
    .A3(en),
    .B(count[2]),
    .Y(_22_));
 NOR2xp33_ASAP7_75t_R _50_ (.A(_17_),
    .B(_22_),
    .Y(_12_));
 XNOR2xp5_ASAP7_75t_R _51_ (.A(count[1]),
    .B(_16_),
    .Y(_13_));
 XNOR2xp5_ASAP7_75t_R _52_ (.A(_01_),
    .B(en),
    .Y(_14_));
 XNOR2xp5_ASAP7_75t_R _53_ (.A(_00_),
    .B(_20_),
    .Y(_15_));
 DFFASRHQNx1_ASAP7_75t_R _54_ (.CLK(clknet_1_0__leaf_clk),
    .D(_14_),
    .QN(_01_),
    .RESETN(rst_n),
    .SETN(_24_));
 DFFASRHQNx1_ASAP7_75t_R _55_ (.CLK(clknet_1_0__leaf_clk),
    .D(_13_),
    .QN(_02_),
    .RESETN(rst_n),
    .SETN(_23_));
 DFFASRHQNx1_ASAP7_75t_R _56_ (.CLK(clknet_1_0__leaf_clk),
    .D(_12_),
    .QN(_03_),
    .RESETN(rst_n),
    .SETN(_30_));
 DFFASRHQNx1_ASAP7_75t_R _57_ (.CLK(clknet_1_0__leaf_clk),
    .D(_11_),
    .QN(_04_),
    .RESETN(rst_n),
    .SETN(_29_));
 DFFASRHQNx1_ASAP7_75t_R _58_ (.CLK(clknet_1_1__leaf_clk),
    .D(_10_),
    .QN(_05_),
    .RESETN(rst_n),
    .SETN(_28_));
 DFFASRHQNx1_ASAP7_75t_R _59_ (.CLK(clknet_1_1__leaf_clk),
    .D(_09_),
    .QN(_06_),
    .RESETN(rst_n),
    .SETN(_27_));
 DFFASRHQNx1_ASAP7_75t_R _60_ (.CLK(clknet_1_1__leaf_clk),
    .D(_08_),
    .QN(_07_),
    .RESETN(rst_n),
    .SETN(_26_));
 DFFASRHQNx1_ASAP7_75t_R _61_ (.CLK(clknet_1_1__leaf_clk),
    .D(_15_),
    .QN(_00_),
    .RESETN(rst_n),
    .SETN(_25_));
 TIEHIx1_ASAP7_75t_R _62_ (.H(_23_));
 TIEHIx1_ASAP7_75t_R _63_ (.H(_24_));
 TIEHIx1_ASAP7_75t_R _64_ (.H(_25_));
 TIEHIx1_ASAP7_75t_R _65_ (.H(_26_));
 TIEHIx1_ASAP7_75t_R _66_ (.H(_27_));
 TIEHIx1_ASAP7_75t_R _67_ (.H(_28_));
 TIEHIx1_ASAP7_75t_R _68_ (.H(_29_));
 TIEHIx1_ASAP7_75t_R _69_ (.H(_30_));
 BUFx4_ASAP7_75t_R clkbuf_0_clk (.A(clk),
    .Y(clknet_0_clk));
 BUFx4_ASAP7_75t_R clkbuf_1_0__f_clk (.A(clknet_0_clk),
    .Y(clknet_1_0__leaf_clk));
 BUFx4_ASAP7_75t_R clkbuf_1_1__f_clk (.A(clknet_0_clk),
    .Y(clknet_1_1__leaf_clk));
endmodule
