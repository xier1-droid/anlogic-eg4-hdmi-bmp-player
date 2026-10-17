# v0.17.0 M3 local.3 候选：灾害图层 v3（四类灾害卡）+ 去掉串口日志与串口字幕

- 基线：v0.16.0（main 1818adc）。上一候选：m3-local.2（已板测通过，v0.17.0-m3-board.1）。回退：releases/v0.17.0/m3-local.2/demo.bit，或 releases/v0.16.0/demo.bit。分支 feature/mountain-escape-classroom。
- 构建 diagnostics/output/mountain_attempt29_s3：HighFanoutOptimization、**strategy 3**、opt_timing high、post_place_opt high（以前用 strategy 5，这次 5 和 2 时序不过，见“构建过程”）。
- 上板文件：本目录 demo.bit（670364 字节，与构建产物逐字节一致）。构建用的 105 个输入与仓库当前源码逐字节一致。

## 相对 local.2 的变化

1. **灾害图层 v3**（用户 2026-10-16 确认的方案，见计划文档“M3 修订”一节）：每张卡讲一个村、一种灾害，四张图依次为致因、发生（近景）、后果（全景）、撤离。支持滑坡、泥石流、山洪、地震四类，同一套逻辑。
   - 数据格式：BMP 文件头字节 6–7 写“灾害类型 + 作用”（24 位普通图为 0，图层不生效）；像素 T 为“2 位区域 + 6 位时刻”。
   - 雨：整屏随机移动，远近两层，约 17 秒一循环，没有闪电；致因图雨大、发生/后果图雨小，撤离图和地震卡没有雨。
   - 地震发生图：画面左右晃动并逐渐衰减（只做水平方向）。
   - 撤离图：危险区红色斜线，绿色流动路线，避险点闪烁；路线和避险点都在危险区以外（工具会检查重叠）。
2. **去掉串口事件日志和串口在线字幕**（用户 2026-10-18 决定）：顶层参数 `UART_LOG_ENABLE`、`UART_SUBTITLE_ENABLE` 默认 0。底部滚动字幕固定为原上电默认文案；uart_tx 一直为高，不再输出日志，也不再响应字幕命令。引脚不变。`timing.sdc` 里 UART 的约束已注释掉，要恢复时和参数一起改回。数码管 SD 调试页保留。

## 生产文件改动（相对 v0.16.0，见 sources/）

- `scene/hazard_layer.v`（v3 图层，调色项用 ROM）、`scene/hazard_test_source.v`（临时 t 源）、`scene/scene_kind_cdc.v`（新增：灾害类型从 SD 域送到像素域，随显示提交生效）。
- `SD/fat32_bmp_reader.v`、`SD/sd_card_bmp.v`：读出 BMP 表头字节 6–7，按缓冲区保存。
- `top_tf_hdmi_audio.v`：v3 图层接线；串口日志/字幕参数；`scene_kinds_sd` 声明提前（修复 ModelSim 编译错误，a30408e）。
- `constraints_source/timing.sdc`：UART 约束注释。
- `TD_project/demo.al`：加入 scene_kind_cdc.v。
- 以上 8 个文件是相对 local.2 的全部改动。另含 M1/M3 已验收、本次未改的 `bmp24_decoder.v`、`video_delay.v`、`bmp_scale_stream.v`、`image_scale_nearest.v`（相对 v0.16.0 的完整改动集共 12 个）。

## 资源/时序

| | local.2（attempt17） | v3 去串口前（attempt25） | **local.3（attempt29_s3）** |
|---|---|---|---|
| LUT | 14652（74.8%） | 16075（82.0%） | **14111（72.0%）** |
| 寄存器 | 8408 | 9128 | 8004 |
| BRAM9k | 56 | 62 | **52** |
| DSP | 13 | 26 | 26 |
| Setup / Hold | +0.116 / +0.014 ns | 未通过 | **+0.126 / +0.024 ns** |

- 0 违例端点，构建日志 0 条 ERROR。video_clk 域 Setup 裕量 +2.131 ns。
- 时序审计 14 类：只有“无输出延迟的端口”由 16 个变为 17 个，多出的是 uart_tx（约束已注释）；其余与 local.2 相同。

## 构建过程（如实记录）

| attempt | 布局策略 | 结果 |
|---|---|---|
| 26 | 5 | 源码随后修改，中途停止 |
| 27 | 5 | uart_tx 变成常量后 SDC 失效：`set_max_delay -to [get_ports uart_tx]` 的 -to 不再生效，10 ns datapath-only 套到了全部 sd_card_clk 路径，sd_miso 上 −15.8 ns。注释约束后重建 |
| 28 | 5 | Setup −0.111 ns（SD 域既有路径 cache_failed → selected_bad） |
| 29_s2 | 2 | Setup −0.272 ns（SD 域既有路径 fs_error → sector_lba） |
| **29_s3** | **3** | **通过，即本候选**；之后的 strategy 4 已停止 |

## 验证（validation/）

- `m3v3_uart_off3`（run_m3.ps1，四张 v3 卡）：
  - 重新生成 16 张场景图，与各卡 `out/sd/` 逐字节一致。
  - `tb_m3v3_sweep`：1,228,800 个向量与 Python 参考模型逐一比对。
  - `tb_m3v3_card`：四张卡 192 帧、58,982,400 个像素逐像素比对。
  - `tb_m3_chain`、`tb_m3_test_source`、读卡灾害类型（8 种组合）。
  - `tb_m3_top`：生产顶层 61,440 个像素对照标量模型（27,894 个被图层改色），含滑坡撤离、泥石流后果（带雨）、地震致因、缩略图旁路、无类型、首图前黑屏。该测试台此前因顶层编译错误一直没有实际运行，补上雨的模型后通过（d35357f）。
  - 变异体 5 个（雨长、噪声、扬尘、晃动钳位、同步）全部检出。
- `m3_uart_off2`（run_m3_uart_off.ps1）：新顶层与旧接法（日志和字幕都打开，uart_rx 空闲）在相同输入下比较最终画面，6 帧 1,804,800 个像素逐个一致（含 4398 个字幕像素），uart_tx 一直为高；改掉字幕文字的变异体在 line 444 被检出。
- `m3r_uart_off2_*`（run_m3_regression.ps1，18 项）全部通过；生产顶层 336271 像素/1148 样本/43 警告、预览 165 帧/105578 刷新/26 警告、完整系统 183705600 转场像素/32 警告、PCM 9279/9279、video_delay 300000 拍，与 local.2 逐项相同。

## 已知限制

- 仅本地仿真与 TD 通过，尚未上板。
- t 仍由临时测试源驱动（切图清零，每 2 帧加 1，0..239 循环），没有按键或音频控制；M4 由 scenario_fsm 实现。
- 标题、字幕、图例等 OSD 文案属于 M4/M5，本候选仍是原有 OSD；左上状态栏和音频环会压住部分画面。
- 串口不再有日志，排查 SD 问题只能看数码管调试页；需要日志时把 `UART_LOG_ENABLE` 改为 1 并恢复 SDC 约束后重建。
- TD 在本设计上不稳定，后续构建可能仍需多试几种布局策略。

## 板测

按 BOARD_VALIDATION.md 进行，请反馈候选名及实际通过/异常的项目。用户确认前不建 board 标签、不进入 M4。
