# v0.18.0 最终验证（2026-10-21）

- 正式 demo.bit 复用 s1-local.1，670364 字节；与候选文件及 v0.18.0-s1-board.1 标签内 bit 逐字节一致。
- 生产源码及 TD 工程相对 v0.18.0-s1-board.1 标签无变化（git diff 为空；S2 各批改动均已撤回，diff 存 diagnostics/output 各构建的 rejected 目录），未重新构建或重复仿真。候选打包时 108 个工程输入与 lut18_attempt02_s3 构建快照逐字节一致。
- lut18_attempt02_s3 完整 TD（HighFanoutOptimization、strategy 3、opt_timing high、post_place_opt high，与 v0.17.0 同配置）：15173 LUT（77.4%）、8529 寄存器、BRAM9k 52、BRAM32k 2、24 DSP，Setup +0.122 ns、Hold +0.021 ns；时序审计 14 类与 v0.17.0 相同。
- 最终源码仿真（s1-local.1/validation，171 份通过日志、34 份变异体检出日志）：hazard_layer 对冻结 v0.17.0 逐周期等价（2 种子 2690 万周期）、按键对冻结 v0.17.0（3 种子 × 300 手势，输出沿差 ≤1 节拍）、run_m1/m3/m4/m5、PCM 单元、调节单元 6 项、四宫格与重扫按键、18 项回归 lut18r3（含生产顶层、真实 SDRAM 预览、完整系统）。
- 板测（只记录用户反馈）：s1-local.1 “功能通过，继续下一步”（2026-10-20，整体反馈，未逐项；无 FONT.BIN 卡中文空白、按键手感、雨丝、冷启动与连续运行时长未单独给出）。
- 已知限制：无 FONT.BIN 的卡中文字幕空白；换卡需要复位；串口日志与串口字幕仍去掉；雨丝曾在 v0.17.0 板上一度不显示，原因未定位；离线计算到达时刻 T 的合规性仍待官方答复。
- 回退 releases/v0.17.0/demo.bit。未跟踪用户素材保留。
