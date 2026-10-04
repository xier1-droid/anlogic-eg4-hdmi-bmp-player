# 文档入口

原`docx`为笔误，内容已统一合并到本目录；按日期保存的历史记录合并保留，无覆盖。

| 内容 | 入口 |
|---|---|
| 当前稳定性任务 | [阶段计划](系统稳定性增强分阶段计划.md) · [S0候选](../releases/v0.4.0-stability-s0-local.1/README.md) |
| 当前产品及下载 | [项目README](../README.md) · [v0.3.0正式版本](../releases/v0.3.0/README.md) |
| 验证结论和边界 | [VALIDATION_STATUS.md](VALIDATION_STATUS.md) |
| 已完成阶段计划 | [HDMI音频分阶段修改计划](HDMI音频分阶段修改计划.md) |
| 历史归档 | [ARCHIVE_INDEX.md](ARCHIVE_INDEX.md) · [history](history) |
| 课程来源和改写说明 | [HDMI_AUDIO_SOURCES.md](HDMI_AUDIO_SOURCES.md) |
| 延期问题分析 | [SD恢复分析](diagnostics/s9_sd_recovery/analysis.md)（用户要求暂不修改） |
| 构建/历史测试复现 | [diagnostics入口](../diagnostics/README.md) |

`history`保存历次说明和验收快照；`diagnostics`只保存问题分析及证据。下载文件仍在`releases`，不在文档目录重复保存bit。

## 本次目录整理

原`docx`内容逐文件并入`docs`，相关链接已更新。v0.2.0合并审查移至对应历史日期。已完成版本的测试进入`diagnostics/history/v0.3.0`，构建入口仍为`diagnostics/run_td_build.ps1`，新运行输出统一到`diagnostics/output`。

旧诊断日志、报告及原始输出保存为[local_results.zip](../diagnostics/history/2026-10-05/local_results.zip)，附[归档说明](../diagnostics/history/2026-10-05/README.md)。既有发布bit和生产RTL未改。

## 清理完成

用户已手动删除根目录`_cleanup`，并已确认目录不存在。原reference、合并后空的docx目录树和旧诊断缓存清理完成；需要保留的资料已归档。
