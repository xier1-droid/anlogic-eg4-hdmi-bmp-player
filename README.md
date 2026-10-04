# 安路 EG4 HDMI 图片播放器

当前开发任务：系统稳定性增强，分支 `feature/system-stability-v0.4.0`。S0本地回归完成，待用户上板；S1未开始，未上传GitHub。[阶段计划](docs/系统稳定性增强分阶段计划.md) · [S0候选与上板清单](releases/v0.4.0-stability-s0-local.1/BOARD_VALIDATION.md)。正式下载仍为已验收v0.3.0。

目录入口：[统一文档](docs/README.md) · [构建与诊断归档](diagnostics/README.md)。原docx已合并为docs；测试入口见诊断归档。

已验收版本：**[v0.3.0](releases/v0.3.0/README.md)**，2026-10-05。已按用户要求将`feature/hdmi-audio-v0.3.0`合并到主分支`main`，包含文档统一和诊断归档。

R2 HDMI音频计划已结项：S0/S1、S4、S6、S7、S8、S9获用户上板确认，S2/S5独立模块验证完成，S3独立EDID取消。[完整阶段记录](docs/HDMI音频分阶段修改计划.md) · [结项归档](docs/history/2026-10-05/HDMI音频升级/README.md)。

基于 Anlogic EG4S20BG256，从TF卡读取BMP图片，使用SDRAM双缓冲输出640×480 HDMI视频和48kHz双声道图片琶音。实际显示提交后触发一次提示音，音量固定128。本版移除旧音频PLL/I2S/AXIS及官方加密HDMI依赖，保留系统/视频两颗PLL，五个时钟域各自同步释放复位；最近已验收节点为S9。

正式产物：[v0.3.0固定bit与说明](releases/v0.3.0/README.md) · [S9上板验收记录](releases/v0.3.0-r2-s9-local.1/BOARD_VALIDATION.md)。SD复位/拔卡恢复问题已记录，用户明确本版本不修、暂不修改。全局时序仍未收敛。

## 使用方式

| SW2 SW1 | 模式位 | KEY1 | KEY2 |
|---|---|---|---|
| 00 | 0 图片 | 上一张 | 下一张 |
| 01 | 1 亮度预留 | 不产生新请求 | 不产生新请求 |
| 10 | 2 对比度预留 | 不产生新请求 | 不产生新请求 |
| 11 | 3 缩放预留 | 不产生新请求 | 不产生新请求 |

KEY4单击切换MAN/AUTO。复位默认MAN，扫描完成且图片多于一张时允许切换AUTO。三个按键20ms消抖，长按不连发；图片首尾循环。

AUTO在四模式下保持，加载完成且空闲约3秒后再翻图，实际间隔包括加载时间。模式变化重新计时，S1修复模式变化恰逢AUTO到期时同拍误发翻图请求；已有手动挂起请求继续处理。图片编号位小数点表示AUTO。

加载期间每个方向最多挂起一次，同向请求合并；下一张优先于上一张，再优先于自动轮播。模式切换不清除已有挂起请求；切回MAN不取消已开始的加载和挂起的手动请求。图片编号在显示交接确认后更新。

## 硬件与图片

| 信号 | FPGA引脚 | 说明 |
|---|---|---|
| KEY1 | A2 | 按下为0 |
| KEY2 | B2 | 按下为0 |
| KEY4 | C1 | 按下为0 |
| SW1 | C8 | 拨上为1 |
| SW2 | C7 | 拨上为1 |

图片须为640×480、24位、未压缩BMP。程序按扇区顺序扫描前131072个扇区，最多查找4张图片，不依赖FAT文件名；上电自动加载首图。模式位显示0/1/2/3，不代表亮度、对比度或缩放已经实现。

## 下载与构建

- [v0.3.0已验收图片音调版本](releases/v0.3.0/demo.bit)
- [S8已验收恢复产物](releases/v0.3.0-r2-s8-local.1/demo.bit)
- [S6已验收静音恢复产物](releases/v0.3.0-r2-s6-local.1/demo.bit)
- [S4已验收恢复产物](releases/v0.3.0-r2-s4-local.1/demo.bit)
- [S1恢复用固定bitstream](releases/v0.3.0-s1-local.1/demo.bit)
- [中文版本说明及构建报告](releases/v0.2.0/README.md)
- [交接记录](HANDOFF.md)、[归档索引](docs/ARCHIVE_INDEX.md)、[合并审核说明](docs/history/2026-10-04/V0_2_0_MERGE_REVIEW.md)

使用Tang Dynasty 6.2打开 `TD_project/demo.al`，选择器件EG4S20BG256、顶层 `top`，依次综合、布局布线、生成bitstream。运行产物 `TD_project/demo_Runs/phy_1/demo.bit` 会被后续构建覆盖，正式下载使用 `releases/v0.3.0/demo.bit`，不使用旧 `best_result` 产物。

## 验证状态与范围

S9已获用户整体上板确认，v0.3.0沿用其固定bit。S9完整ModelSim回归及TD构建证据保留；PLL为2个，STA覆盖99.86%，像素→串行+6.376ns，Setup−6.565ns，仍有64个SDRAM接口违例。已知SD恢复问题按用户决定延期，未作修复。详见[验证状态](docs/VALIDATION_STATUS.md)。

本版不包含OSD、B/C调节和图像处理、缩放。B初值0、范围−128..127；C初值128、范围0..256、至少9位，仅记录为后续需求。

S5独立封装及双PCM源接口已完成，详见[模块交付与仿真证据](releases/v0.3.0-r2-s5-local.1/README.md)。S5无新bit或上板要求；S6已接入新核心，预期正常图片及静音，详见[上板验证文档](releases/v0.3.0-r2-s6-local.1/BOARD_VALIDATION.md)。

S6静音、S7正弦音、S8图片联动、S9清理均已获用户确认；正式发布使用S9产物。
