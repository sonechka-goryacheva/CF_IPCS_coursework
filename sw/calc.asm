; =============================================================================
; calc.asm : калькулятор (задача №21). Клавиатура 4x4 -> 4 семисегментных
;            индикатора. Использует аппаратную инструкцию BIN2BCD.
;
; Клавиши:  0-9 цифры; 10 '+'; 11 '-'; 12 '*'; 13 '/'; 14 '='; 15 'C'.
;
; Правила (см. docs/CALC.md):
;  * Число вводится до 4 значащих цифр; цифра добавляется, только если текущее
;    значение < 1000 (ведущие нули не считаются, лишние цифры игнорируются).
;  * Знак операции запоминает операцию. Если второе число уже введено, сначала
;    вычисляется предыдущая операция (цепочка: 5 + 3 + -> 8). Два знака подряд:
;    второй заменяет первый. Знак без первого числа берёт текущее значение (0).
;  * '=' вычисляет A <операция> X, затем операция сбрасывается (повторное '='
;    ничего не делает); если вычислять нечего - не делает ничего.
;  * Результат: -999..9999. Выход за диапазон и деление на ноль -> 'E',
;    после чего работает только 'C'. Деление целочисленное (остаток отброшен,
;    в сторону нуля). Знак хранится отдельно от модуля; "-0" невозможен.
;
; Регистры: R1..R5 - временные, R6 - база MMIO (0xFF00), R7 - регистр связи.
; Переменные состояния лежат в RAM (секция .data).
; =============================================================================

        .equ MMIO,        0xFF00
        .equ KEY_STATUS,  0
        .equ KEY_DATA,    1
        .equ SEG,         3
        .equ KEY_EQ,      14
        .equ KEY_C,       15
        .equ ERR_SEG,     0xFFFE    ; индикаторы: "   E"

        .data
A_MAG:    .word 0                   ; |A| - накопитель (левый операнд)
A_NEG:    .word 0                   ; знак A: 0 '+', 1 '-'
X_VAL:    .word 0                   ; вводимое число (0..9999)
OP:       .word 0                   ; отложенная операция: 0 нет, 1 '+', 2 '-', 3 '*', 4 '/'
ENTERING: .word 0                   ; 1 - идёт ввод числа X
ERR:      .word 0                   ; 1 - режим ошибки
NEXTOP:   .word 0                   ; операция, которую надо запомнить после вычисления

        .text
start:  LI    R6, MMIO              ; R6 = 0xFF00

; ---- сброс (старт и клавиша C) ----
clear:  LDI   R1, 0
        STORE R1, [R0+A_MAG]
        STORE R1, [R0+A_NEG]
        STORE R1, [R0+X_VAL]
        STORE R1, [R0+OP]
        STORE R1, [R0+ENTERING]
        STORE R1, [R0+ERR]
        STORE R1, [R0+NEXTOP]
        LDI   R3, 0                 ; показать 0
        LDI   R4, 0
        CALL  show

; ---- главный цикл: ожидание клавиши и разбор ----
wait:   LOAD  R2, [R6+KEY_STATUS]
        SHR   R2, R2                ; C = VALID
        BLO   wait
        LOAD  R2, [R6+KEY_DATA]     ; R2 = код клавиши

        ADDI  R0, R2, -KEY_C        ; C?
        BEQ   clear
        LOAD  R1, [R0+ERR]
        ADDI  R0, R1, 0
        BNE   wait                  ; режим ошибки: все клавиши, кроме C, игнорируются

        LDI   R3, 10
        CMP   R2, R3
        BLO   digit                 ; 0..9 - цифра
        ADDI  R0, R2, -KEY_EQ
        BEQ   equals                ; 14 - '='
        ADDI  R2, R2, -9            ; 10..13 -> код операции 1..4
        JUMP  operator

; ---- цифра (R2 = 0..9) ----
digit:  LOAD  R3, [R0+ENTERING]
        ADDI  R0, R3, 0
        BEQ   dig_new               ; ввод не идёт: начать новое число
        LOAD  R1, [R0+X_VAL]
        LI    R4, 1000
        CMP   R1, R4
        BHS   wait                  ; X >= 1000: лишняя цифра игнорируется
        SHL   R3, R1                ; R3 = X*2
        SHL   R4, R1
        SHL   R4, R4
        SHL   R4, R4                ; R4 = X*8
        ADD   R1, R3, R4            ; X*10
        ADD   R1, R1, R2            ; X*10 + цифра
        JUMP  dig_show
