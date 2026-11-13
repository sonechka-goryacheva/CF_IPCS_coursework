`timescale 1ns/1ps
// =============================================================================
// tb_calc.v : самопроверяющийся тестбенч калькулятора (sw/calc.asm).
//   Имитирует клавиатуру 4x4: нажатия key_press / key_code. Перед каждым
//   нажатием ждёт, пока предыдущее прочитано программой (VALID = 0). Перед
//   проверкой выдерживает SETTLE тактов (самая долгая обработка клавиши -
//   деление 9999 / 1, около 420 тактов) и сравнивает SEG с ожидаемым.
//
//   Вид индикаторов (SEG, по одной тетраде на разряд): 0-9 цифра, A - '-',
//   E - 'E', F - погашен. Например FF42 = "  42", FFA3 = "  -3", FFFE = "   E".
// =============================================================================

`ifndef ROM_FILE
`define ROM_FILE "sw/calc.rom.mem"
`endif
`ifndef RAM_FILE
`define RAM_FILE "sw/calc.ram.mem"
`endif
`ifndef VCD_FILE
`define VCD_FILE "sim/tb_calc.vcd"
`endif

// Проверка выходов: макросы, чтобы текст сообщения выводился целиком
`define CHECK(EXP_SEG, MSG) \
    begin \
        repeat (SETTLE) @(posedge clk); \
        checks = checks + 1; \
        if (seg !== (EXP_SEG)) begin \
            errors = errors + 1; \
            $display("  ОШИБКА [%0s]: SEG=%h (ожидалось %h)", MSG, seg, (EXP_SEG)); \
        end else \
            $display("  ok     [%0s]: SEG=%h", MSG, seg); \
    end

`define SCENARIO(NAME) \
    begin \
        $display("[%0d нс] Сценарий: %0s", $time, NAME); \
        do_reset; \
    end

