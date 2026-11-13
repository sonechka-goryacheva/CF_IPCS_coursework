/*
 * kbd.c - VPI-модуль для Icarus Verilog: интерактивный мост "симулятор <-> терминал".
 *
 * Системные задачи и функции, доступные из Verilog:
 *   $kb_init(quiet, "ПРОГРАММА") - перевести терминал в режим посимвольного ввода
 *                                  без ожидания и без эха; quiet = 1 отключает рисование.
 *                                  ПРОГРАММА: "CALC" или "VENDING" (заголовок и подсказка).
 *   k = $kb_get                  - неблокирующее чтение клавиши ПК. Возвращает:
 *                                    -1      нет нажатия (или клавиша без назначения)
 *                                    0..15   код клавиши клавиатуры 4x4 (см. таблицу ниже)
 *                                    100     пользователь нажал q (выход)
 *                                    101     конец ввода (stdin закрыт, режим скрипта)
 *   $kb_draw(seg, led)           - перерисовать экран, если значения изменились
 *   $kb_wait(мс)                 - пауза, чтобы симулятор не нагружал процессор на 100%
 *   $kb_exit                     - вернуть терминал в исходный режим
 *
 * Соответствие клавиш ПК кодам клавиатуры 4x4 (одинаково для автомата и калькулятора):
 *   0-9 -> 0-9;  + -> 10;  - -> 11;  * или x -> 12;  / -> 13;
 *   = или Enter -> 14;  c, C или Backspace -> 15;  q -> выход.
 */
#include <vpi_user.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <signal.h>
#include <errno.h>
#include <time.h>

static struct termios saved_tio;
static int tio_saved = 0, is_tty = 0, cursor_hidden = 0, quiet = 0, frame_started = 0;
static char program[16] = "CALC";
static long shown_seg = -1, shown_led = -1;   /* что сейчас нарисовано */
static int  shown_key = -2;
static int  last_key_code = -1;
static char last_key_char = ' ';
static int  force_draw = 1;

/* ---- терминал ---------------------------------------------------------- */
static void restore_terminal(void)
{
    if (cursor_hidden) { fputs("\x1b[?25h", stdout); cursor_hidden = 0; fflush(stdout); }
    if (tio_saved)     { tcsetattr(STDIN_FILENO, TCSANOW, &saved_tio); tio_saved = 0; }
}

static void on_signal(int sig)
{
    restore_terminal();
    signal(sig, SIG_DFL);
    raise(sig);
}

/* ---- получение аргументов VPI ------------------------------------------- */
static long arg_int(vpiHandle args, int *ok)
{
    vpiHandle a = vpi_scan(args);
    s_vpi_value v;
    if (!a) { *ok = 0; return 0; }
    v.format = vpiIntVal;
    vpi_get_value(a, &v);
    return v.value.integer;
}

/* ---- $kb_init ----------------------------------------------------------- */
static PLI_INT32 kb_init_calltf(PLI_BYTE8 *u)
{
    struct termios raw;
    vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle args = vpi_iterate(vpiArgument, call);
    int ok = 1;
    (void)u;
    quiet = (int)arg_int(args, &ok);
    if (args) {
        vpiHandle a = vpi_scan(args);
        if (a) {
            s_vpi_value v; v.format = vpiStringVal; vpi_get_value(a, &v);
            if (v.value.str) { strncpy(program, v.value.str, sizeof(program) - 1); program[sizeof(program) - 1] = 0; }
            vpi_free_object(args);
        }
    }
    is_tty = isatty(STDIN_FILENO);
    if (is_tty) {
        if (tcgetattr(STDIN_FILENO, &saved_tio) == 0) {
            raw = saved_tio;
            raw.c_lflag &= ~(ICANON | ECHO);   /* ISIG оставлен: Ctrl+C завершает программу */
            raw.c_cc[VMIN] = 0;                /* read() не ждёт нажатия */
            raw.c_cc[VTIME] = 0;
            tcsetattr(STDIN_FILENO, TCSANOW, &raw);
            tio_saved = 1;
        }
    } else {
        fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
    }
    atexit(restore_terminal);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    if (!quiet && is_tty) { fputs("\x1b[?25l", stdout); cursor_hidden = 1; fflush(stdout); }
    return 0;
}

