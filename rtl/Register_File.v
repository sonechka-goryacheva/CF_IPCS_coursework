`timescale 1ns/1ps
// =============================================================================
// Register_File.v : регистровый файл 8 x 16 бит.
//   R0 всегда читается как 0, запись в R0 игнорируется.
//   Два асинхронных порта чтения (A, B), один синхронный порт записи.
//   Синхронный сброс (rst): R1..R7 <- 0.
//   Выходы r1..r7 - отладочные (для временных диаграмм).
// =============================================================================
module Register_File (
    input  wire        clk,
    input  wire        rst,
    input  wire [2:0]  raddr_a,
    input  wire [2:0]  raddr_b,
    output wire [15:0] rdata_a,
    output wire [15:0] rdata_b,
    input  wire        we,
    input  wire [2:0]  waddr,
    input  wire [15:0] wdata,
    output wire [15:0] r1, r2, r3, r4, r5, r6, r7   // отладка
);
    reg [15:0] q1, q2, q3, q4, q5, q6, q7;

    assign r1 = q1; assign r2 = q2; assign r3 = q3; assign r4 = q4;
    assign r5 = q5; assign r6 = q6; assign r7 = q7;

    // Чтение: мультиплексор по номеру регистра (R0 = 0).
    // Все регистры собраны в одну шину, поэтому выход пересчитывается и при
    // смене номера регистра, и при смене его содержимого.
    wire [127:0] bank = {q7, q6, q5, q4, q3, q2, q1, 16'd0};

    assign rdata_a = bank[{raddr_a, 4'b0000} +: 16];
    assign rdata_b = bank[{raddr_b, 4'b0000} +: 16];

    // Запись по фронту clk
    always @(posedge clk) begin
        if (rst) begin
            q1 <= 16'd0; q2 <= 16'd0; q3 <= 16'd0; q4 <= 16'd0;
            q5 <= 16'd0; q6 <= 16'd0; q7 <= 16'd0;
        end else if (we) begin
            case (waddr)
                3'd1: q1 <= wdata;
                3'd2: q2 <= wdata;
                3'd3: q3 <= wdata;
                3'd4: q4 <= wdata;
                3'd5: q5 <= wdata;
                3'd6: q6 <= wdata;
                3'd7: q7 <= wdata;
                default: ;               // запись в R0 игнорируется
            endcase
        end
    end
endmodule