dig_new:
        MOV   R1, R2                ; X = цифра
        LDI   R3, 1
        STORE R3, [R0+ENTERING]
dig_show:
        STORE R1, [R0+X_VAL]
        MOV   R3, R1                ; показать X
        LDI   R4, 0
        CALL  show
        JUMP  wait

; ---- знак операции (R2 = 1..4) ----
operator:
        LOAD  R3, [R0+OP]
        LOAD  R4, [R0+ENTERING]
        ADDI  R0, R3, 0
        BNE   op_pending
        ; отложенной операции нет
        ADDI  R0, R4, 0
        BEQ   op_set                ; ввода не было: A остаётся как есть
        LOAD  R1, [R0+X_VAL]        ; введённое число становится A
        STORE R1, [R0+A_MAG]
        LDI   R1, 0
        STORE R1, [R0+A_NEG]
op_set: STORE R2, [R0+OP]           ; запомнить операцию
        LDI   R1, 0
        STORE R1, [R0+ENTERING]
        JUMP  show_acc              ; показать A
op_pending:
        ADDI  R0, R4, 0
        BEQ   op_set                ; второго числа нет: заменить операцию
        STORE R2, [R0+NEXTOP]       ; цепочка: вычислить, затем запомнить новую
        JUMP  do_compute

; ---- '=' ----
equals: LOAD  R1, [R0+OP]
        ADDI  R0, R1, 0
        BEQ   wait                  ; операции нет
        LOAD  R1, [R0+ENTERING]
        ADDI  R0, R1, 0
        BEQ   wait                  ; второго числа нет
        LDI   R1, 0
        STORE R1, [R0+NEXTOP]       ; после '=' операция сбрасывается
        ; продолжается в do_compute

; ---- вычисление A <op> X (на выходе R3 = модуль, R5 = знак) ----
do_compute:
        LOAD  R4, [R0+OP]
        LOAD  R1, [R0+A_MAG]
        LOAD  R2, [R0+X_VAL]
        LOAD  R5, [R0+A_NEG]
        ADDI  R0, R4, -1
        BEQ   c_add
        ADDI  R0, R4, -2
        BEQ   c_sub
        ADDI  R0, R4, -3
        BEQ   c_mul

c_div:  ADDI  R0, R2, 0             ; делитель == 0 ?
        BEQ   error
        CALL  div                   ; R3 = |A| / X; знак результата = знак A (R5)
        JUMP  finish

c_mul:  CALL  mul                   ; R3 = |A| * X или 0xFFFF при переполнении
        JUMP  finish

c_add:  ADDI  R0, R5, 0
        BNE   add_neg
        ADD   R3, R1, R2            ; A >= 0: |A| + X
        JUMP  finish                ; знак '+' (R5 = 0)
add_neg:                            ; A < 0: X - |A|
        CMP   R2, R1
        BHS   add_np                ; X >= |A|: результат неотрицательный
        SUB   R3, R1, R2            ; |A| - X, знак остаётся '-'
        JUMP  finish
add_np: SUB   R3, R2, R1
        LDI   R5, 0
        JUMP  finish

c_sub:  ADDI  R0, R5, 0
        BNE   sub_neg
        CMP   R1, R2                ; A >= 0: A - X
        BHS   sub_pp
        SUB   R3, R2, R1            ; A < X: X - A, знак '-'
        LDI   R5, 1
        JUMP  finish
sub_pp: SUB   R3, R1, R2
        JUMP  finish                ; знак '+'
sub_neg:
        ADD   R3, R1, R2            ; A < 0: -(|A| + X), знак остаётся '-'
        JUMP  finish

; ---- проверка диапазона и сохранение результата (R3 = модуль, R5 = знак) ----
finish: ADDI  R0, R3, 0
        BNE   fin_chk
        LDI   R5, 0                 ; нулевой модуль: знак всегда '+' (нет "-0")
fin_chk:
        ADDI  R0, R5, 0
        BNE   fin_neg
        LI    R4, 9999
        CMP   R4, R3                ; 9999 - модуль
        BLO   error                 ; модуль > 9999
        JUMP  fin_store
fin_neg:
        LI    R4, 999
        CMP   R4, R3
        BLO   error                 ; результат < -999
