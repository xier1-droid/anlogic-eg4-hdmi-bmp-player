# 构建与诊断归档

稳定性S0入口：`powershell -NoProfile -ExecutionPolicy Bypass -File diagnostics/run_stability_baseline.ps1`，顺序运行八项原回归，汇总到diagnostics/output/stability_s0。工具路径集中在tool_paths.ps1，可设置MODELSIM_BIN、TD_ROOT、PYTHON_EXE；当前探测F:/modelsim/win64、E:/TD、用户Python3。构建支持-TdRoot或TD_ROOT。testbench逻辑未改。新任务SD恢复已获授权，以下延期说明属于v0.3.0边界。

本目录根部只保留构建入口与历史索引；已完成阶段的测试统一归档，新运行结果单独存放。

```text
diagnostics/
  run_td_build.ps1        TD构建入口
  history/
    v0.3.0/              可运行的版本回归脚本、testbench和Python参考
    sd_recovery/         延期SD问题的复现测试，仅存档
    2026-10-04/          早期阶段报告与构建对照
    2026-10-05/          旧本地运行结果压缩包及迁移清单
  output/                新运行缓存和日志（不入Git）
```

- [v0.3.0测试说明](history/v0.3.0/README.md)
- [早期诊断记录](history/2026-10-04/README.md)
- [旧运行结果归档](history/2026-10-05/README.md)
- [SD问题复现存档](history/sd_recovery/README.md)，不表示启动修复
- [正式版本的固定验收证据](../releases/v0.3.0-r2-s9-local.1/README.md)

从项目根目录构建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File diagnostics/run_td_build.ps1 -BuildName manual_build
```

后续构建会更新TD运行目录，不得覆盖releases中的已交付文件。历史测试已适配新路径，仍读取当前生产RTL；复现某个旧版本的原始RTL应先检出相应Git标签，不能把历史脚本与任意后续RTL混用当作原始验收。
