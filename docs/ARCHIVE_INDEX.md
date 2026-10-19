# 项目历史归档索引

## 按日期

| 日期 | 主要内容 |
|---|---|
| 2026-10-19 | [v0.17.0 山区防灾避险课堂结项](history/2026-10-19/mountain-escape-classroom/README.md) |
| 2026-10-14 | [v0.16.0 LUT 极致优化结项](history/2026-10-14/lut-optimization/README.md) |
| 2026-10-13 | [v0.15.0 亮度、对比度与总音量调节结项](history/2026-10-13/brightness-contrast-volume/README.md) · [v0.14.0 图片缩放与缩略图结项](history/2026-10-13/image-scaling-thumbnails/README.md) |
| 2026-10-12 | [v0.13.0 彩色圆形音频可视化结项](history/2026-10-12/circular-audio-visualizer/README.md) |
| 2026-10-08 | [FAT32 v0.7.0 结项](history/2026-10-08/fat32-filesystem/README.md) · [BMP 2.11 解码器独立化、板级验收与发布](history/2026-10-08/bmp24_decoder/README.md) |
| 2026-10-07 | [v0.5.2](history/2026-10-07/v0.5.2/README.md) · [v0.5.3](history/2026-10-07/v0.5.3/README.md) · [v0.5.4](history/2026-10-07/v0.5.4/README.md) |
| 2026-10-06 | [v0.5.1](history/2026-10-06/v0.5.1/README.md) · Flash 规划复核 |
| 2026-10-05 | [Flash 固化](history/2026-10-05/Flash固化与上电自启/README.md) · [HDMI 音频](history/2026-10-05/HDMI音频升级/README.md) · [系统稳定性](history/2026-10-05/系统稳定性增强/README.md) |
| 2026-10-04 | [阶段索引](history/2026-10-04/README.md) · 模式与按键控制 · HDMI 音频重规划 |
| 2026-10-03 | [早期归档](history/2026-10-03/README.md) |

## 归档规则

- 每个已完成任务保留一个 `README.md` 作为入口，计划、交接、验收和必要日志放在同一任务目录下。
- 根目录只保留当前仍被项目或发布文档引用的稳定入口，不为了整齐而破坏历史链接。
- 完全重复的副本经逐字节确认后由用户手动清理，主文件继续保留在对应版本或任务归档目录。
- 下方内容为此前累计的历史索引，状态描述以本页顶部和各任务归档入口为准。

## 既有历史记录

# BMP 2.11 已完成板级验收与本地归档（2026-10-08）

当前本地板级版本：v0.6.0-bmp211-s3-board.1，沿用 S3 local.1 原 bit。用户确认好图、坏图过滤、恢复/AUTO 功能正常；最终独立、稳定性及系统回归全部通过。2.12 不在范围内。GitHub 未上传，等待单独明确授权。

[版本、bit、验证及归档](history/2026-10-08/bmp24_decoder/README.md)。以下为历史过程记录。

# v0.5.4于2026-10-07结项

[归档入口](history/2026-10-07/v0.5.4/README.md) · [正式版本](../releases/v0.5.4/README.md)。下方旧阶段状态为历史记录。

# v0.5.4进行中

[S0基线与历史原文](history/2026-10-07/v0.5.4/S0_baseline.md)。此为过程归档，不是结项。完成后补最终计划/交接/验收。

# 项目归档索引

v0.5.2 于 2026-10-07 结项：[阶段归档](history/2026-10-07/v0.5.2/README.md) · [正式版](../releases/v0.5.2/README.md)。

Flash固化与上电自启于2026-10-05结项，发布v0.5.0：[结项归档](history/2026-10-05/Flash固化与上电自启/README.md) · [正式版本](../releases/v0.5.0/README.md)。

系统稳定性增强已于2026-10-05结项，发布v0.4.0：[结项归档](history/2026-10-05/系统稳定性增强/README.md) · [完成计划](系统稳定性分阶段修改计划.md) · [正式产物](../releases/v0.4.0/README.md)。下方阶段条目保留历史背景。

