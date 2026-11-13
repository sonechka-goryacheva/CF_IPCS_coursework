`timescale 1ns/1ps
// =============================================================================
// tb_vending.v : самопроверяющийся тестбенч для программы автомата (sw/vending.asm).
//   Тестбенч имитирует клавиатуру: подаёт key_press / key_code, перед каждым
//   нажатием ждёт, пока предыдущее прочитано программой (VALID = 0), затем даёт
//   программе время обработать нажатие и сравнивает LED и SEG с ожидаемыми.
//   Временные диаграммы: sim/tb_vending.vcd. Время начала каждого сценария
//   выводится в лог - по нему можно найти сценарий на диаграмме.
// =============================================================================

`ifndef ROM_FILE
`define ROM_FILE "sw/vending.rom.mem"
`endif
`ifndef VCD_FILE
`define VCD_FILE "sim/tb_vending.vcd"
`endif

// Проверка выходов: макросы вместо задач, чтобы текст сообщения (строковый литерал)
// выводился целиком, без обрезки по ширине вектора.
`define CHECK(EXP_SEG, EXP_LED, MSG) \
    begin \
        checks = checks + 1; \
        if (seg !== (EXP_SEG) || led !== (EXP_LED)) begin \
            errors = errors + 1; \
            $display("  ОШИБКА [%0s]: SEG=%h (ожидалось %h), LED=%h (ожидалось %h)", \
                     MSG, seg, (EXP_SEG), led, (EXP_LED)); \
        end else \
            $display("  ok     [%0s]: SEG=%h LED=%h", MSG, seg, led); \
    end

