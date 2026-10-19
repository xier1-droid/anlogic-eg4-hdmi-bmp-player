# v0.17.0 正式版：山区防灾避险课堂

[下载 demo.bit](../../../../releases/v0.17.0/demo.bit)（670364 字节）。复用已验收 m5-local.2 原 bit，逐字节一致，未重新构建。基线及回退：[v0.16.0](../../../../releases/v0.16.0/README.md)。

在原有图片轮播、缩略图、转场、调节、音频全部保留的前提下，加入“山区防灾避险课堂”场景模式：SD 卡场景包里的 32 位 BMP 携带每像素到达时刻，FPGA 按推演时间实时合成灾害图层，配合分阶段旁白、音画同步转场、卡上字库文案和预警模式。

## 使用

- **普通图片模式**与 v0.16.0 相同。差别：mode 0 短按 KEY4 改为松手时切换 MAN/AUTO；串口日志与串口字幕已去掉（字幕固定为上电默认文案）。
- **场景模式**：mode 0 长按 KEY4 约 1 秒进出。KEY2 下一阶段（4→1），短按 KEY4 MAN/AUTO（AUTO 等本阶段推演和旁白结束后再走）。
- **预警模式**：场景模式、mode 0 下按 KEY1 进出。跳到阶段 4、SND4 循环、红框闪烁、显示村名和预警语，数码管末位为 A。
- **推演速度**：场景模式下拨到 01/10，KEY4 选到 S，KEY1/KEY2 调 1X/2X/4X。
- **场景卡**：`python -I tools/make_scene_pack.py <scene.yaml> --audio --text` 生成 PIC1–4.BMP、SND1–4.PCM、FONT.BIN、TEXT.BIN，拷到卡根目录，再放 BGM.PCM。四张示例卡（滑坡、泥石流、山洪、地震）在 `tools/scenes/*_village/`，说明见 [tools/scenes/README.md](../../../../tools/scenes/README.md)。缺 SND 时播放 BGM，缺 FONT/TEXT 时不显示场景文字，24 位普通图不着色。

## 里程碑

| 里程碑 | 内容 | 验收 |
|---|---|---|
| M1 | 32bpp 像素通路：alpha 作为到达时刻 T 写入 SDRAM 像素低 8 位 | [m1-board.1](../../../../releases/v0.17.0/m1-local.1/BOARD_RESULT.md) |
| M2 | 场景包工具（图像部分）、hazard_layer 参考模型 | 用户目视确认 |
| M3 | hazard_layer：四类灾害“致因→发生→后果→撤离”；去掉串口日志/字幕以让出资源 | [m3-board.1](../../../../releases/v0.17.0/m3-local.2/BOARD_RESULT.md)、[m3-board.2](../../../../releases/v0.17.0/m3-local.3/BOARD_RESULT.md) |
| M4 | 场景模式、scenario_fsm、SND1–4 分阶段旁白、fade_mute 音画同步转场 | [m4-board.1](../../../../releases/v0.17.0/m4-local.1/BOARD_RESULT.md) |
| M5 | FONT/TEXT 卡上字库与文本（BRAM32k）、场景 OSD、预警模式、推演速度 | local.1 [未通过](../../../../releases/v0.17.0/m5-local.1/BOARD_RESULT.md)；[m5-board.1](../../../../releases/v0.17.0/m5-local.2/BOARD_RESULT.md) |
| M6 | 整机验收 | 见下 |

## 资源与时序

| | v0.16.0 | **v0.17.0** |
|---|---|---|
| LUT | 14190（72.4%） | **15840（80.8%）** |
| 寄存器 | 8250 | 8677 |
| BRAM9k / BRAM32k | 54 / 0 | 52 / 2 |
| DSP | 13 | 26 |
| Setup / Hold | +0.144 / +0.003 ns | +0.143 / +0.003 ns |

## 整机实测（用户板测反馈）

- Flash 冷启动到出图：4 秒。
- 连续运行：50 分钟，功能正常。
- 换卡加复位到首帧：约 4 秒。
- M6 整机验收板测功能均通过（整体反馈，未逐项）。

[最终验证](../../../../releases/v0.17.0/FINAL_VALIDATION.md) · [候选说明](../../../../releases/v0.17.0/m5-local.2/README.md) · [源码输入](../../../../releases/v0.17.0/m5-local.2/MANIFEST.md) · [时序报告](../../../../releases/v0.17.0/m5-local.2/reports/final_timing.rpt) · [阶段计划](../../../../docs/山区避险课堂分阶段修改计划.md) · [归档](README.md)。
