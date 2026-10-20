# 当前交接：v0.18.0 正式发布，LUT 减量按 S1 结项（2026-10-21）

- 当前任务：无进行中任务。v0.18.0 已发布（releases/v0.18.0，复用 s1-local.1 原 bit 670364 字节，标签 v0.18.0），feature/lut-optimization-v018 合并到 main 并推送。
- 已完成：S1（15840→15173 LUT，−667，24 DSP，Setup +0.122 / Hold +0.021 ns），板测通过。S2 批5/6a/7/8 在模块层面逐周期等价，但全设计物理 LUT 无稳定收益（−55 布线失败、−20、−2、批8 时序通过时 +22），按用户决定全部撤回、不做 S3。归档 docs/history/2026-10-21/lut-reduction-v018/。
- 卡住的问题：无。遗留：无 FONT.BIN 的卡中文字幕空白（用户已接受）；雨丝曾一度不显示（v0.17.0 遗留，未复现）；离线计算 T 的合规性待官方答复。
- 下一步计划：等待用户的新任务。LUT 77.4%，后续功能余量约 1500 LUT 到 85%。若需要 BRAM9k 余量，批8（音频环改 BRAM，释放 19 个 BRAM9k）的 diff 与等价台可直接复用，但需重新收敛时序。
- 踩过的坑：
  - 读码估算的 LUT 收益多数不成立：TD 综合已把常数表（hazard tterm）、同步清零（扫描表）、未用输出（header checker 的大部分）化简掉；改前先看综合门级报告（demo_gate.area）里该模块的实际 LUT。
  - 全设计物理 LUT 有 ±100～200 的布局噪声，主要落在 u_media_hdmi_audio_bridge（吸收上游组合叠加链）；模块层面 −276 的改动在物理全设计上可以变成 +22。判断收益时同时看综合总数与物理总数。
  - SD 域（sd_card_clk）多条与改动无关的路径对布局敏感：decoder pixel_offset→blue.ce、scanner resource*_size.ce、thumb_writer FIFO→received.ce 都曾因视频域或无关改动转负。
  - 等价台只比输出时可能漏检只在部分条件下可见的内部变化（hazard hc），已加寄存项逐拍比较；reader/ring 的逐周期 lockstep 台（tb_reader_lockstep、tb_ring_lockstep）可复用。
  - lut_opt/run_batch3.ps1 对 fat32_pcm_stream 的 v0.15 参考已不适用（v0.16 S2 有意多 1 拍）。
  - 本机 Git Bash 无 python，用 scoop 的 python.exe -I；CRLF 文件用 perl 替换时注意 \r\n。

