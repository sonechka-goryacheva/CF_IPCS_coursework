#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
memcmp.py - сравнение двух файлов образа памяти ($readmemb/$readmemh) по содержимому.
Комментарии (// и /* */), символы '_' и разбивка на строки не учитываются;
поддерживаются метки адреса '@hex'.

Использование:
    python3 tools/memcmp.py эталон.mem проверяемый.mem [--hex]
Код возврата: 0 - содержимое совпадает, 1 - есть отличия.
"""
import argparse
import re
import sys


def load(path, base):
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    mem, addr = {}, 0
    for tok in text.split():
        if tok.startswith("@"):
            addr = int(tok[1:], 16)
        else:
            mem[addr] = int(tok.replace("_", ""), base)
            addr += 1
    return mem


def main(argv=None):
    ap = argparse.ArgumentParser(description="Сравнение образов памяти")
    ap.add_argument("reference")
    ap.add_argument("candidate")
    ap.add_argument("--hex", action="store_true", help="файлы в шестнадцатеричном формате")
    args = ap.parse_args(argv)
    base = 16 if args.hex else 2
    a, b = load(args.reference, base), load(args.candidate, base)
    diffs = [(k, a.get(k), b.get(k)) for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]
    if not diffs:
        print("СОВПАДАЕТ: %d слов, %s == %s" % (len(a), args.reference, args.candidate))
        return 0
    print("ОТЛИЧАЕТСЯ: %d различий (слов: %d и %d)" % (len(diffs), len(a), len(b)))
    for k, x, y in diffs[:20]:
        fx = "-" if x is None else "%04X" % x
        fy = "-" if y is None else "%04X" % y
        print("  адрес %03X: эталон %s, получено %s" % (k, fx, fy))
    return 1


if __name__ == "__main__":
    sys.exit(main())
