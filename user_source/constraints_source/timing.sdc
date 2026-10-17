# S3: one PLL, five generated clocks; no audio PLL / I2S clock domain.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
# Explicit ratios avoid TD derive_clocks rounding the C2 phase to 173 degrees.
create_generated_clock -name sd_card_clk -source [get_ports {clk}] -multiply_by 2 [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
create_generated_clock -name ext_mem_clk -source [get_ports {clk}] -divide_by 1.25 [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
create_generated_clock -name ext_mem_clk_sft -source [get_ports {clk}] -divide_by 1.25 -phase 172.8 [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
create_generated_clock -name video_clk -source [get_ports {clk}] -divide_by 2 [get_pins {sys_pll_m0/pll_inst.clkc[3]}]
create_generated_clock -name hdmi_5x_clk -source [get_ports {clk}] -multiply_by 2.5 [get_pins {sys_pll_m0/pll_inst.clkc[4]}]

# Pixel and serial clocks run concurrently from the same PLL.
# Remove the legacy exclusive group so the serializer crossings are analyzed.
# Reset release is synchronized in each local domain; no new timing exceptions.
# SPI Mode 3: 100 MHz CE-driven logic, fastest half-cycle = 3 clocks.
# See docs/timing_closure/IO_TIMING.md for electrical assumptions and CE proof.
# Returned data: <=5 ns SCLK clk-to-pad + <=2 ns board roundtrip + 14 ns card.
set_input_delay -clock sd_card_clk -max 21.000 [get_ports sd_miso]
set_input_delay -clock sd_card_clk -min 0.000 [get_ports sd_miso]
# Only the direct MISO capture cone; internal SD paths keep single-cycle checks.
set_multicycle_path 3 -setup -end -from [get_ports sd_miso] -to [get_clocks sd_card_clk]
set_multicycle_path 2 -hold -end -from [get_ports sd_miso] -to [get_clocks sd_card_clk]
# Card setup/hold 5 ns + <=1 ns board data/clock mismatch.
# Sampling is >=30 ns after launch. Next change is >=30 ns after sampling.
# The extra hold cycle moves this conservative hold check to the previous edge.
set_output_delay -clock sd_card_clk -max 6.000 [get_ports {sd_mosi sd_ncs}]
set_output_delay -clock sd_card_clk -min -6.000 [get_ports {sd_mosi sd_ncs}]
set_multicycle_path 3 -setup -end -from [get_clocks sd_card_clk] -to [get_ports {sd_mosi sd_ncs}]
set_multicycle_path 3 -hold -end -from [get_clocks sd_card_clk] -to [get_ports {sd_mosi sd_ncs}]
# Forwarded SCLK propagation budget used in the MISO return calculation.
set_output_delay -clock sd_card_clk -max 0.000 [get_ports sd_dclk]
set_output_delay -clock sd_card_clk -min 0.000 [get_ports sd_dclk]
set_max_delay -from [get_clocks sd_card_clk] -to [get_ports sd_dclk] 5.000 -datapath_only
# HDMI digital propagation budget: 4 ns UI minus 0.5 ns engineering reserve.
# These are output-delay bounds, not receiver setup/hold or an eye-mask claim.
# TD needs output clock association to analyze the two ODDR launch edges.
set_output_delay -clock hdmi_5x_clk -max 0.000 [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}]
set_output_delay -clock hdmi_5x_clk -min 0.000 [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}]
set_max_delay -from [get_clocks hdmi_5x_clk] -to [get_ports {HDMI_CLK_P HDMI_D0_P HDMI_D1_P HDMI_D2_P}] 3.500 -datapath_only
# UART log and subtitle are off by default (top UART_LOG_ENABLE /
# UART_SUBTITLE_ENABLE = 0): uart_tx is a constant and uart_rx is unused.
# Restore these constraints together with either parameter. With uart_tx
# constant, TD drops the -to of the max_delay and applies 10 ns datapath-only
# to every sd_card_clk path (mountain_attempt27: -15.8 ns on sd_miso).
# UART is asynchronous at the receiver. Bound only FPGA TX propagation;
# 10 ns is an engineering budget versus the 8680 ns serial bit interval.
# set_output_delay -clock sd_card_clk -max 0.000 [get_ports uart_tx]
# set_output_delay -clock sd_card_clk -min 0.000 [get_ports uart_tx]
# set_max_delay -from [get_clocks sd_card_clk] -to [get_ports uart_tx] 10.000 -datapath_only

# Asynchronous UART input: TD packs rx_meta into the F12 input PAD FF.
# Only port-to-input-register timing is exempt; rx_sync remains timed.
# set_false_path -from [get_ports uart_rx] -to [get_cells {uart_rx_syn_4}]
