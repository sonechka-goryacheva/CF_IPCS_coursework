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

# Открыть временные диаграммы в GTKWave
wave:
	gtkwave sim/tb_sort.vcd &

# Полный перебор BIN2BCD (65536 входов)
bcd:
	@mkdir -p sim
	iverilog -g2005 -o sim/bcd.vvp rtl/BIN2BCD.v tb/tb_bin2bcd.v
	vvp sim/bcd.vvp | tee sim/bcd.log

clean:
	rm -f sim/*.vvp sim/*.vcd sim/*.log

.PHONY: sort sort-trace bcd wave clean
