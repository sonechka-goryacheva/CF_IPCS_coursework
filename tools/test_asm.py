#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_asm.py - модульные тесты ассемблера.
Запуск: python3 tools/test_asm.py   (или make test-asm)
Эталонные слова взяты из docs/ISA.md (раздел "Примеры кодирования") и посчитаны вручную.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asm as A   # noqa: E402


def rom(source):
    """Ассемблирует текст, возвращает список слов ROM по порядку адресов."""
    a = A.Assembler()
    a.assemble(source)
    return [a.out["text"][k][0] for k in sorted(a.out["text"])]


def ram(source):
    a = A.Assembler()
    a.assemble(source)
    return [a.out["data"][k][0] for k in sorted(a.out["data"])]


class TestEncoding(unittest.TestCase):
    """Примеры из ISA.md, п. 7."""

    def test_isa_examples(self):
        self.assertEqual(rom("ADD R1, R2, R3"), [0x014C])
        self.assertEqual(rom("LDI R1, 5"), [0x5905])
        self.assertEqual(rom("LOAD R1, [R2+3]"), [0x6943])
        self.assertEqual(rom("STORE R3, [R6+3]"), [0x73C3])
        self.assertEqual(rom(".org 0\nJUMP 0x010"), [0x7810])
        self.assertEqual(rom("JR R7"), [0xA8E0])

    def test_branch_backward_and_forward(self):
        # BNE по адресу 14 на адрес 1: смещение = 1 - (14 + 1) = -14
        src = "\n".join(["NOP"] * 14 + ["BNE 1"])
        self.assertEqual(rom(src)[14], (0x11 << 11) | ((1 - 15) & 0x7FF))
        # BNE -3 из ISA.md: команда по адресу 3, цель 1
        self.assertEqual(rom(".org 3\nBNE 1"), [0x8FFD])
        # ветвление вперёд на метку
        self.assertEqual(rom("BEQ end\nNOP\nend: HLT")[0], (0x10 << 11) | 1)

    def test_all_simple_mnemonics(self):
        self.assertEqual(rom("SUB R1, R2, R3"), [(0x01 << 11) | (1 << 8) | (2 << 5) | (3 << 2)])
        self.assertEqual(rom("AND R1, R2, R3"), [(0x02 << 11) | (1 << 8) | (2 << 5) | (3 << 2)])
        self.assertEqual(rom("OR R1, R2, R3"), [(0x03 << 11) | (1 << 8) | (2 << 5) | (3 << 2)])
        self.assertEqual(rom("XOR R1, R2, R3"), [(0x04 << 11) | (1 << 8) | (2 << 5) | (3 << 2)])
        self.assertEqual(rom("NOT R1, R2"), [(0x05 << 11) | (1 << 8) | (2 << 5)])
        self.assertEqual(rom("SHL R1, R2"), [(0x06 << 11) | (1 << 8) | (2 << 5)])
        self.assertEqual(rom("SHR R1, R2"), [(0x07 << 11) | (1 << 8) | (2 << 5)])
        self.assertEqual(rom("CMP R2, R1"), [0x4044])
        self.assertEqual(rom("BIN2BCD R2, R1"), [(0x09 << 11) | (2 << 8) | (1 << 5)])
        self.assertEqual(rom("ADDI R1, R1, -1"), [0x513F])
        self.assertEqual(rom("LHI R6, 0xFF"), [(0x0C << 11) | (6 << 8) | 0xFF])
        self.assertEqual(rom("HLT"), [0xA000])

    def test_case_insensitive_and_comments(self):
        self.assertEqual(rom("  add r1, r2, r3   ; комментарий\n// ещё комментарий"), [0x014C])

    def test_memory_operand_forms(self):
        self.assertEqual(rom("LOAD R1, [R2]"), rom("LOAD R1, [R2+0]"))
        self.assertEqual(rom("LOAD R1, [R2-1]"), rom("LOAD R1, [R2+-1]"))
        self.assertEqual(rom("LOAD R1, [ R2 + 3 ]"), [0x6943])


