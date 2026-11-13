`timescale 1ns/1ps
// =============================================================================
// CPU_Core.v : процессорное ядро = Program_Counter + Control_Unit +
//              Register_File + ALU + регистры флагов Z, C.
//   Интерфейс: шина команд (ROM) и шина данных (адрес / данные / we / re).
// =============================================================================
module CPU_Core (
    input  wire        clk,
    input  wire        rst,

    // память команд
    output wire [10:0] rom_addr,
    input  wire [15:0] rom_data,

    // память данных / MMIO
    output wire [15:0] mem_addr,
    output wire [15:0] mem_wdata,
    output wire        mem_we,
    output wire        mem_re,
    input  wire [15:0] mem_rdata,

    output wire        halted,

    // отладочные выходы (для временных диаграмм)
    output wire [15:0] dbg_r1, dbg_r2, dbg_r3, dbg_r4, dbg_r5, dbg_r6, dbg_r7,
    output wire        dbg_z,
    output wire        dbg_c
);
    // ---- сигналы Control_Unit ----
    wire [2:0]  rd, rs, rt;
    wire [4:0]  imm5;
    wire [7:0]  imm8;
    wire [10:0] field11;
    wire        reg_we, b_sel_imm, rb_sel_rd, flag_we, pc_en;
    wire [1:0]  wb_sel, pc_mode;
    wire [3:0]  alu_op;

    // ---- флаги ----
    reg flag_z, flag_c;
    assign dbg_z = flag_z;
    assign dbg_c = flag_c;

    // ---- тракт данных ----
    wire [15:0] ra_data, rb_data;
    wire [15:0] imm5_sext = {{11{imm5[4]}}, imm5};
    wire [15:0] alu_b     = b_sel_imm ? imm5_sext : rb_data;
    wire [15:0] alu_y;
    wire        alu_c, alu_z;
    reg  [15:0] wdata;

    Control_Unit u_cu (
        .clk(clk), .rst(rst), .instr(rom_data),
        .flag_z(flag_z), .flag_c(flag_c),
        .rd(rd), .rs(rs), .rt(rt), .imm5(imm5), .imm8(imm8), .field11(field11),
        .reg_we(reg_we), .wb_sel(wb_sel), .alu_op(alu_op),
        .b_sel_imm(b_sel_imm), .rb_sel_rd(rb_sel_rd), .flag_we(flag_we),
        .mem_we(mem_we), .mem_re(mem_re),
        .pc_en(pc_en), .pc_mode(pc_mode), .halted(halted)
    );

    Program_Counter u_pc (
        .clk(clk), .rst(rst), .en(pc_en), .mode(pc_mode),
        .jump_addr(field11), .offset(field11), .reg_addr(ra_data[10:0]),
        .pc(rom_addr)
    );

    // Порт B регистров: rt (обычные команды) или rd (STORE - данные, LHI - старый rd)
    Register_File u_rf (
        .clk(clk), .rst(rst),
        .raddr_a(rs), .raddr_b(rb_sel_rd ? rd : rt),
        .rdata_a(ra_data), .rdata_b(rb_data),
        .we(reg_we), .waddr(rd), .wdata(wdata),
        .r1(dbg_r1), .r2(dbg_r2), .r3(dbg_r3), .r4(dbg_r4),
        .r5(dbg_r5), .r6(dbg_r6), .r7(dbg_r7)
    );

    ALU u_alu (.a(ra_data), .b(alu_b), .op(alu_op), .y(alu_y), .c(alu_c), .z(alu_z));

    // Мультиплексор данных для записи в регистр
    always @* begin
        case (wb_sel)
            2'd0:    wdata = alu_y;                       // результат АЛУ
            2'd1:    wdata = {8'd0, imm8};                // LDI
            2'd2:    wdata = {imm8, rb_data[7:0]};        // LHI
            default: wdata = mem_rdata;                   // LOAD
        endcase
    end

    // Шина данных
    assign mem_addr  = alu_y;       // rs + sext(imm5)
    assign mem_wdata = rb_data;     // для STORE это значение rd

    // Регистры флагов
    always @(posedge clk) begin
        if (rst) begin
            flag_z <= 1'b0;
            flag_c <= 1'b0;
        end else if (flag_we) begin
            flag_z <= alu_z;
            flag_c <= alu_c;
        end
    end
endmodule