module tb_calc;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         key_press = 1'b0;
    reg  [3:0]  key_code  = 4'd0;
    wire        key_valid, halted;
    wire [15:0] led, seg;

    always #5 clk = ~clk;                       // 100 МГц

    soc_top #(.ROM_FILE(`ROM_FILE), .RAM_FILE(`RAM_FILE)) dut (
        .clk(clk), .rst(rst),
        .key_press(key_press), .key_code(key_code), .key_valid(key_valid),
        .led(led), .seg(seg), .halted(halted)
    );

    // коды клавиш
    localparam PLUS = 10, MINUS = 11, MUL = 12, DIV = 13, EQ = 14, CLR = 15;

    // переменные программы (RAM) - для временных диаграмм
    wire [15:0] a_mag    = dut.u_mem.u_ram.mem[0];
    wire [15:0] a_neg    = dut.u_mem.u_ram.mem[1];
    wire [15:0] x_val    = dut.u_mem.u_ram.mem[2];
    wire [15:0] pend_op  = dut.u_mem.u_ram.mem[3];
    wire [15:0] entering = dut.u_mem.u_ram.mem[4];
    wire [15:0] err_flag = dut.u_mem.u_ram.mem[5];

    localparam SETTLE = 1500;                   // тактов на обработку нажатия
    integer errors = 0, checks = 0;

    task do_reset;
        begin
            rst <= 1'b1;
            repeat (3) @(posedge clk);
            rst <= 1'b0;
            repeat (SETTLE) @(posedge clk);
        end
    endtask

    // нажатие клавиши k
    task press(input [3:0] k);
        begin
            while (key_valid) @(posedge clk);   // предыдущее нажатие должно быть прочитано
            @(posedge clk);
            key_code  <= k;
            key_press <= 1'b1;
            @(posedge clk);
            key_press <= 1'b0;
            @(posedge clk);                     // key_valid поднимается
            while (key_valid) @(posedge clk);   // программа прочитала клавишу
        end
    endtask

    // набор числа n (1-4 цифры, без ведущих нулей)
    task num(input integer n);
        begin
            if (n >= 1000) press((n / 1000) % 10);
            if (n >= 100)  press((n / 100) % 10);
            if (n >= 10)   press((n / 10) % 10);
            press(n % 10);
        end
    endtask

    initial begin
        $dumpfile(`VCD_FILE);
        $dumpvars(0, tb_calc);

        `SCENARIO("начальное состояние")
        `CHECK(16'hFFF0, "после сброса: 0")

        `SCENARIO("12 + 30 = (основной пример)")
        num(12);          `CHECK(16'hFF12, "набрано 12")
        press(PLUS);      `CHECK(16'hFF12, "после '+' показано 12")
        num(30);          `CHECK(16'hFF30, "набрано 30")
        press(EQ);        `CHECK(16'hFF42, "12 + 30 = 42")

        `SCENARIO("7 - 10 = (отрицательный результат)")
        num(7); press(MINUS); num(10); press(EQ);
        `CHECK(16'hFFA3, "7 - 10 = -3 (минус вплотную к числу)")

        `SCENARIO("25 * 4 =")
        num(25); press(MUL); num(4); press(EQ);
        `CHECK(16'hF100, "25 * 4 = 100")

        `SCENARIO("100 / 7 = (целочисленное деление)")
        num(100); press(DIV); num(7); press(EQ);
        `CHECK(16'hFF14, "100 / 7 = 14")

        `SCENARIO("деление на ноль и режим ошибки")
        num(5); press(DIV); num(0); press(EQ);
        `CHECK(16'hFFFE, "5 / 0 = E")
        press(5);         `CHECK(16'hFFFE, "в режиме ошибки цифра игнорируется")
        press(PLUS);      `CHECK(16'hFFFE, "в режиме ошибки '+' игнорируется")
        press(CLR);       `CHECK(16'hFFF0, "C выводит из ошибки: 0")

        `SCENARIO("9999 + 1 = (переполнение)")
        num(9999); press(PLUS); num(1); press(EQ);
        `CHECK(16'hFFFE, "9999 + 1 = E")

        `SCENARIO("3 - 5 + 10 = (цепочка с отрицательным промежуточным)")
        num(3); press(MINUS); num(5); press(PLUS);
        `CHECK(16'hFFA2, "после второго знака показан результат -2")
        num(10); press(EQ);
        `CHECK(16'hFFF8, "-2 + 10 = 8")

        `SCENARIO("пятая цифра игнорируется")
        press(1); press(2); press(3); press(4);
        `CHECK(16'h1234, "набрано 1234")
        press(5);
        `CHECK(16'h1234, "пятая цифра не принята")

        `SCENARIO("ведущие нули 0 0 0 0 5")
        press(0); press(0); press(0); press(0); press(5);
        `CHECK(16'hFFF5, "0 0 0 0 5 = 5")

        `SCENARIO("256 * 256 = (произведение 65536 = 0 в 16 битах)")
        num(256); press(MUL); num(256); press(EQ);
        `CHECK(16'hFFFE, "256 * 256 = E")

        `SCENARIO("9999 * 7 = (69993 в 16 битах заворачивается в 4457)")
        num(9999); press(MUL); num(7); press(EQ);
        `CHECK(16'hFFFE, "9999 * 7 = E (перенос при сложении)")
        press(CLR);
        num(5000); press(MUL); num(14); press(EQ);
        `CHECK(16'hFFFE, "5000 * 14 = 70000 -> E (в 16 битах 4464)")

        `SCENARIO("200 * 200 = (40000 помещается в 16 бит, но > 9999)")
        num(200); press(MUL); num(200); press(EQ);
        `CHECK(16'hFFFE, "200 * 200 = E")

        `SCENARIO("5 - 9999 = (меньше -999)")
        num(5); press(MINUS); num(9999); press(EQ);
        `CHECK(16'hFFFE, "5 - 9999 = E")

        `SCENARIO("0 - 5 * 0 = (нет минус-нуля)")
        num(0); press(MINUS); num(5); press(MUL);
        `CHECK(16'hFFA5, "0 - 5 -> -5")
        num(0); press(EQ);
        `CHECK(16'hFFF0, "-5 * 0 = 0 (а не минус ноль)")

        `SCENARIO("+ + - 5 = (замена знака, ввод без первого числа)")
        press(PLUS); press(PLUS); press(MINUS); num(5); press(EQ);
        `CHECK(16'hFFA5, "0 - 5 = -5")

        `SCENARIO("12 + 30 = = (повторное '=')")
        num(12); press(PLUS); num(30); press(EQ);
        `CHECK(16'hFF42, "первое '='")
        press(EQ);
        `CHECK(16'hFF42, "повторное '=' ничего не делает")

        `SCENARIO("12 + 30 = + 8 = (продолжение цепочки от результата)")
        num(12); press(PLUS); num(30); press(EQ); press(PLUS); num(8); press(EQ);
        `CHECK(16'hFF50, "42 + 8 = 50")

        `SCENARIO("12 + 30 = 7 = (цифра после '=' начинает новое число)")
        num(12); press(PLUS); num(30); press(EQ); num(7);
        `CHECK(16'hFFF7, "после '=' набрана 7")
        press(EQ);
        `CHECK(16'hFFF7, "'=' без операции ничего не делает")
        press(PLUS); num(1); press(EQ);
        `CHECK(16'hFFF8, "7 + 1 = 8 (старый результат 42 забыт)")

        `SCENARIO("5 + * 3 = (замена операции)")
        num(5); press(PLUS); press(MUL); num(3); press(EQ);
        `CHECK(16'hFF15, "5 * 3 = 15")

        `SCENARIO("5 + = 3 = ('=' без второго числа)")
        num(5); press(PLUS); press(EQ);
        `CHECK(16'hFFF5, "'=' без второго числа ничего не делает")
        num(3); press(EQ);
        `CHECK(16'hFFF8, "5 + 3 = 8")

        `SCENARIO("0 - 5 = * 3 = (операции над отрицательным)")
        num(0); press(MINUS); num(5); press(EQ);
        `CHECK(16'hFFA5, "0 - 5 = -5")
        press(MUL); num(3); press(EQ);
        `CHECK(16'hFA15, "-5 * 3 = -15")

        `SCENARIO("0 - 7 = / 2 = (деление отрицательного, к нулю)")
        num(0); press(MINUS); num(7); press(EQ); press(DIV); num(2); press(EQ);
        `CHECK(16'hFFA3, "-7 / 2 = -3 (остаток отброшен к нулю)")

        `SCENARIO("0 - 7 = / 10 = (нет минус-нуля при делении)")
        num(0); press(MINUS); num(7); press(EQ); press(DIV); num(10); press(EQ);
        `CHECK(16'hFFF0, "-7 / 10 = 0 (а не минус ноль)")

        `SCENARIO("границы диапазона")
        num(9999); press(MUL); num(1); press(EQ);
        `CHECK(16'h9999, "9999 * 1 = 9999")
        press(CLR);
        num(999); press(MUL); num(10); press(EQ);
        `CHECK(16'h9990, "999 * 10 = 9990")
        press(CLR);
        num(1000); press(MUL); num(10); press(EQ);
        `CHECK(16'hFFFE, "1000 * 10 = 10000 -> E")
        press(CLR);
        num(9999); press(DIV); num(1); press(EQ);
        `CHECK(16'h9999, "9999 / 1 = 9999 (самое долгое деление)")

        `SCENARIO("нижняя граница -999")
        num(0); press(MINUS); num(999); press(EQ);
        `CHECK(16'hA999, "0 - 999 = -999")
        press(CLR);
        num(0); press(MINUS); num(1000); press(EQ);
        `CHECK(16'hFFFE, "0 - 1000 = -1000 -> E")

        `SCENARIO("5 + 3 C 4 = (сброс клавишей C)")
        num(5); press(PLUS); num(3); press(CLR);
        `CHECK(16'hFFF0, "C: 0")
        num(4); press(EQ);
        `CHECK(16'hFFF4, "после C операция забыта: показано 4")

        `SCENARIO("2 + 3 * 4 = (цепочка слева направо)")
        num(2); press(PLUS); num(3); press(MUL);
        `CHECK(16'hFFF5, "после '*' показано 5")
        num(4); press(EQ);
        `CHECK(16'hFF20, "(2 + 3) * 4 = 20")

        `SCENARIO("деление с остатком и умножение на ноль")
        num(10); press(DIV); num(3); press(EQ);
        `CHECK(16'hFFF3, "10 / 3 = 3")
        press(CLR);
        num(5); press(MUL); num(0); press(EQ);
        `CHECK(16'hFFF0, "5 * 0 = 0")
        press(CLR);
        num(0); press(MUL); num(5); press(EQ);
        `CHECK(16'hFFF0, "0 * 5 = 0")

        `SCENARIO("1234 + 1 =")
        num(1234); press(PLUS); num(1); press(EQ);
        `CHECK(16'h1235, "1234 + 1 = 1235")

        $display("----------------------------------------------");
        $display("Проверок: %0d, ошибок: %0d", checks, errors);
        if (errors == 0) $display("TEST PASSED: калькулятор работает по спецификации");
        else             $display("TEST FAILED");
        $finish;
    end
endmodule
