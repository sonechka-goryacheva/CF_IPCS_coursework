#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
models.py - эталонные модели прошивок на Python (написаны по спецификации, на обычных
целых числах Python; не используют код прошивки). Используются в стресс-тесте.

  calc_run(keys)    -> список значений SEG: начальное и после каждой клавиши
  vending_run(keys) -> список пар (LED, SEG): начальное и после каждой клавиши
Коды клавиш: 0-9 цифры, 10 '+', 11 '-', 12 '*', 13 '/', 14 '=', 15 'C' / отмена.
"""

PRICE = 7


def bcd(n):
    return ((n // 1000) % 10) << 12 | ((n // 100) % 10) << 8 | ((n // 10) % 10) << 4 | (n % 10)


def seg_signed(a):
    """Вид индикаторов: ведущие нули погашены (F), минус (A) вплотную к числу."""
    if a >= 0:
        v = bcd(a)
        if a < 10:
            v |= 0xFFF0
        elif a < 100:
            v |= 0xFF00
        elif a < 1000:
            v |= 0xF000
        return v
    m = -a
    v = bcd(m)
    if m < 10:
        return v | 0xFFA0
    if m < 100:
        return v | 0xFA00
    return v | 0xA000


SEG_ERR = 0xFFFE


def _calc(a, op, x):
    if op == 1:
        r = a + x
    elif op == 2:
        r = a - x
    elif op == 3:
        r = a * x
    else:
        if x == 0:
            return None
        q = abs(a) // x
        r = q if a >= 0 else -q          # остаток отбрасывается к нулю
    return None if (r > 9999 or r < -999) else r


class Calc:
    def __init__(self):
        self.reset()

    def reset(self):
        self.a = 0; self.x = 0; self.op = 0
        self.ent = False; self.err = False
        self.disp = seg_signed(0)

    def key(self, k):
        if k == 15:
            self.reset(); return self.disp
        if self.err:
            return self.disp
        if k < 10:
            if self.ent:
                if self.x < 1000:
                    self.x = self.x * 10 + k
            else:
                self.x = k; self.ent = True
            self.disp = seg_signed(self.x)
        elif k == 14:
            if self.op and self.ent:
                r = _calc(self.a, self.op, self.x)
                if r is None:
                    self.err = True; self.disp = SEG_ERR
                else:
                    self.a = r; self.op = 0; self.ent = False; self.disp = seg_signed(r)
        else:
            new = k - 9
            if self.op == 0:
                if self.ent:
                    self.a = self.x
                self.op = new; self.ent = False; self.disp = seg_signed(self.a)
            elif self.ent:
                r = _calc(self.a, self.op, self.x)
                if r is None:
                    self.err = True; self.disp = SEG_ERR
                else:
                    self.a = r; self.op = new; self.ent = False; self.disp = seg_signed(r)
            else:
                self.op = new; self.disp = seg_signed(self.a)
        return self.disp


def calc_run(keys):
    c = Calc()
    out = [c.disp]
    for k in keys:
        out.append(c.key(k))
    return out


def vending_run(keys):
    bal, done, led, seg = 0, False, 0, seg_signed(0)
    out = [(led, seg)]
    for k in keys:
        if done:                                   # после покупки/возврата нажатие только сбрасывает
            bal, done, led, seg = 0, False, 0, seg_signed(0)
        elif k in (1, 2, 5):
            bal += k
            seg = seg_signed(bal)
            if bal >= PRICE:
                change = bal - PRICE
                led = 1 | (2 if change else 0)
                seg = seg_signed(change)
                done = True
        elif k == 15 and bal > 0:
            led = 2; seg = seg_signed(bal); done = True
        out.append((led, seg))
    return out
