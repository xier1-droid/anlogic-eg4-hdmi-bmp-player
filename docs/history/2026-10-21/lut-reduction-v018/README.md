# v0.18.0 LUT 减量归档（2026-10-21）

[阶段计划](阶段修改计划.md) · [最终交接](HANDOFF.md) · [发布说明](RELEASE_NOTES.md) · [正式文件与验证](../../../../releases/v0.18.0/README.md) · [LUT 记录](../../../../diagnostics/lut_opt18/LUT_RECORD.md)。

基线 v0.17.0（15840 LUT）。S1 删 case 字库、合并位置计数、hazard 哈希共享与定值移位、旁白标志 1 位、按键共用 1 ms 节拍，15173 LUT（−667）、24 DSP，Setup +0.122 ns、Hold +0.021 ns，板测通过。S2 批5（共用 header checker）、批6a（扫描表只清标志）、批7（hazard 常数表 BRAM）、批8（音频环 BRAM）模块层面逐周期等价，但全设计物理 LUT 无稳定收益或时序失败，全部撤回；按用户决定按 S1 结项，正式版复用 s1-local.1 原 bit。等价台与冻结模块保留在 diagnostics/lut_opt18。
