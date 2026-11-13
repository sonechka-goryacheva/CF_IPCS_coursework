`timescale 1ns/1ps
// =============================================================================
// Memory_Top.v : подсистема данных = Data_RAM + MMIO-декодер + периферия.
//
//   Карта адресов (память данных):
//     0x0000-0x00FF  Data_RAM
//     0xFF00  KEY_STATUS (R)  бит 0 = VALID
//     0xFF01  KEY_DATA   (R)  биты [3:0] = код клавиши; чтение сбрасывает VALID
//     0xFF02  LED        (R/W)
//     0xFF03  SEG        (R/W) 4 тетрады: 0-9 цифры, A '-', E 'E', F погашено
//     прочие адреса: чтение 0, запись игнорируется
//
//   Нажатие клавиши подаёт внешний мост/тестбенч: key_press (строб, 1 такт)
//   и key_code. Если VALID уже равен 1, новое нажатие игнорируется.
// =============================================================================
module Memory_Top #(
    parameter RAM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,

    // шина данных от процессора
    input  wire [15:0] addr,
    input  wire [15:0] wdata,
    input  wire        we,
    input  wire        re,        // строб чтения (1 такт)
    output reg  [15:0] rdata,

    // внешние сигналы периферии
    input  wire        key_press,
    input  wire [3:0]  key_code,
    output wire        key_valid,
    output wire [15:0] led,
    output wire [15:0] seg
);
    // ---- декодер адреса ----
    wire ram_sel  = (addr[15:8] == 8'h00);
    wire mmio_sel = (addr[15:2] == 14'h3FC0);          // 0xFF00..0xFF03
    wire [1:0] reg_idx = addr[1:0];

    wire sel_key_status = mmio_sel && (reg_idx == 2'd0);
    wire sel_key_data   = mmio_sel && (reg_idx == 2'd1);
    wire sel_led        = mmio_sel && (reg_idx == 2'd2);
    wire sel_seg        = mmio_sel && (reg_idx == 2'd3);

    // ---- Data_RAM ----
    wire [15:0] ram_rdata;
    Data_RAM #(.INIT_FILE(RAM_INIT_FILE)) u_ram (
        .clk(clk), .we(we & ram_sel), .addr(addr[7:0]),
        .wdata(wdata), .rdata(ram_rdata)
    );

    // ---- регистры периферии (синхронный сброс) ----
    reg        key_valid_r;
    reg [3:0]  key_data_r;
    reg [15:0] led_r;
    reg [15:0] seg_r;

    assign key_valid = key_valid_r;
    assign led       = led_r;
    assign seg       = seg_r;

    always @(posedge clk) begin
        if (rst) begin
            key_valid_r <= 1'b0;
            key_data_r  <= 4'd0;
            led_r       <= 16'd0;
            seg_r       <= 16'hFFFF;                    // все разряды погашены
        end else begin
            // приём нажатия (если предыдущее ещё не прочитано - игнорируем)
            if (key_press && !key_valid_r) begin
                key_valid_r <= 1'b1;
                key_data_r  <= key_code;
            end
            // чтение KEY_DATA сбрасывает VALID (re длится ровно один такт)
            if (re && sel_key_data)
                key_valid_r <= 1'b0;
            // запись LED / SEG
            if (we && sel_led) led_r <= wdata;
            if (we && sel_seg) seg_r <= wdata;
        end
    end

    // ---- мультиплексор чтения ----
    always @* begin
        if (ram_sel)               rdata = ram_rdata;
        else if (sel_key_status)   rdata = {15'd0, key_valid_r};
        else if (sel_key_data)     rdata = {12'd0, key_data_r};
        else if (sel_led)          rdata = led_r;
        else if (sel_seg)          rdata = seg_r;
        else                       rdata = 16'd0;
    end
endmodule
