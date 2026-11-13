`timescale 1ns/1ps
// =============================================================================
// Program_Counter.v : счётчик команд (11 бит -> 2048 слов ROM).
//   mode: 0 - PC+1 (следующая команда)
//         1 - JUMP : PC <- jump_addr
//         2 - ветвление: PC <- PC + 1 + offset (смещение 11 бит со знаком;
//             сложение по модулю 2^11 даёт правильный результат)
//         3 - JR   : PC <- reg_addr
//   Обновляется только при en = 1. Синхронный сброс: PC <- 0.
// =============================================================================
module Program_Counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire [1:0]  mode,
    input  wire [10:0] jump_addr,
    input  wire [10:0] offset,
    input  wire [10:0] reg_addr,
    output reg  [10:0] pc
);
    wire [10:0] pc_inc = pc + 11'd1;

    always @(posedge clk) begin
        if (rst)
            pc <= 11'd0;
        else if (en) begin
            case (mode)
                2'd0:    pc <= pc_inc;
                2'd1:    pc <= jump_addr;
                2'd2:    pc <= pc_inc + offset;
                default: pc <= reg_addr;
            endcase
        end
    end
endmodule
