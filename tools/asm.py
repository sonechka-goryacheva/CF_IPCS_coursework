#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
asm.py - двухпроходный ассемблер для 16-битного процессора курсового проекта.
Система команд описана в docs/ISA.md, синтаксис ассемблера - в docs/ASSEMBLER.md.

Использование:
    python3 tools/asm.py sw/sort.asm [--rom FILE] [--ram FILE] [--list FILE] [--hex]

Результат:
    *.rom.mem - образ памяти команд (для $readmemb, с ключом --hex - для $readmemh)
    *.ram.mem - образ памяти данных из секции .data (если она есть)
    *.lst     - листинг: адрес, машинное слово, исходная строка, таблица символов

Алгоритм:
    Проход 1: разбор строк, учёт меток, директив и размера каждой команды
              (псевдокоманды занимают 1-3 слова), назначение адресов.
    Проход 2: вычисление выражений (метки уже известны, в том числе
              "вперёд"), проверка диапазонов, кодирование в 16-битные слова.
"""
import argparse
import os
import re
import sys

ROM_WORDS = 2048           # размер памяти команд (слов)
RAM_WORDS = 256            # размер памяти данных (слов)

# ---------------------------------------------------------------------------
# Таблицы команд (коды операций - из docs/ISA.md)
# ---------------------------------------------------------------------------
OPS_R3 = {"ADD": 0x00, "SUB": 0x01, "AND": 0x02, "OR": 0x03, "XOR": 0x04}   # rd, rs, rt
OPS_R2 = {"NOT": 0x05, "SHL": 0x06, "SHR": 0x07, "BIN2BCD": 0x09}           # rd, rs
OP_CMP, OP_ADDI, OP_LDI, OP_LHI = 0x08, 0x0A, 0x0B, 0x0C
OP_LOAD, OP_STORE, OP_JUMP = 0x0D, 0x0E, 0x0F
BRANCHES = {"BEQ": 0x10, "BNE": 0x11, "BLO": 0x12, "BHS": 0x13}
OP_HLT, OP_JR = 0x14, 0x15

PSEUDO = {"NOP", "MOV", "LI", "CALL", "RET"}
MNEMONICS = (set(OPS_R3) | set(OPS_R2) | set(BRANCHES) | PSEUDO |
             {"CMP", "ADDI", "LDI", "LHI", "LOAD", "STORE", "JUMP", "HLT", "JR"})
DIRECTIVES = {".text", ".data", ".org", ".equ", ".word", ".space"}
REGISTERS = {"R%d" % i: i for i in range(8)}


class AsmError(Exception):
    """Ошибка ассемблирования (с номером строки)."""
    def __init__(self, msg, line_no=None, text=None):
        super().__init__(msg)
        self.msg, self.line_no, self.text = msg, line_no, text


class UndefinedSymbol(AsmError):
    pass


# ---------------------------------------------------------------------------
# Вычисление выражений
#   числа: 123, 0x1F, 0b101; символы (метки, .equ); операции:
#   | ^ & << >> + - * / % унарные - + ~ ; скобки; функции lo(x), hi(x)
# ---------------------------------------------------------------------------
TOKEN_RE = re.compile(
    r"\s*(?:(0[xX][0-9a-fA-F_]+|0[bB][01_]+|[0-9][0-9_]*)|([A-Za-z_][A-Za-z0-9_]*)|(<<|>>|[-+*/%&|^~()]))")


def eval_expr(text, symbols):
    """Вычисляет целочисленное выражение. Неизвестный символ -> UndefinedSymbol."""
    text = text.strip()
    if not text:
        raise AsmError("пустое выражение")
    tokens, pos = [], 0
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise AsmError("недопустимый символ в выражении: %r" % text[pos:].strip()[:10])
        pos = m.end()
        if m.group(1) is not None:
            s = m.group(1).replace("_", "")
            tokens.append(("num", int(s, 0) if s[:2].lower() in ("0x", "0b") else int(s, 10)))
        elif m.group(2) is not None:
            tokens.append(("id", m.group(2)))
        else:
            tokens.append(("op", m.group(3)))
    st = {"i": 0}

    def peek():
        return tokens[st["i"]] if st["i"] < len(tokens) else (None, None)

    def take():
        t = peek()
        st["i"] += 1
        return t

    def level(next_level, ops):
        def f():
            v = next_level()
            while peek()[0] == "op" and peek()[1] in ops:
                op = take()[1]
                r = next_level()
                v = apply(op, v, r)
            return v
        return f

    def apply(op, a, b):
        if op == "|": return a | b
        if op == "^": return a ^ b
        if op == "&": return a & b
        if op == "<<": return a << b
        if op == ">>": return a >> b
        if op == "+": return a + b
        if op == "-": return a - b
        if op == "*": return a * b
        if op in ("/", "%"):
            if b == 0:
                raise AsmError("деление на ноль в выражении")
            return a // b if op == "/" else a % b
        raise AsmError("неизвестная операция " + op)

    def primary():
        kind, val = take()
        if kind == "num":
            return val
        if kind == "id":
            if val.lower() in ("lo", "hi"):
                if take() != ("op", "("):
                    raise AsmError("после %s ожидалась '('" % val)
                inner = or_()
                if take() != ("op", ")"):
                    raise AsmError("не хватает ')' после аргумента %s" % val)
                return (inner & 0xFF) if val.lower() == "lo" else ((inner >> 8) & 0xFF)
            if val in symbols:
                return symbols[val]
            raise UndefinedSymbol("неизвестный символ '%s'" % val)
        if (kind, val) == ("op", "("):
            v = or_()
            if take() != ("op", ")"):
                raise AsmError("не хватает ')'")
            return v
        raise AsmError("неожиданный конец выражения или лишний символ")

    def unary():
        if peek() == ("op", "-"):
            take(); return -unary()
        if peek() == ("op", "+"):
            take(); return unary()
        if peek() == ("op", "~"):
            take(); return ~unary()
        return primary()

    mul = level(unary, ("*", "/", "%"))
    add = level(mul, ("+", "-"))
    shift = level(add, ("<<", ">>"))
    and_ = level(shift, ("&",))
    xor = level(and_, ("^",))
    or_ = level(xor, ("|",))
    value = or_()
    if st["i"] != len(tokens):
        raise AsmError("лишние символы в выражении: %r" % (tokens[st["i"]][1],))
    return value


# ---------------------------------------------------------------------------
# Разбор строк
# ---------------------------------------------------------------------------
LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:")
MEM_RE = re.compile(r"^\[\s*([A-Za-z0-9_]+)\s*(?:([+-])\s*(.+?))?\s*\]$")


def strip_comment(line):
    """Удаляет комментарий (от ';' или '//' до конца строки)."""
    cut = len(line)
    for marker in (";", "//"):
        i = line.find(marker)
        if i != -1:
            cut = min(cut, i)
    return line[:cut].strip()


def split_operands(s):
    """Делит строку операндов по запятым вне скобок."""
    if not s.strip():
        return []
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        else:
            cur += ch
    out.append(cur.strip())
    return out


class Stmt:
    """Одна исходная конструкция: команда или директива данных."""
    def __init__(self, line_no, raw, section, addr, kind, name, ops, size):
        self.line_no, self.raw, self.section = line_no, raw, section
        self.addr, self.kind, self.name, self.ops, self.size = addr, kind, name, ops, size


class Assembler:
    def __init__(self):
        self.symbols = {}
        self.stmts = []
        self.out = {"text": {}, "data": {}}   # section -> {addr: (word, kind, comment)}

    # ---- общие вспомогательные функции -----------------------------------
    @staticmethod
    def fail(msg, stmt_or_no, raw=None):
        if isinstance(stmt_or_no, Stmt):
            raise AsmError(msg, stmt_or_no.line_no, stmt_or_no.raw)
        raise AsmError(msg, stmt_or_no, raw)

    def define(self, name, value, line_no, raw):
        if name.upper() in MNEMONICS or name.upper() in REGISTERS:
            self.fail("имя '%s' зарезервировано (команда или регистр)" % name, line_no, raw)
        if name in self.symbols:
            self.fail("символ '%s' уже определён" % name, line_no, raw)
        self.symbols[name] = value

    # ---- проход 1 ----------------------------------------------------------
    def pass1(self, lines):
        section, loc = "text", {"text": 0, "data": 0}
        for no, raw in enumerate(lines, 1):
            code = strip_comment(raw)
            if not code:
                continue
            while True:                       # метки (допускается несколько)
                m = LABEL_RE.match(code)
                if not m:
                    break
                self.define(m.group(1), loc[section], no, raw)
                code = code[m.end():].strip()
            if not code:
                continue
            parts = re.split(r"\s+", code, maxsplit=1)
            head, rest = parts[0], (parts[1] if len(parts) > 1 else "")
            ops = split_operands(rest)

            if head.startswith("."):
                d = head.lower()
                if d not in DIRECTIVES:
                    self.fail("неизвестная директива '%s'" % head, no, raw)
                if d == ".text":
                    section = "text"
                elif d == ".data":
                    section = "data"
                elif d == ".org":
                    if len(ops) != 1:
                        self.fail(".org принимает один операнд", no, raw)
                    try:
                        loc[section] = eval_expr(ops[0], self.symbols)
                    except AsmError as e:
                        self.fail(".org: " + e.msg, no, raw)
                elif d == ".equ":
                    if len(ops) != 2 or not re.match(r"^[A-Za-z_]\w*$", ops[0]):
                        self.fail("формат: .equ ИМЯ, выражение", no, raw)
                    try:
                        value = eval_expr(ops[1], self.symbols)
                    except AsmError as e:
                        self.fail(".equ: " + e.msg + " (символ должен быть определён выше)", no, raw)
                    self.define(ops[0], value, no, raw)
                elif d == ".word":
                    if not ops:
                        self.fail(".word требует хотя бы одно значение", no, raw)
                    st = Stmt(no, raw, section, loc[section], "word", ".word", ops, len(ops))
                    self.stmts.append(st); loc[section] += len(ops)
                elif d == ".space":
                    if len(ops) != 1:
                        self.fail(".space принимает один операнд", no, raw)
                    try:
                        n = eval_expr(ops[0], self.symbols)
                    except AsmError as e:
                        self.fail(".space: " + e.msg, no, raw)
                    if n < 0:
                        self.fail(".space: отрицательный размер", no, raw)
                    st = Stmt(no, raw, section, loc[section], "space", ".space", [str(n)], n)
                    self.stmts.append(st); loc[section] += n
                continue

            mnem = head.upper()
            if mnem not in MNEMONICS:
                self.fail("неизвестная команда '%s'" % head, no, raw)
            if section != "text":
                self.fail("команды допускаются только в секции .text", no, raw)
            size = 1
            if mnem == "CALL":
                size = 3
            elif mnem == "LI":
                size = 2
                if len(ops) == 2:
                    try:
                        v = eval_expr(ops[1], self.symbols)
                        if 0 <= v <= 255:
                            size = 1          # значение известно и умещается в LDI
                    except AsmError:
                        pass                  # метка "вперёд" -> 2 слова
            st = Stmt(no, raw, section, loc[section], "instr", mnem, ops, size)
            self.stmts.append(st); loc[section] += size

    # ---- кодирование отдельных операндов ----------------------------------
    def reg(self, text, st):
        r = REGISTERS.get(text.strip().upper())
        if r is None:
            self.fail("ожидался регистр R0-R7, получено '%s'" % text, st)
        return r

    def val(self, text, st):
        try:
            return eval_expr(text, self.symbols)
        except AsmError as e:
            self.fail(e.msg, st)

    def mem(self, text, st):
        m = MEM_RE.match(text.strip())
        if not m:
            self.fail("ожидался операнд памяти вида [Rs], [Rs+imm] или [Rs-imm], получено '%s'" % text, st)
        base = self.reg(m.group(1), st)
        imm = 0
        if m.group(3) is not None:
            imm = self.val(m.group(3), st)
            if m.group(2) == "-":
                imm = -imm
        return base, imm

    def imm5(self, v, st):
        if not -16 <= v <= 15:
            self.fail("смещение/константа %d вне диапазона -16..15 (imm5)" % v, st)
        return v & 0x1F

    def imm8(self, v, st):
        if not 0 <= v <= 255:
            self.fail("константа %d вне диапазона 0..255 (imm8)" % v, st)
        return v

    @staticmethod
    def r_word(op, rd, rs, rt):
        return (op << 11) | (rd << 8) | (rs << 5) | (rt << 2)

    @staticmethod
    def i_word(op, rd, rs, imm5):
        return (op << 11) | (rd << 8) | (rs << 5) | (imm5 & 0x1F)

    @staticmethod
    def l_word(op, rd, imm8):
        return (op << 11) | (rd << 8) | (imm8 & 0xFF)

    @staticmethod
    def j_word(op, field):
        return (op << 11) | (field & 0x7FF)

    def target(self, text, st):
        t = self.val(text, st)
        if not 0 <= t < ROM_WORDS:
            self.fail("адрес перехода %d вне памяти команд (0..%d)" % (t, ROM_WORDS - 1), st)
        return t

    # ---- проход 2: кодирование --------------------------------------------
    def encode(self, st):
        """Возвращает список (слово, вид) для команды/директивы."""
        n, ops, m = len(st.ops), st.ops, st.name

        def need(k):
            if n != k:
                self.fail("%s: ожидалось операндов: %d, получено: %d" % (m, k, n), st)

        if st.kind == "word":
            res = []
            for o in ops:
                v = self.val(o, st)
                if not -32768 <= v <= 65535:
                    self.fail(".word: значение %d не помещается в 16 бит" % v, st)
                res.append((v & 0xFFFF, "D"))
            return res
        if st.kind == "space":
            return [(0, "D")] * st.size

        if m in OPS_R3:
            need(3)
            return [(self.r_word(OPS_R3[m], self.reg(ops[0], st), self.reg(ops[1], st), self.reg(ops[2], st)), "R")]
        if m in OPS_R2:
            need(2)
            return [(self.r_word(OPS_R2[m], self.reg(ops[0], st), self.reg(ops[1], st), 0), "R")]
        if m == "CMP":
            need(2)
            return [(self.r_word(OP_CMP, 0, self.reg(ops[0], st), self.reg(ops[1], st)), "R")]
        if m == "JR":
            need(1)
            return [(self.r_word(OP_JR, 0, self.reg(ops[0], st), 0), "R")]
        if m == "ADDI":
            need(3)
            return [(self.i_word(OP_ADDI, self.reg(ops[0], st), self.reg(ops[1], st),
                                 self.imm5(self.val(ops[2], st), st)), "I")]
        if m in ("LDI", "LHI"):
            need(2)
            return [(self.l_word(OP_LDI if m == "LDI" else OP_LHI, self.reg(ops[0], st),
                                 self.imm8(self.val(ops[1], st), st)), "L")]
        if m in ("LOAD", "STORE"):
            need(2)
            base, imm = self.mem(ops[1], st)
            return [(self.i_word(OP_LOAD if m == "LOAD" else OP_STORE, self.reg(ops[0], st), base,
                                 self.imm5(imm, st)), "I")]
        if m == "JUMP":
            need(1)
            return [(self.j_word(OP_JUMP, self.target(ops[0], st)), "J")]
        if m in BRANCHES:
            need(1)
            off = self.target(ops[0], st) - (st.addr + 1)
            if not -1024 <= off <= 1023:
                self.fail("цель ветвления слишком далеко (смещение %d, допустимо -1024..1023)" % off, st)
            return [(self.j_word(BRANCHES[m], off), "J")]
        if m == "HLT":
            need(0)
            return [(self.j_word(OP_HLT, 0), "J")]
        # ---- псевдокоманды ----
        if m == "NOP":
            need(0)
            return [(0x0000, "R")]                               # ADD R0, R0, R0
        if m == "MOV":
            need(2)                                              # MOV rd, rs -> ADD rd, rs, R0
            return [(self.r_word(OPS_R3["ADD"], self.reg(ops[0], st), self.reg(ops[1], st), 0), "R")]
        if m == "RET":
            need(0)                                              # RET -> JR R7
            return [(self.r_word(OP_JR, 0, 7, 0), "R")]
        if m == "LI":
            need(2)
            rd, v = self.reg(ops[0], st), self.val(ops[1], st)
            if not -32768 <= v <= 65535:
                self.fail("LI: значение %d не помещается в 16 бит" % v, st)
            v &= 0xFFFF
            if st.size == 1:
                return [(self.l_word(OP_LDI, rd, self.imm8(v, st)), "L")]
            return [(self.l_word(OP_LDI, rd, v & 0xFF), "L"), (self.l_word(OP_LHI, rd, v >> 8), "L")]
        if m == "CALL":
            need(1)                                              # CALL f -> LDI R7,lo(ret); LHI R7,hi(ret); JUMP f
            ret = st.addr + 3
            return [(self.l_word(OP_LDI, 7, ret & 0xFF), "L"),
                    (self.l_word(OP_LHI, 7, (ret >> 8) & 0xFF), "L"),
                    (self.j_word(OP_JUMP, self.target(ops[0], st)), "J")]
        self.fail("внутренняя ошибка: команда '%s' не обработана" % m, st)

    def pass2(self):
        limits = {"text": ROM_WORDS, "data": RAM_WORDS}
        for st in self.stmts:
            words = self.encode(st)
            if len(words) != st.size:
                self.fail("внутренняя ошибка: размер %s изменился между проходами" % st.name, st)
            src = re.sub(r"\s+", " ", strip_comment(st.raw))
            for k, (w, kind) in enumerate(words):
                a = st.addr + k
                if not 0 <= a < limits[st.section]:
                    self.fail("адрес 0x%X выходит за пределы памяти (%s: 0..0x%X)" %
                              (a, "ROM" if st.section == "text" else "RAM", limits[st.section] - 1), st)
                if a in self.out[st.section]:
                    self.fail("адрес 0x%X уже занят (пересечение секций/директив .org)" % a, st)
                note = src if k == 0 else "%s  [+%d]" % (src, k)
                self.out[st.section][a] = (w, kind, note)

    def assemble(self, text):
        self.pass1(text.splitlines())
        self.pass2()


# ---------------------------------------------------------------------------
# Вывод результатов
# ---------------------------------------------------------------------------
def word_bin(w, kind):
    """Двоичная запись слова с разбивкой на поля (подчёркивания допустимы в $readmemb)."""
    b = lambda v, n: format(v, "0%db" % n)
    if kind == "R":
        return "_".join([b(w >> 11, 5), b((w >> 8) & 7, 3), b((w >> 5) & 7, 3), b((w >> 2) & 7, 3), b(w & 3, 2)])
    if kind == "I":
        return "_".join([b(w >> 11, 5), b((w >> 8) & 7, 3), b((w >> 5) & 7, 3), b(w & 31, 5)])
    if kind == "L":
        return "_".join([b(w >> 11, 5), b((w >> 8) & 7, 3), b(w & 255, 8)])
    if kind == "J":
        return "_".join([b(w >> 11, 5), b(w & 0x7FF, 11)])
    return b(w, 16)


def write_mem(path, words, hexfmt, title):
    """Пишет образ памяти для $readmemb / $readmemh (адреса через @hex при разрывах)."""
    lines = ["// " + title,
             "// Формат: %s, одно 16-битное слово в строке; '@A' - смена адреса (hex)" %
             ("hex ($readmemh)" if hexfmt else "двоичный ($readmemb)")]
    prev = None
    for a in sorted(words):
        w, kind, note = words[a]
        if prev is None and a != 0 or prev is not None and a != prev + 1:
            lines.append("@%X" % a)
        val = "%04X" % w if hexfmt else word_bin(w, kind)
        lines.append("%-20s // %03X: %s" % (val, a, note))
        prev = a
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def write_listing(path, asm):
    lines = ["Адрес  Слово  Двоично             Исходная строка", "-" * 70]
    for section, name in (("text", "ROM (память команд)"), ("data", "RAM (память данных)")):
        if not asm.out[section]:
            continue
        lines.append("== %s ==" % name)
        for a in sorted(asm.out[section]):
            w, kind, note = asm.out[section][a]
            lines.append("%03X    %04X   %-20s %s" % (a, w, word_bin(w, kind), note))
    lines += ["", "Таблица символов:"]
    for s in sorted(asm.symbols, key=lambda k: (asm.symbols[k], k)):
        lines.append("  %-16s = %d (0x%X)" % (s, asm.symbols[s], asm.symbols[s] & 0xFFFF))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Ассемблер для процессора курсового проекта")
    ap.add_argument("source", help="исходный файл .asm")
    ap.add_argument("--rom", help="выходной образ ROM (по умолчанию <имя>.rom.mem)")
    ap.add_argument("--ram", help="выходной образ RAM (по умолчанию <имя>.ram.mem)")
    ap.add_argument("--list", help="файл листинга (по умолчанию <имя>.lst)")
    ap.add_argument("--hex", action="store_true", help="выводить hex вместо двоичных слов ($readmemh)")
    args = ap.parse_args(argv)

    base = os.path.splitext(args.source)[0]
    rom_path = args.rom or base + ".rom.mem"
    ram_path = args.ram or base + ".ram.mem"
    lst_path = args.list or base + ".lst"

    with open(args.source, encoding="utf-8") as f:
        text = f.read()
    asm = Assembler()
    try:
        asm.assemble(text)
    except AsmError as e:
        where = "%s:%s" % (args.source, e.line_no) if e.line_no else args.source
        sys.stderr.write("%s: ошибка: %s\n" % (where, e.msg))
        if e.text:
            sys.stderr.write("    %s\n" % e.text.strip())
        return 1

    write_mem(rom_path, asm.out["text"], args.hex, "ROM: %s" % os.path.basename(args.source))
    print("ROM: %d слов -> %s" % (len(asm.out["text"]), rom_path))
    if asm.out["data"]:
        write_mem(ram_path, asm.out["data"], args.hex, "RAM: %s" % os.path.basename(args.source))
        print("RAM: %d слов -> %s" % (len(asm.out["data"]), ram_path))
    write_listing(lst_path, asm)
    print("Листинг -> %s (символов: %d)" % (lst_path, len(asm.symbols)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
