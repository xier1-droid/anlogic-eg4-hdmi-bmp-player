# v0.18.0 LUT 减量记录

基线 v0.17.0（mountain_attempt34_s3）：物理 15840 LUT（lut 列，80.82%）/ 8677 寄存器 / 52 BRAM9K + 2 BRAM32K / 26 DSP，Setup +0.143、Hold +0.003 ns。构建均用 `diagnostics/media_adjust/run_td.ps1 -HighFanoutOptimization -PlacementStrategy 3`（与 attempt34_s3 同配置：hfn high、pr_strategy 3、opt_timing high、post_place_opt high），约束不变。单批 ±100～150 为噪声，按累计判断。

| 构建 | 内容 | 物理 LUT | 寄存器 | DSP | Setup / Hold ns | 结论 |
|---|---|---:|---:|---:|---|---|
| lut18_attempt01_s3 | 批1 + 批2 | 15525（−315） | 8653 | 24 | +0.144 / +0.020 | 保留 |
| lut18_attempt02_s3 | + loop_count 标志 + 批4 | 15173（−667） | 8529 | 24 | +0.122 / +0.021 | 保留 |

## 批1：case 字库、位置计数

- scroll_text_overlay（BRAM_FONT=1）不再例化 osd_font_cn_16x16；无 FONT.BIN 时中文字形空白。tb_m5_scroll_font 改为：BRAM 字库与 case 字库逐像素相同；无字库时等于 case 字库去掉中文像素（并断言确有中文像素被去掉）。
- 顶层 u_ring_position 与 u_subtitle_position 输入相同，合为一份。
- 模块变化（attempt01 对 34_s3）：bridge −248（吸收的叠加链）、scroll −13、ring_position −14。

## 批2：hazard_layer

- 四个噪声角共享 ncx*73+ncy*151（+73/+151/+224 增量），hc 先选输入后哈希一次；nsx∈{2,3,4,5}、nsy∈{1,2,4} 的移位改为定值选择。
- lut18_hazard_equiv3：对冻结的 v0.17.0 模块逐周期比较输出及 C1 寄存项，2 种子 2690 万周期一致，3 个变异体检出。首次运行抓到 nsy=1 小数位写错（{nv[2:0],0} 应为 {nv[0],000}），修正后通过。
- 模块变化：hazard_layer −91，DSP −2。

## loop_count 标志

- fat32_pcm_stream 新增 LOOP_BITS（默认 32，单元测试不变）；sd_card_bmp 只用 !=0，取 1 位。lut18_pcm_s2_1 三项通过。

## 批4：按键共用 1 ms 节拍

- 一个 ms 预分频驱动 3 个消抖（新模块 key_ms_debounce）、KEY2 重扫、KEY4 场景长按和调节手势。旧计数从 1 起、到 N−1 止，实际短 2 个时钟；按节拍计数会短 2 ms，故实时钟下阈值加 1～2 个节拍（TICK_ADJ），各时长与旧版相差在 1 ms 内；1 kHz 测试时钟下 TICK_ADJ=0，计数与旧版相同。
- lut18_keys1：20 时钟/ms 下对冻结模块，3 种子各 300 次手势（含抖动、模式切换、禁用），全部输出沿在一个节拍内对应，3 个变异体检出。tb_m4_keys（lut18_m4_1）、run_m5（lut18_m5_2/2b）、tb_preview_keys、tb_rescan_key、media_adjust 单元 6 项通过。
- 模块变化（attempt02 对 01）：sd_card_bmp −303（mode_key_control 486→209）。

## S1 回归

- lut18r1（run_m3_regression，18 项）在批1+2+loop_count 源码上全部通过；lut18_m3_1、lut18_m5_1 通过。批4 之后已重跑按键相关全部测试；S1 最终源码仍需完整重跑。

| lut18_attempt03_s3 | + 解码器 row_payload/row_last 13 位、sd_card_cmd byte_cnt 10 位 | 15209（+36 对 02） | 8512 | 24 | **−0.058** / +0.012 | 放弃：全局无收益（decoder −35、sd_card_cmd −47，被噪声抵消），最差路径 thumb_writer FIFO wr_addr→received.ce（未改模块）。diff 存 output/lut18_attempt03_s3/rejected |

## S1 候选

- releases/v0.18.0/s1-local.1：lut18_attempt02_s3 bit（670364 字节），源码 1148e6e；108 个构建输入逐字节一致，6 个改动输入，171 份通过日志、34 份变异体日志。时序审计（lut18_attempt02_s3/timing_audit）14 类与 v0.17.0 相同，dangling 节点 4（同数，位置不同）。
- 最终源码验证：lut18r3 18 项回归、lut18_m1_1、lut18_m3_2、lut18_m4_1、lut18_m5_2、lut18_adjust_unit1、lut18_pcm_s2_1、lut18_preview_keys1、lut18_rescan_key1、lut18_hazard_equiv3、lut18_keys1。
- 批3 未做项：streamer 簇号 28 位（FAT 高 4 位来自卡上数据，不能确认恒为 0；收益在噪声内）、缩放 inside 边沿标志（约 −20）。
- S1 board.1：用户确认 s1-local.1“功能通过，继续下一步”（2026-10-20，整体反馈），标签 v0.18.0-s1-board.1。

## S2

基线 S1 board.1（lut18_attempt02_s3，15173 LUT）。

| 构建 | 内容 | 物理 LUT | DSP | Setup / Hold ns | 结论 |
|---|---|---:|---:|---|---|
| lut18_attempt04_s3 | 批5 共用 header checker | 15118（布局后，−55） | — | 布线失败 | 放弃 |

### 批5：共用 header checker（放弃）

- 缩放路径下 preflight 与解码器分时共用一个 bmp_header_check，寄存的 header_load 在 IDLE 的 scan_start/load_start 切换；bmp24_decoder 加 SHARED_HEADER 参数与 229 位结果总线。
- lut18_header2：新 reader 与冻结的 v0.17.0 reader 同输入逐周期比较，42 用例 × 字节间隔 0/2 × 缩放/固定两条路径 + 5 个注入模式 × 2 路径共 178 次全部一致；3 个变异体（选择不切换、偏移用扇区索引、解码字节无效）均由逐周期比较检出。缩放路径上除 case 0 mode 0 外，fixture 的结果契约按固定路径写（4 簇遍历上限、宽度 3），只做逐周期比较（CHECK_CONTRACT=0）。
- lut18_attempt04_s3：布局后 15118 LUT（仅 −55，估算 −420～−470 未兑现，单个 checker 的大部分逻辑被综合按常数/未用输出裁掉过），布线 PHY-8023 在 x24y19 处 scaler 复位网拥塞，RUN-8102 增量布线失败，无 bit。
- 按规则放弃，源码恢复 S1；diff 存 output/lut18_attempt04_s3/rejected。等价台与冻结模块保留（diagnostics/lut_opt18/tb_reader_lockstep.sv、run_s2_header.ps1、*_v017.v），供后续 reader 改动复用。