`define SCENARIO(NAME) \
    begin \
        $display("[%0d нс] Сценарий: %0s", $time, NAME); \
        do_reset; \
    end

module tb_vending;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         key_press = 1'b0;
    reg  [3:0]  key_code  = 4'd0;
    wire        key_valid, halted;
    wire [15:0] led, seg;

    always #5 clk = ~clk;                       // 100 МГц

    soc_top #(.ROM_FILE(`ROM_FILE), .RAM_FILE("")) dut (
        .clk(clk), .rst(rst),
        .key_press(key_press), .key_code(key_code), .key_valid(key_valid),
        .led(led), .seg(seg), .halted(halted)
    );

    // сигналы для временных диаграмм
    wire [15:0] balance = dut.u_cpu.dbg_r1;     // R1 - баланс
    wire [15:0] state   = dut.u_cpu.dbg_r5;     // R5 - состояние (0 приём, 1 завершено)

    localparam SETTLE = 400;                    // тактов на обработку нажатия программой
    integer errors = 0, checks = 0;

    // ---- сброс процессора ----
    task do_reset;
        begin
            rst <= 1'b1;
            repeat (3) @(posedge clk);
            rst <= 1'b0;
            repeat (SETTLE) @(posedge clk);
        end
    endtask

    // ---- нажатие клавиши ----
    task press(input [3:0] k);
        begin
            while (key_valid) @(posedge clk);   // предыдущее нажатие должно быть прочитано
            @(posedge clk);
            key_code  <= k;
            key_press <= 1'b1;
            @(posedge clk);
            key_press <= 1'b0;
            while (key_valid) @(posedge clk);   // ждём, пока программа прочитает клавишу
            repeat (SETTLE) @(posedge clk);     // и закончит обработку
        end
    endtask

    initial begin
        $dumpfile(`VCD_FILE);
        $dumpvars(0, tb_vending);

        // 0. Начальное состояние
        `SCENARIO("начальное состояние")
        `CHECK(16'hFFF0, 16'h0000, "после сброса: 0, LED погашены")

        // 1. Точная сумма: 5 + 2 = 7
        `SCENARIO("5, 2 -> товар без сдачи")
        press(5); `CHECK(16'hFFF5, 16'h0000, "баланс 5")
        press(2); `CHECK(16'hFFF0, 16'h0001, "товар выдан, сдача 0")

        // 2. Сдача: 5 + 5 = 10, сдача 3
        `SCENARIO("5, 5 -> товар и сдача 3")
        press(5); `CHECK(16'hFFF5, 16'h0000, "баланс 5")
        press(5); `CHECK(16'hFFF3, 16'h0003, "товар + сдача 3")

        // 3. Отмена: 2 + 1, затем 15 -> возврат 3
        `SCENARIO("2, 1, 15 -> возврат 3")
        press(2);  `CHECK(16'hFFF2, 16'h0000, "баланс 2")
        press(1);  `CHECK(16'hFFF3, 16'h0000, "баланс 3")
        press(15); `CHECK(16'hFFF3, 16'h0002, "возврат 3, товара нет")

        // 4. Накопление мелкими монетами: 1 x 7
        `SCENARIO("1 x 7 -> товар без сдачи")
        press(1); `CHECK(16'hFFF1, 16'h0000, "баланс 1")
        press(1); `CHECK(16'hFFF2, 16'h0000, "баланс 2")
        press(1); `CHECK(16'hFFF3, 16'h0000, "баланс 3")
        press(1); `CHECK(16'hFFF4, 16'h0000, "баланс 4")
        press(1); `CHECK(16'hFFF5, 16'h0000, "баланс 5")
        press(1); `CHECK(16'hFFF6, 16'h0000, "баланс 6")
        press(1); `CHECK(16'hFFF0, 16'h0001, "баланс 7: товар, сдача 0")

        // 5. 2 x 4 = 8, сдача 1
        `SCENARIO("2, 2, 2, 2 -> товар и сдача 1")
        press(2); `CHECK(16'hFFF2, 16'h0000, "баланс 2")
        press(2); `CHECK(16'hFFF4, 16'h0000, "баланс 4")
        press(2); `CHECK(16'hFFF6, 16'h0000, "баланс 6")
        press(2); `CHECK(16'hFFF1, 16'h0003, "товар + сдача 1")

        // 6. Сброс после покупки: нажатие только сбрасывает, не засчитывается
        `SCENARIO("5, 5, затем 5 -> сброс после покупки")
        press(5); `CHECK(16'hFFF5, 16'h0000, "баланс 5")
        press(5); `CHECK(16'hFFF3, 16'h0003, "товар + сдача 3")
        press(5); `CHECK(16'hFFF0, 16'h0000, "сброс: баланс 0 (а не 5)")
        press(1); `CHECK(16'hFFF1, 16'h0000, "после сброса монеты снова принимаются")

        // 7. Сброс после отмены
        `SCENARIO("2, 15, затем 1 -> сброс после возврата")
        press(2);  `CHECK(16'hFFF2, 16'h0000, "баланс 2")
        press(15); `CHECK(16'hFFF2, 16'h0002, "возврат 2")
        press(1);  `CHECK(16'hFFF0, 16'h0000, "сброс, клавиша 1 не засчитана")

        // 8. Отмена при нулевом балансе и посторонние клавиши
        `SCENARIO("15 и посторонние клавиши при балансе 0")
        press(15); `CHECK(16'hFFF0, 16'h0000, "отмена при балансе 0: ничего")
        press(9);  `CHECK(16'hFFF0, 16'h0000, "клавиша 9 игнорируется")
        press(0);  `CHECK(16'hFFF0, 16'h0000, "клавиша 0 игнорируется")

        // 9. Посторонние клавиши при ненулевом балансе
        `SCENARIO("5, затем посторонние клавиши")
        press(5);  `CHECK(16'hFFF5, 16'h0000, "баланс 5")
        press(3);  `CHECK(16'hFFF5, 16'h0000, "клавиша 3 игнорируется")
        press(14); `CHECK(16'hFFF5, 16'h0000, "клавиша 14 игнорируется")
        press(2);  `CHECK(16'hFFF0, 16'h0001, "баланс 7: товар")

        // 10. Наибольшая сдача: 5 + 1 + 5 = 11 -> сдача 4
        `SCENARIO("5, 1, 5 -> максимальная сдача 4")
        press(5); `CHECK(16'hFFF5, 16'h0000, "баланс 5")
        press(1); `CHECK(16'hFFF6, 16'h0000, "баланс 6")
        press(5); `CHECK(16'hFFF4, 16'h0003, "товар + сдача 4")

        $display("----------------------------------------------");
        $display("Проверок: %0d, ошибок: %0d", checks, errors);
        if (errors == 0) $display("TEST PASSED: автомат работает по спецификации");
        else             $display("TEST FAILED");
        $finish;
    end
endmodule
