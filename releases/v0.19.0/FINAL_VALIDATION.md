# v0.19.0 最终验证（2026-10-21）

- 正式 demo.bit 复用 s1-local.1，645920 字节；与候选文件、构建输出 lut19_attempt01_s5 及标签 v0.19.0-s1-board.1 内的 bit 逐字节一致。
- 生产源码及 TD 工程相对 v0.19.0-s1-board.1 标签无变化，未重新构建或重复仿真。候选打包时 108 个工程输入与 lut19_attempt01_s5 构建快照逐字节一致，其中 3 个相对 v0.18.0 有改动。
- lut19_attempt01_s5 完整 TD（HighFanoutOptimization、strategy 5、opt_timing high、post_place_opt high）：14489 LUT（73.9%）、8447 寄存器、BRAM9k 30、BRAM32k 2、24 DSP，Setup +0.155 ns、Hold +0.003 ns；时序审计 14 类与 v0.18.0 相同。
- 策略 3 的构建 Setup −0.214 ns（失败路径在未改动的 u_cache_control 内部），不作为候选。
- 最终源码仿真（s1-local.1/validation，170 份通过日志、35 份变异体检出日志）：error_flag 对冻结 v0.18.0 模块 300 万周期逐拍一致（含变异体）、hazard 等价、按键节拍、run_m1/m3/m4/m5、PCM 单元、调节单元、四宫格与重扫按键、18 项回归。其中回归的 preview、system、video_delay 三项在第一次串跑中被截断，由 lut19r2 重跑通过。
- 板测（只记录用户反馈）：s1-local.1 “功能正常”（2026-10-21，整体反馈，未逐项；圆环区域、旁白播完后 AUTO 前进、四宫格、预警、Flash 冷启动与连续运行时长未单独给出）。
- 已知限制：普通模式没有圆形音频可视化；无 FONT.BIN 的卡中文字幕空白；换卡需要复位；雨丝曾在 v0.17.0 板上一度不显示，原因未定位；离线计算到达时刻 T 的合规性仍待官方答复。
- 回退 releases/v0.18.0/demo.bit。未跟踪用户素材保留。
