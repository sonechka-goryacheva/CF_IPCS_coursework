`timescale 1ns/1ps
// =============================================================================
// tb_play.v : ИНТЕРАКТИВНЫЙ мост "симулятор <-> клавиатура и экран ПК".
//   Это не автоматический тест: процессор работает, пока вы нажимаете клавиши
//   в окне Терминала; индикаторы и светодиоды рисуются там же (vpi/kbd.c).
//
//   Цикл моста: выполнить CYCLES тактов процессора -> прочитать клавишу ПК
//   (без ожидания) -> если процессор готов принять клавишу (key_valid = 0),
//   подать её на вход клавиатуры -> перерисовать экран -> небольшая пауза.
//   Клавиша, пришедшая раньше времени, ждёт своей очереди, поэтому нажатия не
//   теряются.
//
//   Ключи запуска (vvp ... +ключ):
//     +nodraw  не рисовать экран (для автоматического стресс-теста)
//     +fast    без пауз и с более частым опросом (стресс-тест)
//   Если stdin не терминал (скрипт), конец ввода завершает симуляцию, и в
//   последней строке печатается итоговое состояние: "FINAL seg=... led=...".
// =============================================================================

`ifndef ROM_FILE
`define ROM_FILE "sw/calc.rom.mem"
`endif
`ifndef RAM_FILE
`define RAM_FILE "sw/calc.ram.mem"
`endif
`ifndef PROGRAM
`define PROGRAM "CALC"
`endif

module tb_play;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         key_press = 1'b0;
    reg  [3:0]  key_code  = 4'd0;
    wire        key_valid, halted;
    wire [15:0] led, seg;

    always #5 clk = ~clk;                       // 100 МГц (модельное время)

    soc_top #(.ROM_FILE(`ROM_FILE), .RAM_FILE(`RAM_FILE)) dut (
        .clk(clk), .rst(rst),
        .key_press(key_press), .key_code(key_code), .key_valid(key_valid),
        .led(led), .seg(seg), .halted(halted)
    );

    integer     cycles_per_poll;   // тактов процессора между опросами клавиатуры
    integer     sleep_ms;          // пауза между опросами (не грузить процессор ПК)
    integer     k;
    reg         have;              // есть клавиша, ожидающая подачи
    reg  [3:0]  pend;
    reg         quit;
    integer     quiet;

    initial begin
        cycles_per_poll = 500;
        sleep_ms        = 5;
        quiet           = $test$plusargs("nodraw");
        if ($test$plusargs("fast")) begin
            cycles_per_poll = 100;
            sleep_ms        = 0;
        end

        $kb_init(quiet, `PROGRAM);
        have = 1'b0;
        quit = 1'b0;

        repeat (3) @(posedge clk);
        rst <= 1'b0;
        repeat (1500) @(posedge clk);           // программа выполняет начальную инициализацию
        $kb_draw(seg, led);

        while (!(quit && !have)) begin
            repeat (cycles_per_poll) @(posedge clk);

            if (!have) begin
                k = $kb_get;
                if (k >= 0 && k <= 15) begin
                    pend = k[3:0];
                    have = 1'b1;
                end else if (k == 100 || k == 101)
                    quit = 1'b1;
            end

            if (have && !key_valid) begin       // клавиатура свободна: подаём нажатие
                key_code  <= pend;
                key_press <= 1'b1;
                @(posedge clk);
                key_press <= 1'b0;
                have = 1'b0;
            end

            $kb_draw(seg, led);
            $kb_wait(sleep_ms);
        end

        repeat (3000) @(posedge clk);           // дать программе дообработать последнюю клавишу
        $kb_draw(seg, led);
        $kb_exit;
        $display("FINAL seg=%h led=%h", seg, led);
        $finish(0);
    end
endmodule
