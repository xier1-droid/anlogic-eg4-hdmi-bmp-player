# v0.19.0 S1 候选（s1-local.1）

## 基线与候选

| | 基线 v0.18.0 | 候选 lut19_attempt01_s5 |
|---|---|---|
| 来源 | main 02f94ba，lut18_attempt02_s3 | 分支 feature/lut-feature-trim-v019 |
| LUT | 15173 | **14489（73.9%，−684）** |
| 寄存器 | — | 8447 |
| BRAM | — | 30 BRAM9K（−22）+ 2 BRAM32K |
| DSP | — | 24 |
| Setup / Hold | +0.122 / +0.021 ns | +0.155 / +0.003 ns |

- 候选的最差 Hold +0.003 ns 出现在 ext_mem_clk，与 v0.17.0 正式版相同，与本次改动无关。
- 时序审计的 14 类结果与 v0.18.0 相同。
- 构建命令：diagnostics/media_adjust/run_td.ps1 -HighFanoutOptimization -PlacementStrategy 5。
  - 用策略 3 构建时，Setup 为 −0.214 ns，失败路径是 u_cache_control 内部路径，这个模块没有改动。所以候选用策略 5。

## 改动

| 文件 | 内容 |
|---|---|
| top_tf_hdmi_audio.v | `AUDIO_VIS_ENABLE = 0`。综合时剪掉 audio_ring_levels 和 audio_ring_rom（21 BRAM9K）；overlay 只保留 2 拍对齐流水 |
| audio/fat32_pcm_stream.v | 新增寄存输出 `error_flag`，每拍都等于 `error_code!=0`，不增加延迟 |
| SD/sd_card_bmp.v | narration_done 改用 error_flag，去掉 8 位或运算 |

单独去掉音频环时（隔离构建，见 diagnostics/lut_opt19/LUT_RECORD.md），路径 u_stream/error_code→u_cache_control 只剩 +0.031 ns 余量（策略 3 下为 −0.225 ns）。加寄存后这条路径消失。

## 验证

证据见 MANIFEST.md 和 validation/：

- **lockstep 等价测试**：lut19_error_flag6。
  - 与冻结的 v0.18.0 模块对比 3M 周期，输出逐拍一致，error_flag 每拍都等于 error_code!=0。
  - 变异体 mut_no_flag 被检出。
- **场景套件**：run_m1/m3/m4/m5（lut19_m*_1），含变异体。
- **单元测试**：media_adjust、PCM S2。
- **等价台**：hazard 等价（lut19_hazard_equiv1）、按键节拍（lut19_keys1）。
- **18 项回归**：
  - lut19r1 跑完前 15 项。
  - preview、system 两项在 lut19r1 中仿真途中被中断，由 lut19r2 重跑通过。
  - video_delay 在 lut19r2_video_delay1 中重跑通过。

## 已知限制

- 普通模式不再显示圆形音频可视化（用户决定），方案书中的加分项 5 失效。
- 尚未上板。
