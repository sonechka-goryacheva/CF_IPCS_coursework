#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
stress.py - стресс-тест интерактивного моста: длинная серия случайных нажатий проходит
через тот же путь, что и живая игра (VPI-модуль vpi/kbd.c читает "клавиши" из stdin),
затем итоговое состояние индикаторов сравнивается с эталонной моделью (tools/models.py).
Дополнительно сравнивается пиковая память процесса симулятора на коротком и длинном
прогоне (рост памяти = утечка).

Использование: python3 tools/stress.py calc|vending [число_клавиш] [seed]
Перед запуском нужны sim/play_calc.vvp (или play_vending.vvp) и vpi/kbd.vpi (make stress делает это сам).
"""
import os
import random
import re
import resource
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import models  # noqa: E402

CHARS = {10: '+', 11: '-', 12: '*', 13: '/', 14: '=', 15: 'c'}


def to_chars(keys):
    return ''.join(str(k) if k < 10 else CHARS[k] for k in keys)


def gen_calc(rng, n):
    keys = []
    for _ in range(n):
        r = rng.random()
        if r < 0.50:
            keys.append(rng.randrange(10))
        elif r < 0.80:
            keys.append(rng.randrange(10, 14))
        elif r < 0.93:
            keys.append(14)
        else:
            keys.append(15)
    return keys


def gen_vending(rng, n):
    return [rng.choice([1, 2, 5, 1, 2, 5, 15, 0, 3, 9, 14]) for _ in range(n)]


def run_sim(kind, keys):
    vvp = 'sim/play_%s.vvp' % kind
    t0 = time.time()
    p = subprocess.run(['vvp', '-M', 'vpi', '-mkbd', vvp, '+nodraw', '+fast'],
                       input=(to_chars(keys) + 'q').encode(), capture_output=True, timeout=900)
    out = p.stdout.decode('utf-8', 'replace')
    m = re.search(r'FINAL seg=([0-9a-fA-F]+) led=([0-9a-fA-F]+)', out)
    if not m:
        raise SystemExit('Симулятор не вывел итоговое состояние:\n' + out[-500:])
    return int(m.group(1), 16), int(m.group(2), 16), time.time() - t0


def rss_mb():
    r = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return r / (1024 * 1024) if sys.platform == 'darwin' else r / 1024


def checkpoint(keys, p):
    """Сдвигает контрольную точку так, чтобы перед ней не было сброса (иначе состояние тривиально)."""
    while p > 6 and 15 in keys[p - 6:p]:
        p -= 1
    return p


def main():
    kind = sys.argv[1] if len(sys.argv) > 1 else 'calc'
    n = int(sys.argv[2]) if len(sys.argv) > 2 else (2000 if kind == 'calc' else 1000)
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    if kind not in ('calc', 'vending'):
        raise SystemExit('Использование: stress.py calc|vending [клавиш] [seed]')
    rng = random.Random(seed)
    gen = gen_calc if kind == 'calc' else gen_vending
    model = models.calc_run if kind == 'calc' else models.vending_run
    keys = gen(rng, n)
    bad = 0
    mem = []
    # короткий прогон (память), затем контрольные точки на 25%, 50%, 75% и 100% длинной серии
    plan = [('короткий', max(50, n // 8))] + [('точка %d%%' % pct, checkpoint(keys, n * pct // 100)) for pct in (25, 50, 75, 100)]
    for label, count in plan:
        seg, led, dt = run_sim(kind, keys[:count])
        exp = model(keys[:count])[-1]
        exp_led, exp_seg = (0, exp) if kind == 'calc' else exp
        ok = (seg == exp_seg and led == exp_led)
        bad += 0 if ok else 1
        mem.append(rss_mb())
        print('%-10s %5d клавиш за %4.1f с: SEG=%04X LED=%04X (эталон SEG=%04X LED=%04X) -> %s'
              % (label, count, dt, seg, led, exp_seg, exp_led, 'совпало' if ok else 'РАСХОЖДЕНИЕ'))
    print('Пиковая память симулятора: %.1f МБ после короткого, %.1f МБ после самого длинного прогона' % (mem[0], mem[-1]))
    leak = mem[-1] - mem[0] > max(5.0, 0.2 * mem[0])
    print('Рост памяти:', 'ЕСТЬ (возможна утечка)' if leak else 'нет')
    if bad or leak:
        print('STRESS FAILED')
        return 1
    print('STRESS PASSED: состояние симулятора совпадает с эталоном во всех контрольных точках, память не растёт')
    return 0


if __name__ == '__main__':
    sys.exit(main())