fin_store:
        STORE R3, [R0+A_MAG]
        STORE R5, [R0+A_NEG]
        LOAD  R1, [R0+NEXTOP]
        STORE R1, [R0+OP]           ; новая отложенная операция (0 после '=')
        LDI   R1, 0
        STORE R1, [R0+ENTERING]
        ; продолжается в show_acc

show_acc:
        LOAD  R3, [R0+A_MAG]
        LOAD  R4, [R0+A_NEG]
        CALL  show
        JUMP  wait

; ---- ошибка: "E", дальше работает только C ----
error:  LI    R3, ERR_SEG
        STORE R3, [R6+SEG]
        LDI   R1, 1
        STORE R1, [R0+ERR]
        JUMP  wait

; -----------------------------------------------------------------------------
; show: вывод на индикаторы. Вход: R3 = модуль (0..9999), R4 = знак (0 '+', 1 '-').
;       Ведущие нули гасятся (0xF); минус (0xA) ставится вплотную к числу.
;       Портит R2, R3, R4 и флаги.
; -----------------------------------------------------------------------------
show:   BIN2BCD R2, R3              ; R2 = BCD (копия для сравнений)
        MOV   R3, R2                ; R3 = выводимое значение
        ADDI  R0, R4, 0
        BNE   show_neg
        LI    R4, 0x1000
        CMP   R2, R4
        BHS   show_out              ; >= 1000: все 4 разряда значащие
        LI    R4, 0xF000
        OR    R3, R3, R4            ; погасить тысячи
        LI    R4, 0x0100
        CMP   R2, R4
        BHS   show_out
        LI    R4, 0x0F00
        OR    R3, R3, R4            ; погасить сотни
        LI    R4, 0x0010
        CMP   R2, R4
        BHS   show_out
        LI    R4, 0x00F0
        OR    R3, R3, R4            ; погасить десятки
        JUMP  show_out
show_neg:                           ; модуль 1..999
        LI    R4, 0x0100
        CMP   R2, R4
        BLO   neg_lt100
        LI    R4, 0xA000
        OR    R3, R3, R4            ; 100..999: "-123"
        JUMP  show_out
neg_lt100:
        LI    R4, 0x0010
        CMP   R2, R4
        BLO   neg_lt10
        LI    R4, 0xFA00
        OR    R3, R3, R4            ; 10..99: " -42"
        JUMP  show_out
neg_lt10:
        LI    R4, 0xFFA0
        OR    R3, R3, R4            ; 1..9: "  -3"
show_out:
        STORE R3, [R6+SEG]
        RET

; -----------------------------------------------------------------------------
; mul: R3 = R1 * R2 (беззнаково, сдвиг и сложение). При переполнении 16 бит
;      R3 = 0xFFFF. Портит R1, R2, R3 и флаги.
; -----------------------------------------------------------------------------
mul:    LDI   R3, 0
mul_lp: SHR   R2, R2                ; C = младший бит множителя
        BLO   mul_sk
        ADD   R3, R3, R1
        BHS   mul_ov                ; перенос: произведение не помещается
mul_sk: ADDI  R0, R2, 0             ; множитель исчерпан?
        BEQ   mul_done
        SHL   R1, R1                ; множимое * 2
        BHS   mul_ov                ; потеряли старший бит, а множитель не пуст
        JUMP  mul_lp
mul_ov: LI    R3, 0xFFFF
mul_done:
        RET

; -----------------------------------------------------------------------------
; div: R3 = R1 / R2 (беззнаково, деление сдвигом и вычитанием, 16 итераций).
;      Делитель R2 != 0. Портит R1, R2, R3, R4 и флаги. R5 сохраняется.
; -----------------------------------------------------------------------------
div:    LDI   R3, 0                 ; остаток
        LDI   R4, 16                ; счётчик итераций
div_lp: SHL   R3, R3                ; остаток * 2
        SHL   R1, R1                ; C = старший бит делимого, в R1 копится частное
        BLO   div_nb
        ADDI  R3, R3, 1             ; внести бит делимого в остаток
div_nb: CMP   R3, R2                ; остаток >= делителя ?
        BLO   div_nx
        SUB   R3, R3, R2
        ADDI  R1, R1, 1             ; бит частного = 1
div_nx: ADDI  R4, R4, -1
        BNE   div_lp
        MOV   R3, R1                ; R3 = частное
        RET