/* ---- $kb_get ------------------------------------------------------------ */
static PLI_INT32 kb_get_calltf(PLI_BYTE8 *u)
{
    vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
    s_vpi_value v;
    unsigned char ch;
    int code = -1;
    ssize_t n;
    (void)u;

    n = read(STDIN_FILENO, &ch, 1);
    if (n == 1) {
        switch (ch) {
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9': code = ch - '0'; break;
        case '+': code = 10; break;
        case '-': code = 11; break;
        case '*': case 'x': case 'X': code = 12; break;
        case '/': code = 13; break;
        case '=': case '\r': case '\n': code = 14; break;
        case 'c': case 'C': case 0x7f: case 0x08: code = 15; break;
        case 'q': case 'Q': code = 100; break;
        default: code = -1; break;
        }
        if (code >= 0 && code <= 15) {
            last_key_code = code;
            last_key_char = (code <= 9) ? (char)('0' + code) :
                            (code == 10) ? '+' : (code == 11) ? '-' : (code == 12) ? '*' :
                            (code == 13) ? '/' : (code == 14) ? '=' : 'C';
        }
    } else if (n == 0 && !is_tty) {
        code = 101;                            /* конец входного потока (режим скрипта) */
    }
    v.format = vpiIntVal;
    v.value.integer = code;
    vpi_put_value(call, &v, NULL, vpiNoDelay);
    return 0;
}

/* ---- рисование ---------------------------------------------------------- */
/* Сегменты a b c d e f g для тетрады 0..F (0-9 цифры, A = '-', E = 'E', остальные погашены) */
enum { A = 1, B = 2, C = 4, D = 8, E = 16, F = 32, G = 64 };
static const unsigned char SEG7[16] = {
    A|B|C|D|E|F, B|C, A|B|D|E|G, A|B|C|D|G, B|C|F|G, A|C|D|F|G, A|C|D|E|F|G, A|B|C,
    A|B|C|D|E|F|G, A|B|C|D|F|G, G, 0, 0, 0, A|D|E|F|G, 0
};

static void digit_rows(int nib, char rows[3][4])
{
    unsigned s = SEG7[nib & 15];
    sprintf(rows[0], " %c ", (s & A) ? '_' : ' ');
    sprintf(rows[1], "%c%c%c", (s & F) ? '|' : ' ', (s & G) ? '_' : ' ', (s & B) ? '|' : ' ');
    sprintf(rows[2], "%c%c%c", (s & E) ? '|' : ' ', (s & D) ? '_' : ' ', (s & C) ? '|' : ' ');
}

