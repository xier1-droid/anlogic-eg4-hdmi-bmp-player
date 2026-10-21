# v0.19 功能裁剪 S1 实测记录

基线：v0.18.0 正式 bit，`diagnostics/output/lut18_attempt02_s3`。指标如下：

- 物理 15173 LUT，综合 14725 LUT
- 52 BRAM9k，24 DSP
- 时序 Setup +0.122 / Hold +0.021 ns

本轮构建全部用 `diagnostics/lut_opt19/run_td_ringoff.ps1`：

- 只在隔离副本里把 `top_tf_hdmi_audio.v` 的 `AUDIO_VIS_ENABLE` 改成 0，生产源码不改。
- 选项与基线相同：hfn high、opt_timing high、post_place_opt high。

## 构建 A：去掉圆形音频可视化

| 构建 | 策略 | 物理 LUT | 综合 LUT | BRAM9k | DSP | Setup / Hold (ns) |
|---|---|---|---|---|---|---|
| lut18_attempt02_s3（基线） | 3 | 15173 | 14725 | 52 | 24 | +0.122 / +0.021 |
| lut19_ringoff_a_s3 | 3 | 14523（−650） | 13993（−732） | 30（−22） | 24 | **−0.225** / +0.021 |
| lut19_ringoff_a_s5 | 5 | 14558（−615） | 13993（−732） | 30（−22） | 24 | +0.031 / +0.014 |

- 收益远大于 ±150 的噪声，读码估算的 −550～−600 成立。
- `audio_ring_rom` 的 21 个 BRAM9k 和 `audio_ring_levels` 已完全剪掉。
- `u_audio_ring` 剩 59～82 LUT。这部分是保留下来的 2 拍视频对齐流水，理论上还能再省几十 LUT，但这个量在噪声以内，所以不做构建 B。
- 两次构建的最差路径相同，都在 sd_card_clk：
  - `g_audio$u_stream/error_code_reg` → `u_cache_control/cache_failed_reg[2]`，10 级 LUT。
  - 这条路径与音频环无关，属于 HANDOFF 里记录的布局敏感 SD 域路径。
  - 策略 3 在这条路径上 −0.225 ns 失败，策略 5 通过，但余量只有 +0.031 ns。
- 进入 S2 时有两个选择：
  - 直接用策略 5；
  - 或者把这条路径定点寄存一拍，提高余量。

## S1 生产源码：AUDIO_VIS_ENABLE=0 + error_flag 寄存

- 改动内容：
  - `fat32_pcm_stream` 增加单位寄存输出 `error_flag`，每一拍都等于 `error_code!=0`。
  - `sd_card_bmp` 的 narration_done 改用 error_flag，不再对 8 位 error_code 做或运算。
- 构建方式：`diagnostics/media_adjust/run_td.ps1 -HighFanoutOptimization -PlacementStrategy N`。

| 构建 | 策略 | 物理 LUT | 综合 LUT | BRAM9k | DSP | Setup / Hold (ns) | 说明 |
|---|---|---|---|---|---|---|---|
| lut19_attempt01_s3 | 3 | 14518（−655） | 13986（−739） | 30 | 24 | **−0.214** / +0.019 | 原 error_code 路径已消失；新的最差路径是 u_cache_control 内部 cache_valid→bank_map，未改模块 |
| lut19_attempt01_s5 | 5 | 14489（**−684**） | 13986（−739） | 30 | 24 | +0.155 / +0.003 | 候选 |

- s5 的 sd_card_clk Setup 从 +0.031 提高到 +0.155 ns。
  - 最差路径变成 preview full_view→cache_failed，与 v0.18.0 的 sd_card_clk 余量同级。
- 最差 Hold +0.003 ns 出现在 ext_mem_clk（SDRAM），与改动无关；v0.17.0 正式 bit 的 Hold 也是 +0.003。
  - 其余时钟域的 Hold 都在 +0.024 ns 以上。
- 策略 3 在本设计上落在布局敏感路径，不使用。
- 等价验证：`run_error_flag.ps1`（lut19_error_flag6）。
  - 3M 拍下与冻结的 v0.18.0 模块全部输出逐拍一致，error_flag 每一拍都等于 error_code!=0。
  - 覆盖面：20 次置位，其中 5 次为坏起始 8'h30、15 次为流错误；37 次播完，4 次复位。
  - 变异体 mut_no_flag 已被检出。
