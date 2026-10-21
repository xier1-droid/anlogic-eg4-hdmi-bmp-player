# v0.19.0 去掉圆形音频可视化归档（2026-10-21）

[阶段计划](阶段修改计划.md) · [最终交接](HANDOFF.md) · [发布说明](RELEASE_NOTES.md) · [正式文件与验证](../../../../releases/v0.19.0/README.md) · [LUT 记录](../../../../diagnostics/lut_opt19/LUT_RECORD.md)。

基线 v0.18.0（15173 LUT）。用户决定只去掉圆形音频可视化：`AUDIO_VIS_ENABLE=0` 剪掉柱高计算和 ROM（21 个 BRAM9k），并给音频流模块加寄存的 error_flag，消除只剩 +0.031 ns 余量的 SD 域路径。14489 LUT（−684）、BRAM9k 30，Setup +0.155 ns、Hold +0.003 ns（布局策略 5；策略 3 在未改动的 u_cache_control 内部路径上 Setup −0.214 ns）。板测“功能正常”（整体反馈），正式版复用 s1-local.1 原 bit。方案书加分项 5 失效。等价台、隔离构建脚本与冻结模块保留在 diagnostics/lut_opt19。
