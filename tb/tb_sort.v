// =============================================================================
// tb_sort.v : самопроверяющийся тестбенч для программы пузырьковой сортировки.
//   Сценарий: сброс -> загрузка ROM/RAM ($readmemb в модулях) -> запуск
//   процессора -> ожидание HLT -> проверка массива в RAM -> PASS/FAIL.
//   Временные диаграммы: sim/tb_sort.vcd (открыть в GTKWave).
//   Трассировка выполняемых команд: запуск с ключом +trace.
// =============================================================================
`timescale 1ns/1ps

// Имена файлов можно переопределить ключом компилятора, например:
//   iverilog -DROM_FILE=\"sw/sort.rom.mem\" ...  (см. Makefile, цель sort-asm)
`ifndef ROM_FILE
`define ROM_FILE "sw/sort_rom.mem"
`endif
`ifndef RAM_FILE
`define RAM_FILE "sw/sort_data.mem"
`endif
`ifndef VCD_FILE
`define VCD_FILE "sim/tb_sort.vcd"
`endif

module tb_sort;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    wire        halted;
    wire        key_valid;
    wire [15:0] led, seg;

    // тактовый сигнал 100 МГц
    always #5 clk = ~clk;

    soc_top #(
        .ROM_FILE(`ROM_FILE),
        .RAM_FILE(`RAM_FILE)
    ) dut (
        .clk(clk), .rst(rst),
        .key_press(1'b0), .key_code(4'd0), .key_valid(key_valid),
        .led(led), .seg(seg), .halted(halted)
    );

    // ---- эталонный результат ----
    reg [15:0] expected [0:9];
    integer i, errors, cycles;

    // ---- сигналы для временных диаграмм ----
    wire [10:0] pc    = dut.u_cpu.rom_addr;
    wire [15:0] ir    = dut.u_cpu.u_cu.ir;
    wire [1:0]  state = dut.u_cpu.u_cu.state;
    wire [15:0] r1 = dut.u_cpu.dbg_r1, r2 = dut.u_cpu.dbg_r2,
                r3 = dut.u_cpu.dbg_r3, r4 = dut.u_cpu.dbg_r4;
    wire        flag_z = dut.u_cpu.dbg_z, flag_c = dut.u_cpu.dbg_c;
    wire [15:0] ram0 = dut.u_mem.u_ram.mem[0], ram1 = dut.u_mem.u_ram.mem[1],
                ram2 = dut.u_mem.u_ram.mem[2], ram3 = dut.u_mem.u_ram.mem[3],
                ram4 = dut.u_mem.u_ram.mem[4], ram5 = dut.u_mem.u_ram.mem[5],
                ram6 = dut.u_mem.u_ram.mem[6], ram7 = dut.u_mem.u_ram.mem[7],
                ram8 = dut.u_mem.u_ram.mem[8], ram9 = dut.u_mem.u_ram.mem[9];

    // ---- трассировка (по ключу +trace) ----
    always @(posedge clk)
        if (!rst && state == 2'd1 && $test$plusargs("trace"))
            $display("[%0t] PC=%03h IR=%04h  R1=%0d R2=%0d R3=%0d R4=%0d Z=%b C=%b",
                     $time, pc, ir, r1, r2, r3, r4, flag_z, flag_c);

    initial begin
        $dumpfile(`VCD_FILE);
        $dumpvars(0, tb_sort);

        expected[0] = 16'd0;    expected[1] = 16'd3;
        expected[2] = 16'd7;    expected[3] = 16'd7;
        expected[4] = 16'd15;   expected[5] = 16'd42;
        expected[6] = 16'd99;   expected[7] = 16'd300;
        expected[8] = 16'd1000; expected[9] = 16'd65535;

        $display("Массив до сортировки:");
        for (i = 0; i < 10; i = i + 1)
            $display("  RAM[%0d] = %0d", i, dut.u_mem.u_ram.mem[i]);

        // сброс
        repeat (3) @(posedge clk);
        rst = 1'b0;

        // ожидание останова (тайм-аут 100000 тактов)
        cycles = 0;
        while (!halted && cycles < 100000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        @(posedge clk);

        $display("Процессор остановлен (HLT) через %0d тактов", cycles);
        $display("Массив после сортировки:");
        errors = 0;
        for (i = 0; i < 10; i = i + 1) begin
            $display("  RAM[%0d] = %0d (ожидалось %0d)", i,
                     dut.u_mem.u_ram.mem[i], expected[i]);
            if (dut.u_mem.u_ram.mem[i] !== expected[i]) errors = errors + 1;
        end

        if (!halted)
            $display("TEST FAILED: тайм-аут, процессор не дошёл до HLT");
        else if (errors == 0)
            $display("TEST PASSED: массив отсортирован верно");
        else
            $display("TEST FAILED: ошибок = %0d", errors);
        $finish;
    end
endmodule
