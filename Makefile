RTL = rtl/*.v

sim/sort.vvp: $(RTL) tb/tb_sort.v sw/sort_rom.mem sw/sort_data.mem
	@mkdir -p sim
	iverilog -g2005 -Wall -o sim/sort.vvp $(RTL) tb/tb_sort.v

# Запуск теста сортировки (результат в консоль и в sim/sort.log)
sort: sim/sort.vvp
	vvp sim/sort.vvp | tee sim/sort.log

# То же с трассировкой каждой команды (sim/sort_trace.log)
sort-trace: sim/sort.vvp
	vvp sim/sort.vvp +trace | tee sim/sort_trace.log

# Полный перебор BIN2BCD (65536 входов)
bcd:
	@mkdir -p sim
	iverilog -g2005 -o sim/bcd.vvp rtl/BIN2BCD.v tb/tb_bin2bcd.v
	vvp sim/bcd.vvp | tee sim/bcd.log

# ---- этап 3: ассемблер ----
# Ассемблировать sw/sort.asm -> sw/sort.rom.mem, sw/sort.ram.mem, sw/sort.lst
asm-sort:
	python3 tools/asm.py sw/sort.asm

# Сравнить результат ассемблера с машинным кодом, написанным вручную (этап 2)
cmp-sort: asm-sort
	python3 tools/memcmp.py sw/sort_rom.mem sw/sort.rom.mem
	python3 tools/memcmp.py sw/sort_data.mem sw/sort.ram.mem

# Выполнить на процессоре программу, полученную из ассемблера
sort-asm: asm-sort
	@mkdir -p sim
	iverilog -g2005 -Wall -DROM_FILE=\"sw/sort.rom.mem\" -DRAM_FILE=\"sw/sort.ram.mem\" -DVCD_FILE=\"sim/tb_sort_asm.vcd\" -o sim/sort_asm.vvp $(RTL) tb/tb_sort.v
	vvp sim/sort_asm.vvp | tee sim/sort_asm.log

# Модульные тесты ассемблера
test-asm:
	python3 tools/test_asm.py

# Открыть временные диаграммы в GTKWave
wave:
	gtkwave sim/tb_sort.vcd &

clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.log

.PHONY: sort sort-trace bcd wave asm-sort cmp-sort sort-asm test-asm clean