目录整理（2026-10-05）：原docx并入docs；[文档入口](README.md) · [诊断归档](../diagnostics/README.md) · [旧本地结果与迁移记录](../diagnostics/history/2026-10-05/README.md)。课程来源保留于[HDMI_AUDIO_SOURCES.md](HDMI_AUDIO_SOURCES.md)。

更新：2026-10-05。R2 HDMI音频计划已获S9验收并发布v0.3.0；SD恢复问题按用户要求延期且暂不修改。历史EDID仍取消，原归档保留。

- [Git回退与R2重规划归档](history/2026-10-04/HDMI音频升级/方案重规划/README.md)
- [HDMI音频当前阶段计划](HDMI音频分阶段修改计划.md)
- [S0固定候选和验收说明](../releases/v0.3.0/v0.3.0-s0-local.1/README.md)
- [S1固定候选和验收说明](../releases/v0.3.0/v0.3.0-s1-local.1/README.md)
- [S1开始前交接快照](history/2026-10-04/HDMI音频升级/HANDOFF_before_S1.md)
- [音频升级开始前交接快照](history/2026-10-04/HDMI音频升级/HANDOFF_before_S0.md)

音频升级已结项，正式产物沿用S9固定bit。

- [R2结项归档](history/2026-10-05/HDMI音频升级/README.md)
- [v0.3.0正式版本](../releases/v0.3.0/README.md)
- [延期SD问题分析](diagnostics/s9_sd_recovery/analysis.md)

- [项目说明](../README.md)
- [当前交接](../HANDOFF.md)
- [中文版本说明与固定产物](../releases/v0.2.0/README.md)
- [验证边界](VALIDATION_STATUS.md)
- [合并审核说明](history/2026-10-04/V0_2_0_MERGE_REVIEW.md)
- [版本演进](../CHANGELOG.md)
- [模式功能历史](history/2026-10-04/MODE_ARCHIVE.md)
- [10月4日早期归档](history/2026-10-04/README.md)
- [10月3日归档](history/2026-10-03/README.md)

v0.1.8为缓冲所有权版本；v0.1.9为数码管面板模块化版本；v0.2.0为拨码与新按键版本。历史原文中的“当前”“待验收”和完整回归结论，均以当前交接和验证说明为准。

- [进入S3前交接](history/2026-10-05/系统稳定性增强/HANDOFF_before_S3.md)。v0.4.0仍进行中，最终完成归档未执行。

- [进入S4前交接](history/2026-10-05/系统稳定性增强/HANDOFF_S3_board_accepted.md)
- [S4本地候选及证据](../releases/v0.4.0/v0.4.0-s4-local.1/README.md)（已上板通过，整体尚未结项）

- [S4验收后交接](history/2026-10-05/系统稳定性增强/HANDOFF_S4_board_accepted.md)
- [S5候选及证据](../releases/v0.4.0/v0.4.0-s5-local.1/README.md)（已上板通过，整体尚未结项）

- [进入S6前交接](history/2026-10-05/系统稳定性增强/HANDOFF_before_S6.md)
- [S6本地全回归与最终验收入口](../releases/v0.4.0/v0.4.0-s6-local.1/README.md)（已整体验收并结项）
# v0.5.1 时序收敛与 Flash 启动回归于 2026-10-06 结项：用户确认 S5 上板通过并明确跳过 S6。[结项归档](history/2026-10-06/v0.5.1/README.md) · [正式版本](../releases/v0.5.1/README.md)。

[S2 日志验收更正与原文存档](history/2026-10-07/v0.5.4/S2_log_correction.md)，过程记录，未结项。

[S2修正版板测通过](history/2026-10-07/v0.5.4/S2_board_validation.md) · [S3本地交付记录](history/2026-10-07/v0.5.4/S3_local_summary.md)，S3待上板，v0.5.4未结项。

[S3首图花屏调查](history/2026-10-07/v0.5.4/S3_board_failure.md)：local.1板测失败，S2回退正常，未结项。

S3调查进展：对照bit用户确认正常，local.2编译期关闭版本待上板，工作区未提交。见[故障与修订记录](history/2026-10-07/v0.5.4/S3_board_failure.md)。

[S3 local.2已上板验收](history/2026-10-07/v0.5.4/S3_board_validation.md)，原始附件归档；S4/S5待实施，v0.5.4未结项。
