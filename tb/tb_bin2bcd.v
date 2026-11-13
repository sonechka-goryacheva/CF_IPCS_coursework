`timescale 1ns/1ps
// =============================================================================
// tb_bin2bcd.v : полный перебор всех 65536 входов преобразователя BIN2BCD.
//   Эталон считается обычным делением в тестбенче (в железе деления нет).
// =============================================================================
module tb_bin2bcd;
    reg  [15:0] x;
    wire [19:0] b;
    integer i, errors;
    reg [19:0] expected;

    BIN2BCD dut (.bin(x), .bcd(b));

    initial begin
        errors = 0;
        for (i = 0; i < 65536; i = i + 1) begin
            x = i;
            #1;
            expected = ((i / 10000) % 10) << 16 | ((i / 1000) % 10) << 12 |
                       ((i / 100)   % 10) << 8  | ((i / 10)   % 10) << 4  | (i % 10);
            if (b !== expected) begin
                errors = errors + 1;
                if (errors <= 5) $display("ОШИБКА: bin=%0d bcd=%h ожидалось %h", i, b, expected);
            end
        end
        if (errors == 0) $display("TEST PASSED: BIN2BCD верен для всех 65536 входов");
        else             $display("TEST FAILED: ошибок = %0d", errors);
        $finish;
    end
endmodule