class TestPseudo(unittest.TestCase):
    def test_nop_mov_ret(self):
        self.assertEqual(rom("NOP"), [0x0000])
        self.assertEqual(rom("MOV R1, R2"), rom("ADD R1, R2, R0"))
        self.assertEqual(rom("RET"), rom("JR R7"))

    def test_call_expansion(self):
        # CALL по адресу 0: возврат на адрес 3
        w = rom("CALL f\nNOP\nNOP\nf: HLT")
        self.assertEqual(w[0], (0x0B << 11) | (7 << 8) | 3)          # LDI R7, lo(3)
        self.assertEqual(w[1], (0x0C << 11) | (7 << 8) | 0)          # LHI R7, hi(3)
        self.assertEqual(w[2], (0x0F << 11) | 5)                     # JUMP f (f = 5)

    def test_call_high_return_address(self):
        w = rom(".org 0x2FE\nCALL f\nf: HLT")
        self.assertEqual(w[0], (0x0B << 11) | (7 << 8) | 0x01)       # lo(0x301)
        self.assertEqual(w[1], (0x0C << 11) | (7 << 8) | 0x03)       # hi(0x301)

    def test_li_sizes(self):
        self.assertEqual(len(rom("LI R1, 200")), 1)                  # умещается в LDI
        self.assertEqual(rom("LI R1, 1000"), [(0x0B << 11) | (1 << 8) | 0xE8, (0x0C << 11) | (1 << 8) | 0x03])
        self.assertEqual(len(rom("LI R1, later\nlater: HLT")), 3)    # метка "вперёд" -> 2 слова
        self.assertEqual(rom("LI R1, -1"), [(0x0B << 11) | (1 << 8) | 0xFF, (0x0C << 11) | (1 << 8) | 0xFF])


class TestExpressions(unittest.TestCase):
    def test_arithmetic(self):
        e = lambda t, s=None: A.eval_expr(t, s or {})
        self.assertEqual(e("1 + 2 * 3"), 7)
        self.assertEqual(e("(1 + 2) * 3"), 9)
        self.assertEqual(e("0x10 | 0b11"), 19)
        self.assertEqual(e("1 << 4 + 1"), 32)
        self.assertEqual(e("~0 & 0xFF"), 255)
        self.assertEqual(e("-5 + 2"), -3)
        self.assertEqual(e("7 % 4 + 9 / 2"), 7)
        self.assertEqual(e("lo(0x1234)"), 0x34)
        self.assertEqual(e("hi(0x1234)"), 0x12)
        self.assertEqual(e("X + 1", {"X": 41}), 42)

    def test_equ_and_labels_in_operands(self):
        self.assertEqual(rom(".equ K, 3\nLOAD R1, [R2+K]"), [0x6943])
        self.assertEqual(rom(".equ A, 2\n.equ B, A*2\nLDI R1, B+1"), rom("LDI R1, 5"))


class TestDirectives(unittest.TestCase):
    def test_data_section(self):
        self.assertEqual(ram(".data\n.word 1, 0xFF, -1, 65535"), [1, 255, 0xFFFF, 0xFFFF])
        self.assertEqual(ram(".data\n.space 3\n.word 7"), [0, 0, 0, 7])

    def test_data_label_addresses(self):
        a = A.Assembler()
        a.assemble(".data\nx: .word 1\ny: .word 2, 3\n.text\nLDI R1, y")
        self.assertEqual(a.symbols["y"], 1)
        self.assertEqual(a.out["text"][0][0], (0x0B << 11) | (1 << 8) | 1)

    def test_org_leaves_gap(self):
        a = A.Assembler()
        a.assemble("NOP\n.org 0x10\nHLT")
        self.assertEqual(sorted(a.out["text"]), [0, 0x10])

    def test_multiple_labels_one_line(self):
        a = A.Assembler()
        a.assemble("a: b: NOP\nc:\nHLT")
        self.assertEqual((a.symbols["a"], a.symbols["b"], a.symbols["c"]), (0, 0, 1))


class TestErrors(unittest.TestCase):
    def check(self, source, fragment):
        with self.assertRaises(A.AsmError) as cm:
            rom(source)
        self.assertIn(fragment, cm.exception.msg)
        return cm.exception

    def test_unknown_mnemonic(self):
        self.check("FOO R1", "неизвестная команда")

    def test_bad_register(self):
        self.check("ADD R1, R2, R8", "регистр")

    def test_operand_count(self):
        self.check("ADD R1, R2", "операндов")

    def test_imm_ranges(self):
        self.check("LDI R1, 256", "imm8")
        self.check("LDI R1, -1", "imm8")
        self.check("ADDI R1, R1, 16", "imm5")
        self.check("ADDI R1, R1, -17", "imm5")
        self.check("LOAD R1, [R2+16]", "imm5")

    def test_undefined_symbol(self):
        self.check("JUMP nowhere", "nowhere")

    def test_duplicate_label(self):
        self.check("a: NOP\na: NOP", "уже определён")

    def test_reserved_label(self):
        self.check("add: NOP", "зарезервировано")

    def test_branch_too_far(self):
        self.check("BEQ far\n.org 0x600\nfar: HLT", "слишком далеко")

    def test_rom_overflow(self):
        self.check(".org 0x7FF\nNOP\nNOP", "за пределы")

    def test_overlap(self):
        self.check("NOP\n.org 0\nHLT", "уже занят")

    def test_instruction_in_data(self):
        self.check(".data\nNOP", ".text")

    def test_line_number_reported(self):
        e = self.check("NOP\nNOP\nBAD R1", "неизвестная команда")
        self.assertEqual(e.line_no, 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
