# v0.4.0-stability-s0-local.1

2026-10-05。仅本地候选、待用户上板，未推送GitHub。基线 `e76be02`（main，已验收v0.3.0）；分支 `feature/system-stability-v0.4.0`。S0没有修改生产RTL、TD工程或约束，没有修复SD缺陷。

[下载demo.bit](demo.bit) · [上板清单](BOARD_VALIDATION.md) · [阶段计划](../../docs/系统稳定性增强分阶段计划.md)。新候选629624字节，SHA256 `5827746FC7E289CFD7BA2ADF01ED52B11093922D189FE369627A8A9CD44443E6`。已验收v0.3.0哈希 `14AADBB177378148CB23D9FA31913FC02FEC113EE81DBE5124A5881158EF4BE0` 保持；bitgen时间等元信息可使重建bit不同，仍需候选上板。

## 本地验证

ModelSim SE-64 10.6e，Python3独立参考，八个入口全部通过，编译/仿真零错误零警告：6控制（含74次显示提交）、模式面板、3组异步缓冲、独立PCM、HDMI基础/音频封装、视频对齐、S9媒体/真实PHY/CDC、实际top复位。testbench/FIFO/PLL的行为模型不代替真实SD/SDRAM板级验证。旧缺陷PASS REPRO不在成功回归中。

TD6.2.168116（E:/TD）综合/布局布线/bitgen通过；顶层top、器件EG4S20BG256。资源3327 LUT、2590寄存器、4 BRAM、1 DSP、2 PLL；相对v0.3.0的3301 LUT增加26，其余相同，未改RTL。Setup WNS -6.565ns / TNS -294.439ns，Hold +0.004ns，64个Setup违例，STA覆盖99.86%；全局未收敛。

构建报告仍含原工程历史SDC路径字符串，生成demo.prj及settings.cfg已指向当前工作区，约束内容与v0.3.0 SHA256一致；原始报告作为证据不改写。TD编译顺序重复警告、原有IO/时序限制保留，不宣称TD零警告。

## 复现及证据

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File diagnostics/run_stability_baseline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File diagnostics/run_td_build.ps1 -BuildName stability_s0_local1 -TdRoot E:/TD
```

工具可用MODELSIM_BIN、TD_ROOT、PYTHON_EXE指定；测试结果写diagnostics/output，构建只写TD运行目录，不覆盖本目录。freeze_stability_s0.ps1为首次固化工具，交付后不要再次对同一release运行；新构建使用新local修订目录和标签。

evidence包含八项汇总、各仿真/编译/独立参考数据、TD日志及配置；source_inventory.json记录全部user_source和活动工程哈希，SHA256.json记录本候选文件校验。固定源码由本地标签对应提交保存。

当前已知复位卡0、扫描拔卡卡2、密集翻图复位卡0仍在；恢复用[v0.3.0](../v0.3.0/demo.bit)。用户上板确认前不进入S1、不创建board标签、不上传候选。不做任务完成归档；最终验收后按计划归档文档。
