`timescale 1ns/1ps
// =============================================================================
// Data_RAM.v : память данных 256 x 16 бит (адреса 0x0000-0x00FF).
//   Запись синхронная, чтение асинхронное.
//   Начальное содержимое: нули, затем загрузка из файла ($readmemb), если задан.
// =============================================================================
module Data_RAM #(
    parameter INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        we,
    input  wire [7:0]  addr,
    input  wire [15:0] wdata,
    output wire [15:0] rdata
);
    reg [15:0] mem [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1) mem[i] = 16'd0;
        if (INIT_FILE != "") $readmemb(INIT_FILE, mem, 0);
    end

    always @(posedge clk)
        if (we) mem[addr] <= wdata;

    assign rdata = mem[addr];
endmodule
