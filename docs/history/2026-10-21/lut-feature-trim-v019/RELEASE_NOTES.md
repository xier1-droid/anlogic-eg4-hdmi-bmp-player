# v0.19.0 正式版：去掉圆形音频可视化

[下载 demo.bit](../../../../releases/v0.19.0/demo.bit)（645920 字节）。复用已验收 s1-local.1 原 bit，逐字节一致，未重新构建。基线及回退：[v0.18.0](../../../../releases/v0.18.0/README.md)。

与 v0.18.0 相比只有一处可见差别：**普通模式播放音乐时，右下角不再显示彩色圆形音频环**，原位置直接显示图片。音乐、字幕、参数条、四宫格、转场、场景模式和预警都保持不变。

## 资源与时序

| | v0.18.0 | **v0.19.0** |
|---|---|---|
| LUT | 15173（77.4%） | **14489（73.9%，−684）** |
| 寄存器 | 8529 | 8447 |
| BRAM9k / BRAM32k | 52 / 2 | 30 / 2 |
| DSP | 24 | 24 |
| Setup / Hold | +0.122 / +0.021 ns | +0.155 / +0.003 ns |

Hold 的最小值出现在 SDRAM 时钟域（ext_mem_clk），与本次改动无关，v0.17.0 正式版也是 +0.003 ns。

## 改动

| 文件 | 内容 |
|---|---|
| top_tf_hdmi_audio.v | `AUDIO_VIS_ENABLE = 0`，音频环的柱高计算和 ROM（21 个 BRAM9k）被综合剪掉；overlay 只保留 2 拍对齐流水 |
| audio/fat32_pcm_stream.v | 新增寄存输出 `error_flag`，每拍都等于 `error_code!=0` |
| SD/sd_card_bmp.v | 旁白“已播完”判断改用 error_flag，去掉 8 位或运算 |

方案书中的加分项 5（音频可视化）因此失效，已在方案书里标明。后续功能可用余量：到 85% 约 1900 LUT，BRAM9k 余 34 个。

[最终验证](../../../../releases/v0.19.0/FINAL_VALIDATION.md) · [候选说明](../../../../releases/v0.19.0/s1-local.1/README.md) · [源码输入](../../../../releases/v0.19.0/s1-local.1/MANIFEST.md) · [板测结果](../../../../releases/v0.19.0/s1-local.1/BOARD_RESULT.md) · [时序报告](../../../../releases/v0.19.0/s1-local.1/reports/final_timing.rpt) · [阶段计划](阶段修改计划.md) · [归档](README.md)。
