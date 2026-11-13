`timescale 1ns/1ps
// =============================================================================
// soc_top.v : верхний уровень SoC = CPU_Core + Instruction_ROM + Memory_Top.
// =============================================================================
module soc_top #(
    parameter ROM_FILE = "",
    parameter RAM_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,

    // периферия
    input  wire        key_press,
    input  wire [3:0]  key_code,
    output wire        key_valid,
    output wire [15:0] led,
    output wire [15:0] seg,

    output wire        halted
);
    wire [10:0] rom_addr;
    wire [15:0] rom_data;
    wire [15:0] mem_addr, mem_wdata, mem_rdata;
    wire        mem_we, mem_re;

    // отладочные сигналы ядра (для временных диаграмм)
    wire [15:0] dbg_r1, dbg_r2, dbg_r3, dbg_r4, dbg_r5, dbg_r6, dbg_r7;
    wire        dbg_z, dbg_c;

    CPU_Core u_cpu (
        .clk(clk), .rst(rst),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_we(mem_we), .mem_re(mem_re), .mem_rdata(mem_rdata),
        .halted(halted),
        .dbg_r1(dbg_r1), .dbg_r2(dbg_r2), .dbg_r3(dbg_r3), .dbg_r4(dbg_r4),
        .dbg_r5(dbg_r5), .dbg_r6(dbg_r6), .dbg_r7(dbg_r7),
        .dbg_z(dbg_z), .dbg_c(dbg_c)
    );

    Instruction_ROM #(.INIT_FILE(ROM_FILE)) u_rom (
        .addr(rom_addr), .data(rom_data)
    );

    Memory_Top #(.RAM_INIT_FILE(RAM_FILE)) u_mem (
        .clk(clk), .rst(rst),
        .addr(mem_addr), .wdata(mem_wdata), .we(mem_we), .re(mem_re),
        .rdata(mem_rdata),
        .key_press(key_press), .key_code(key_code), .key_valid(key_valid),
        .led(led), .seg(seg)
    );
endmodule
