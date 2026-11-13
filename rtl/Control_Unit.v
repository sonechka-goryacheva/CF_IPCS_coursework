`timescale 1ns/1ps
// =============================================================================
// Control_Unit.v : устройство управления - конечный автомат + декодер команд.
//
//   Состояния (многотактное выполнение, 2 такта на команду):
//     S_FETCH : читаем команду из ROM в регистр IR;
//     S_EXEC  : декодируем IR и выполняем (запись регистра / памяти / флагов / PC);
//     S_HALT  : останов (команда HLT или зарезервированный код); выход - только rst.
//   Все управляющие сигналы с побочным эффектом активны только в S_EXEC,
//   поэтому строб чтения/записи памяти длится ровно один такт.
// =============================================================================
module Control_Unit (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] instr,      // команда с выхода Instruction_ROM
    input  wire        flag_z,
    input  wire        flag_c,

    // поля команды
    output wire [2:0]  rd,
    output wire [2:0]  rs,
    output wire [2:0]  rt,
    output wire [4:0]  imm5,
    output wire [7:0]  imm8,
    output wire [10:0] field11,

    // управление трактом данных
    output reg         reg_we,       // запись в регистровый файл
    output reg  [1:0]  wb_sel,       // 0: ALU, 1: LDI, 2: LHI, 3: данные памяти
    output reg  [3:0]  alu_op,       // операция АЛУ
    output reg         b_sel_imm,    // 1: операнд B = sext(imm5)
    output reg         rb_sel_rd,    // 1: порт B регистров читает rd (STORE, LHI)
    output reg         flag_we,      // запись флагов Z, C
    output reg         mem_we,       // запись в память данных
    output reg         mem_re,       // чтение памяти данных (строб)
    output reg         pc_en,
    output reg  [1:0]  pc_mode,
    output wire        halted
);
    // ---- коды операций (см. ISA.md) ----
    localparam OP_ADD = 5'h00, OP_SUB = 5'h01, OP_AND = 5'h02, OP_OR  = 5'h03,
               OP_XOR = 5'h04, OP_NOT = 5'h05, OP_SHL = 5'h06, OP_SHR = 5'h07,
               OP_CMP = 5'h08, OP_BCD = 5'h09, OP_ADDI= 5'h0A, OP_LDI = 5'h0B,
               OP_LHI = 5'h0C, OP_LOAD= 5'h0D, OP_STORE=5'h0E, OP_JUMP= 5'h0F,
               OP_BEQ = 5'h10, OP_BNE = 5'h11, OP_BLO = 5'h12, OP_BHS = 5'h13,
               OP_HLT = 5'h14, OP_JR  = 5'h15;

    // ---- коды операций АЛУ (внутренние, совпадают с ALU.v) ----
    localparam ALU_ADD = 4'd0, ALU_SUB = 4'd1, ALU_AND = 4'd2, ALU_OR  = 4'd3,
               ALU_XOR = 4'd4, ALU_NOT = 4'd5, ALU_SHL = 4'd6, ALU_SHR = 4'd7,
               ALU_BCD = 4'd8;

    // ---- состояния автомата ----
    localparam S_FETCH = 2'd0, S_EXEC = 2'd1, S_HALT = 2'd2;

    reg [1:0]  state;
    reg [15:0] ir;

    assign rd      = ir[10:8];
    assign rs      = ir[7:5];
    assign rt      = ir[4:2];
    assign imm5    = ir[4:0];
    assign imm8    = ir[7:0];
    assign field11 = ir[10:0];
    assign halted  = (state == S_HALT);

    wire [4:0] op   = ir[15:11];
    wire       exec = (state == S_EXEC);

    // HLT и все зарезервированные коды (> 0x15) останавливают процессор
    wire is_halt = (op == OP_HLT) || (op > OP_JR);

    // ---- регистр состояния и IR ----
    always @(posedge clk) begin
        if (rst) begin
            state <= S_FETCH;
            ir    <= 16'd0;
        end else begin
            case (state)
                S_FETCH: begin ir <= instr; state <= S_EXEC; end
                S_EXEC : state <= is_halt ? S_HALT : S_FETCH;
                default: state <= S_HALT;
            endcase
        end
    end

    // ---- условие ветвления (по текущим флагам) ----
    reg take_branch;
    always @* begin
        case (op)
            OP_BEQ:  take_branch = flag_z;
            OP_BNE:  take_branch = ~flag_z;
            OP_BLO:  take_branch = ~flag_c;
            OP_BHS:  take_branch = flag_c;
            default: take_branch = 1'b0;
        endcase
    end

    // ---- декодер: комбинационные управляющие сигналы ----
    always @* begin
        // значения по умолчанию (NOP-подобные)
        reg_we    = 1'b0;
        wb_sel    = 2'd0;
        alu_op    = ALU_ADD;
        b_sel_imm = 1'b0;
        rb_sel_rd = 1'b0;
        flag_we   = 1'b0;
        mem_we    = 1'b0;
        mem_re    = 1'b0;
        pc_en     = exec & ~is_halt;
        pc_mode   = 2'd0;

        case (op)
            OP_ADD: begin alu_op = ALU_ADD; reg_we = exec; flag_we = exec; end
            OP_SUB: begin alu_op = ALU_SUB; reg_we = exec; flag_we = exec; end
            OP_AND: begin alu_op = ALU_AND; reg_we = exec; flag_we = exec; end
            OP_OR : begin alu_op = ALU_OR ; reg_we = exec; flag_we = exec; end
            OP_XOR: begin alu_op = ALU_XOR; reg_we = exec; flag_we = exec; end
            OP_NOT: begin alu_op = ALU_NOT; reg_we = exec; flag_we = exec; end
            OP_SHL: begin alu_op = ALU_SHL; reg_we = exec; flag_we = exec; end
            OP_SHR: begin alu_op = ALU_SHR; reg_we = exec; flag_we = exec; end
            OP_CMP: begin alu_op = ALU_SUB;                flag_we = exec; end   // без записи регистра
            OP_BCD: begin alu_op = ALU_BCD; reg_we = exec; flag_we = exec; end
            OP_ADDI: begin
                alu_op = ALU_ADD; b_sel_imm = 1'b1; reg_we = exec; flag_we = exec;
            end
            OP_LDI: begin wb_sel = 2'd1; reg_we = exec; end
            OP_LHI: begin wb_sel = 2'd2; rb_sel_rd = 1'b1; reg_we = exec; end
            OP_LOAD: begin
                alu_op = ALU_ADD; b_sel_imm = 1'b1;       // адрес = rs + imm5
                wb_sel = 2'd3; reg_we = exec; mem_re = exec;
            end
            OP_STORE: begin
                alu_op = ALU_ADD; b_sel_imm = 1'b1;       // адрес = rs + imm5
                rb_sel_rd = 1'b1; mem_we = exec;          // данные = rd
            end
            OP_JUMP: pc_mode = 2'd1;
            OP_BEQ, OP_BNE, OP_BLO, OP_BHS: pc_mode = take_branch ? 2'd2 : 2'd0;
            OP_JR:   pc_mode = 2'd3;
            default: ;   // HLT / зарезервированные: pc_en уже 0
        endcase
    end
endmodule
