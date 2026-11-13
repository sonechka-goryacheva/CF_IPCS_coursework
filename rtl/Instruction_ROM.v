`timescale 1ns/1ps
// =============================================================================
// Instruction_ROM.v : память команд 2048 x 16 бит (адреса 0x000-0x7FF).
//   Содержимое загружается из текстового файла двоичных слов ($readmemb),
//   одна команда на строку. Невыписанные ячейки заполняются HLT (0xA000),
//   чтобы потерявшийся PC останавливал процессор.
//   Чтение асинхронное (комбинационное).
// =============================================================================
module Instruction_ROM #(
    parameter INIT_FILE = ""
) (
    input  wire [10:0] addr,
    output wire [15:0] data
);
    reg [15:0] mem [0:2047];
    integer i;

    initial begin
        for (i = 0; i < 2048; i = i + 1) mem[i] = 16'hA000;   // HLT
        if (INIT_FILE != "") $readmemb(INIT_FILE, mem, 0);
    end

    assign data = mem[addr];
endmodule
