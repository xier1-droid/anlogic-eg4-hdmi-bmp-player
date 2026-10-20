# v0.18.0 S1 候选（s1-local.1）

- 基线：v0.17.0（main 361d1c5，mountain_attempt34_s3，15840 LUT，Setup +0.143 / Hold +0.003 ns）。
- 候选：lut18_attempt02_s3，源码 1148e6e（分支 feature/lut-optimization-v018），**15173 LUT（77.4%，−667）**、8529 寄存器、52 BRAM9K + 2 BRAM32K、24 DSP（−2），Setup +0.122 / Hold +0.021 ns。时序审计 14 类与基线相同。
- 构建：diagnostics/media_adjust/run_td.ps1 -HighFanoutOptimization -PlacementStrategy 3（与基线同配置）。

## 改动

| 批 | 文件 | 内容 |
|---|---|---|
| 1 | osd/scroll_text_overlay.v、top_tf_hdmi_audio.v | BRAM 字库模式不再例化 case 字库（无 FONT.BIN 时中文空白）；音频环与字幕共用一份位置计数 |
| 2 | scene/hazard_layer.v | 噪声四角共享乘积项、尘粒哈希先选输入后算一次、噪声移位改定值选择（逐位等价） |
| 3（部分） | audio/fat32_pcm_stream.v、SD/sd_card_bmp.v | 旁白循环计数改 1 位“已播完”标志（LOOP_BITS 参数，默认 32） |
| 4 | SD/mode_key_control.v | 全部按键计数共用 1 ms 节拍（新模块 key_ms_debounce），时长与旧版相差 ≤1 ms |

批3 其余（解码器行计数、sd_card_cmd 字节计数）在 lut18_attempt03_s3 中全局 +36 LUT（噪声内）且 sd_card_clk −0.058 ns（thumb_writer FIFO 路径，未改动的模块），按规则放弃；diff 保存在 diagnostics/output/lut18_attempt03_s3/rejected。

## 验证（最终源码 1148e6e）

见 MANIFEST.md 与 validation/。等价台：lut18_hazard_equiv3（hazard 对 v0.17.0 逐周期，2690 万周期，3 变异体）、lut18_keys1（按键对 v0.17.0，3 种子 × 300 手势，沿差 ≤1 节拍，3 变异体）。场景套件 run_m1/m3/m4/m5、media_adjust 单元、PCM 单元、按键 4 个旧测试台、18 项回归 lut18r3。

## 已知限制

- 无 FONT.BIN 的卡中文字幕空白（用户已确认接受）。
- 尚未上板。