static void draw_frame(long seg, long led)
{
    int i, r;
    char d[4][3][4];
    for (i = 0; i < 4; i++) digit_rows((int)((seg >> (4 * (3 - i))) & 15), d[i]);

    if (!frame_started) { fputs("\x1b[2J", stdout); frame_started = 1; }
    fputs("\x1b[H", stdout);

    if (strcmp(program, "VENDING") == 0)
        fputs("  Автомат с едой (цена 7 руб.)\x1b[K\n", stdout);
    else
        fputs("  Калькулятор\x1b[K\n", stdout);
    fputs("\x1b[K\n", stdout);
    fputs("  +------------------------+\x1b[K\n", stdout);
    for (r = 0; r < 3; r++) {
        fputs("  |  ", stdout);
        for (i = 0; i < 4; i++) fprintf(stdout, "%s  ", d[i][r]);
        fputs("|\x1b[K\n", stdout);
    }
    fputs("  +------------------------+\x1b[K\n", stdout);
    fputs("\x1b[K\n", stdout);
    fputs("  LED: ", stdout);
    for (i = 0; i < 8; i++) fputs(((led >> i) & 1) ? "\x1b[1;32m* \x1b[0m" : ". ", stdout);
    fputs("  (LED0 слева)\x1b[K\n", stdout);
    fprintf(stdout, "  SEG = 0x%04lX   LED = 0x%04lX\x1b[K\n", seg & 0xFFFF, led & 0xFFFF);
    if (last_key_code >= 0)
        fprintf(stdout, "  Последняя клавиша: '%c' (код %d)\x1b[K\n", last_key_char, last_key_code);
    else
        fputs("  Последняя клавиша: -\x1b[K\n", stdout);
    fputs("\x1b[K\n", stdout);
    if (strcmp(program, "VENDING") == 0) {
        fputs("  1, 2, 5 - монеты 1, 2, 5 руб.   c - отмена (возврат)   q - выход\x1b[K\n", stdout);
        fputs("  LED0 - товар выдан, LED1 - показана сдача (возврат)\x1b[K\n", stdout);
    } else {
        fputs("  0-9 цифры   + - * / операции   = или Enter   c - сброс   q - выход\x1b[K\n", stdout);
        fputs("  Индикатор: \"-\" минус, \"E\" ошибка\x1b[K\n", stdout);
    }
    fflush(stdout);
}

static PLI_INT32 kb_draw_calltf(PLI_BYTE8 *u)
{
    vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle args = vpi_iterate(vpiArgument, call);
    int ok = 1;
    long seg, led;
    (void)u;
    seg = arg_int(args, &ok);
    led = arg_int(args, &ok);
    if (args) vpi_free_object(args);
    if (quiet) return 0;
    if (force_draw || seg != shown_seg || led != shown_led || last_key_code != shown_key) {
        draw_frame(seg, led);
        shown_seg = seg; shown_led = led; shown_key = last_key_code;
        force_draw = 0;
    }
    return 0;
}

/* ---- $kb_wait ------------------------------------------------------------ */
static PLI_INT32 kb_wait_calltf(PLI_BYTE8 *u)
{
    vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle args = vpi_iterate(vpiArgument, call);
    int ok = 1;
    long ms = arg_int(args, &ok);
    struct timespec ts;
    (void)u;
    if (args) vpi_free_object(args);
    if (ms > 0) {
        ts.tv_sec = ms / 1000;
        ts.tv_nsec = (ms % 1000) * 1000000L;
        nanosleep(&ts, NULL);
    }
    return 0;
}

/* ---- $kb_exit ------------------------------------------------------------- */
static PLI_INT32 kb_exit_calltf(PLI_BYTE8 *u)
{
    (void)u;
    restore_terminal();
    if (!quiet && frame_started) fputs("\n", stdout);
    fflush(stdout);
    return 0;
}

/* ---- регистрация ----------------------------------------------------------- */
static void reg_task(const char *name, PLI_INT32 (*fn)(PLI_BYTE8 *))
{
    s_vpi_systf_data t;
    memset(&t, 0, sizeof t);
    t.type = vpiSysTask;
    t.tfname = (PLI_BYTE8 *)name;
    t.calltf = fn;
    vpi_register_systf(&t);
}

static void register_all(void)
{
    s_vpi_systf_data t;
    reg_task("$kb_init", kb_init_calltf);
    reg_task("$kb_draw", kb_draw_calltf);
    reg_task("$kb_wait", kb_wait_calltf);
    reg_task("$kb_exit", kb_exit_calltf);
    memset(&t, 0, sizeof t);
    t.type = vpiSysFunc;
    t.sysfunctype = vpiIntFunc;
    t.tfname = (PLI_BYTE8 *)"$kb_get";
    t.calltf = kb_get_calltf;
    vpi_register_systf(&t);
}

void (*vlog_startup_routines[])(void) = { register_all, 0 };
