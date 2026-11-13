`timescale 1ns/1ps
// =============================================================================
// ALU.v : арифметико-логическое устройство (комбинационное).
//   Операции: ADD, SUB, AND, OR, XOR, NOT, SHL, SHR, BIN2BCD.
//   Флаги (результат вычисляется всегда, сохраняет их CPU_Core):
//     z - результат равен нулю;
//     c - ADD: перенос; SUB: 1, если заёма не было (a >= b, беззнаково);
//         AND/OR/XOR/NOT: 0; SHL: выдвинутый бит a[15]; SHR: выдвинутый бит a[0];
//         BIN2BCD: 1, если a >= 10000.
// =============================================================================
module ALU (
    input  wire [15:0] a,      // первый операнд (rs)
    input  wire [15:0] b,      // второй операнд (rt или imm5 со знаковым расширением)
    input  wire [3:0]  op,     // код операции АЛУ (внутренний)
    output reg  [15:0] y,      // результат
    output reg         c,      // флаг C (кандидат на запись)
    output wire        z       // флаг Z (кандидат на запись)
);
    localparam OP_ADD = 4'd0;
    localparam OP_SUB = 4'd1;
    localparam OP_AND = 4'd2;
    localparam OP_OR  = 4'd3;
    localparam OP_XOR = 4'd4;
    localparam OP_NOT = 4'd5;
    localparam OP_SHL = 4'd6;
    localparam OP_SHR = 4'd7;
    localparam OP_BCD = 4'd8;

    // Блок кастомной инструкции BIN2BCD
    wire [19:0] bcd;
    BIN2BCD u_bin2bcd (.bin(a), .bcd(bcd));

    assign z = (y == 16'd0);

    always @* begin
        y = 16'd0;
        c = 1'b0;
        case (op)
            OP_ADD: {c, y} = {1'b0, a} + {1'b0, b};
            // a - b = a + ~b + 1; перенос = 1 <=> заёма не было (a >= b)
            OP_SUB: {c, y} = {1'b0, a} + {1'b0, ~b} + 17'd1;
            OP_AND: y = a & b;
            OP_OR : y = a | b;
            OP_XOR: y = a ^ b;
            OP_NOT: y = ~a;
            OP_SHL: begin y = {a[14:0], 1'b0}; c = a[15]; end
            OP_SHR: begin y = {1'b0, a[15:1]}; c = a[0];  end
            OP_BCD: begin y = bcd[15:0];       c = |bcd[19:16]; end
            default: begin y = 16'd0; c = 1'b0; end
        endcase
    end
endmodule
