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
