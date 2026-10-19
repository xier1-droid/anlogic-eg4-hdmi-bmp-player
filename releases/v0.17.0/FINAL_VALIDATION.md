# v0.17.0 最终验证（2026-10-19）

- 正式 demo.bit 复用 m5-local.2，670364 字节；与候选文件及 v0.17.0-m5-board.1 标签内 bit 逐字节一致。
- 生产源码及 TD 工程相对 v0.17.0-m5-board.1 标签无变化（git diff 为空），未重新构建或重复仿真。候选打包时 108 个工程输入与 mountain_attempt34_s3 构建快照逐字节一致。
- mountain_attempt34_s3 完整 TD（HighFanoutOptimization、strategy 3、opt_timing high、post_place_opt high）：15840 LUT（80.8%）、8677 寄存器、BRAM9k 52、BRAM32k 2、26 DSP，Setup +0.143 ns、Hold +0.003 ns，0 ERROR；时序审计 14 类同 m4-local.1，仅多一个 BRAM32K 未用输出位的 dangling 节点。Hold +0.003 ns 在 hdmi_5x_clk 串行复位释放路径，与 v0.16.0 同值。
- 最终源码仿真（m5-local.2，161 份通过日志与 28 份变异体检出日志在 m5-local.2/validation，另加 84 例读卡）：run_m5（工具检查、场景 OSD 逐像素、字幕 BRAM 字库、FONT/TEXT 载入与预警、生产顶层、scenario_fsm 驱动的雨丝、14 个变异体）、run_m4、run_m3、run_m1、FAT32 读卡 84 例、调节单元 6 项、18 项回归（含生产顶层、真实 SDRAM 预览 165 帧、完整系统、PCM 与 tb_pcm_preview_rescan），统计与 m4-local.1 逐项相同。
- 板测（只记录用户反馈）：
  - M1、M3（两轮）、M4：整体“功能通过/正常”，记录见各候选 BOARD_RESULT。
  - M5：m5-local.1 未通过（雨丝一度不显示，随后复测正常、原因未复现；场景模式参数条与右上面板重叠）；m5-local.2“功能通过”。
  - M6 整机：用户反馈“M6整机验收的板测功能均通过”，连续运行 50 分钟，Flash 冷启动 4 秒，换卡加复位到首帧约 4 秒。整体反馈，未逐项列出原有功能回归。
- M6 计划中的“第 2 张场景卡”：M3 起已做四张卡（滑坡、泥石流、山洪、地震），换卡验收用这些卡完成。
- 已知限制：换卡需要复位（免复位换卡在后续计划）；串口日志与串口字幕已去掉；Hold 余量 3 ps；LUT 80.8%，距 85% 目标约 820；case 字库保留作无 FONT.BIN 时的回退；雨丝曾在板上一度不显示，原因未定位；离线计算到达时刻 T 的合规性仍待官方答复（技术实现 §10）。
- 回退 releases/v0.16.0/demo.bit。未跟踪用户素材保留。
