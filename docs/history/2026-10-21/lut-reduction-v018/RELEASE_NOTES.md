# v0.18.0 正式版：LUT 减量（功能不变）

[下载 demo.bit](../../../../releases/v0.18.0/demo.bit)（670364 字节）。复用已验收 s1-local.1 原 bit，逐字节一致，未重新构建。基线及回退：[v0.17.0](../../../../releases/v0.17.0/README.md)。

功能与 v0.17.0 相同，只有一处可见差别：**没有 FONT.BIN 的卡，普通模式字幕里的中文字显示为空白**（板上 case 字库已删除，中文字形只从卡上 FONT.BIN 读取；ASCII 部分照常显示）。用 `tools/make_scene_pack.py --text` 生成的卡都带 FONT.BIN，不受影响。按键计时改为共用 1 ms 节拍，各时长与 v0.17.0 相差不超过 1 ms。

## 资源与时序

| | v0.17.0 | **v0.18.0** |
|---|---|---|
| LUT | 15840（80.8%） | **15173（77.4%，−667）** |
| 寄存器 | 8677 | 8529 |
| BRAM9k / BRAM32k | 52 / 2 | 52 / 2 |
| DSP | 26 | 24 |
| Setup / Hold | +0.143 / +0.003 ns | +0.122 / +0.021 ns |

## 改动（S1）

| 批 | 内容 |
|---|---|
| 1 | BRAM 字库模式不再例化 case 字库；音频环与字幕共用一份行/帧位置计数 |
| 2 | hazard_layer 噪声四角共享乘积项、尘粒哈希只算一次、噪声移位改定值选择（与 v0.17.0 逐位等价） |
| 3 | 旁白“已播完”改为 1 位标志 |
| 4 | 消抖、长按重扫、长按进出场景、调节手势共用 1 ms 预分频 |

S2（共用 BMP header checker、扫描表清零、hazard 常数表与音频环改 BRAM）各批在模块层面均逐周期等价，但全设计物理 LUT 没有超过构建噪声的稳定收益，且多次引发 SD 域无关路径时序失败，按用户决定不纳入；S3（OSD 叠加链合并）未做。详见 [LUT 记录](../../../../diagnostics/lut_opt18/LUT_RECORD.md)。

[最终验证](../../../../releases/v0.18.0/FINAL_VALIDATION.md) · [候选说明](../../../../releases/v0.18.0/s1-local.1/README.md) · [源码输入](../../../../releases/v0.18.0/s1-local.1/MANIFEST.md) · [板测结果](../../../../releases/v0.18.0/s1-local.1/BOARD_RESULT.md) · [时序报告](../../../../releases/v0.18.0/s1-local.1/reports/final_timing.rpt) · [阶段计划](阶段修改计划.md)。
