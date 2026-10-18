# v0.17.0 M4 local.1 候选：场景模式、SND1–4 分阶段音频与音画同步转场

- 基线：v0.16.0（main 1818adc）。上一候选：m3-local.3（已板测通过，v0.17.0-m3-board.2）。回退：releases/v0.17.0/m3-local.3/demo.bit，或 releases/v0.16.0/demo.bit。分支 feature/mountain-escape-classroom。
- 构建 diagnostics/output/mountain_attempt30_s3：HighFanoutOptimization、strategy 3、opt_timing high、post_place_opt high（与 m3-local.3 相同）。
- 上板文件：本目录 demo.bit（670364 字节，与构建产物逐字节一致）。构建用的全部输入与仓库当前源码逐字节一致，见 MANIFEST.md。

## 相对 m3-local.3 的变化

1. **场景模式入口与按键**（用户 2026-10-18 确定；拨码四个 mode 都已占用）：
   - mode 0 下长按 KEY4 1 秒进入/退出场景模式；短按 KEY4 切换 MAN/AUTO，**改为松手时生效**（原为按下时）。mode 3 的 KEY4 不变。
   - 场景模式内 KEY2 下一阶段（4→1 循环），长按 2 秒重扫；KEY1 留给 M5 预警模式，不响应。
   - 场景模式在 mode 1/2/3 下保持，各 mode 按键不变。
2. **scenario_fsm 替换 M3 临时 t 源**：阶段等于当前显示的图片（复用原翻图请求、转场与显示提交）；t 每播放 1600 个 SD 音频样本加 1，到 239 停住，没有音频文件时每 2 帧加 1。图层**只在场景模式下打开**（M3 是一直打开）。AUTO 打开时，本阶段推演到头且旁白读完一遍后才进入下一阶段。临时 t 源保留，顶层参数 `HAZARD_TEST_SOURCE=1` 时恢复 M3 行为。
3. **SND1–4 分阶段音频**：扫描器新增 SND1–4 槽；场景模式下播放当前阶段的 SNDn，该阶段没有 SNDn 时回退 BGM.PCM；普通图片模式仍播放 BGM。换文件时先停掉流和播放器，再从新文件开头播放。
4. **fade_mute**：`pcm_master_volume` 新增输入，静音时增益以每样本 14 斜坡降到 0、解除后以 14 回到音量目标（单程约 4682 样本、98 ms）；普通调音量仍为 256。场景模式下转场期间静音；进出场景模式和每次阶段切换都保持静音，直到新文件开始播放（或 30 帧超时），期间 t 不走，所以旁白和画面从同一时刻开始。
5. **M2 工具音频输出**：`make_scene_pack.py --audio` 按 scene.yaml 的 `sound` / `narration` 生成 SND1–4.PCM（`tools/scene_audio.py`，旁白用 Windows 中文语音合成，放在样本 t×1600 处）。四张 v3 卡已写好旁白并生成到各卡 `out/sd/`；PIC1–4 与 m3-local.3 板测卡逐字节相同。

## 生产文件改动（相对 m3-local.3）

- 新增 `scene/scenario_fsm.v`。
- `SD/fat32_volume_scanner.v`（SND 槽、audio_slot 选择、提前结束条件）、`SD/fat32_bmp_reader.v`（端口透传）、`SD/sd_card_bmp.v`（场景模式、按阶段选文件与换文件握手、AUTO 等待阶段结束）、`SD/mode_key_control.v`（KEY4 短按/长按、场景模式）、`adjust/pcm_master_volume.v`（fade_mute）、`top_tf_hdmi_audio.v`（scenario_fsm 接线、fade_mute、HAZARD_TEST_SOURCE 默认 0）、`TD_project/demo.al`（加入 scenario_fsm.v）。
- 时钟、引脚、约束不变。sources/ 保存相对 v0.16.0 的全部改动文件。

## 资源/时序

| | m3-local.3（attempt29_s3） | **m4-local.1（attempt30_s3）** |
|---|---|---|
| LUT | 14111（72.0%） | **14740（75.2%，+629）** |
| 寄存器 | 8004 | 8372 |
| BRAM9k | 52 | 52 |
| DSP | 26 | 26 |
| Setup / Hold | +0.126 / +0.024 ns | **+0.101 / +0.024 ns** |

- 0 违例端点，构建日志 0 条 ERROR。最紧的是 sd_card_clk（+0.101 ns）；video_clk +2.725 ns。
- 时序审计 14 类的计数与 m3-local.3 完全相同（dangling 节点名单随综合变化，数量相同）。
- 同时构建了 strategy 4（attempt30_s4），时序与资源相同，bit 与 attempt30_s3 逐字节相同。
- LUT 距 85% 目标（约 16660）还有约 1900，M5 仍需注意。

## 验证（validation/）

- `m4_scene2`（run_m4.ps1）：
  - `tb_m4_fsm`：63 项检查——每次提交重新开始阶段与类型、1600/800/400 样本一步（1×/2×/4×）、无音频时每 2 帧一步、停在 239 与 stage_done、只在场景模式开图层、进出场景模式与提交的静音保持（由音频重新开始解除或 30 帧超时）、静音期间 t 不走、场景模式下转场静音。
  - `tb_m4_fade`：18087 个被接受样本逐个检查：增益步长（fade ≤14、调音量 ≤256）、单调无跳变、输出等于输入×增益>>16；全程静音和恢复各 4680–4684 个样本；中途反转、淡入时调音量、静音中选 0 档。
  - `tb_m4_keys`：KEY4 短按松手切 AUTO、长按 1 秒切场景模式且松手不再动作、场景模式 KEY1 不响应、KEY2 与长按重扫照常、mode 1–3 和跨 mode 按住不切换、禁用时无事件。
  - `tb_m4_scanner`（字节间隔 0 和 2）：SND1–4 各自的槽、只有全部找到才提前结束、第二目录簇、部分文件、重名取第一个、近似文件名和属性、重扫清表、仅 BGM。原 `tb_audio_scan`（0 和 2）通过。
  - `tb_m4_scene_audio`：生产 sd_card_bmp + 模拟 FAT 卡（PIC1–4、BGM、SND1/2/4，没有 SND3），10 次播放会话逐个按首样本识别文件并逐样本比对：普通模式 BGM、进场景 SND1、KEY2 依次 SND2 → BGM（SND3 回退）→ SND4、KEY1 无效、AUTO 等 stage_done 才走、场景模式重扫回 SND1、退出回 BGM 且 KEY1 恢复、无 SND 卡换阶段不重开 BGM；换文件只发生在流停止后；扫描不早于音频停止；无欠载/溢出。
  - `tb_m4_top`：生产顶层 13 项接线检查。
  - 变异体 9 个（fade 步长、样本步长、静音解除条件、静音期间冻结 t、SND 文件名、扫描提前结束、场景模式 KEY1、AUTO 按下沿、SND 回退）全部检出。
- `m4_m3v3_1`（run_m3.ps1）：四张卡 16 张图与 `out/sd` 逐字节一致；1,228,800 向量、192 帧逐像素、链路、读卡类型、`tb_m3_top`（M3 图层强制打开）与 5 个变异体，全部通过。
- `m4r2_*`（run_m3_regression.ps1，18 项）：全部通过；生产顶层 336271 像素/1148 样本/43 警告、预览 165 帧/105578 刷新/26 警告、完整系统 183705600 转场像素/32 警告、PCM 9279/9279（含 tb_pcm_preview_rescan）、video_delay 300000 拍，与 m3-local.3 逐项相同。首轮 m4r1 因 history/v0.3.0/tb_mode_key_control.sv 未声明新端口 scene_mode 而 four_bank 一项无法加载，补声明后整套重跑为 m4r2
- 另跑 `media_adjust/run_unit.ps1`（含 tb_volume、tb_adjust_keys）6 项通过；`fat32/run_core.ps1` 42 个用例全部 PASS，日志中的 6 条警告是测试台未连 bmp24_decoder 的 M1 新端口，与本次无关（v0.17.0 M1 起即如此）。
- 旁白时刻：四张卡 36 句，每句在 SND 文件中的开口位置都在 t×1600 后 21 ms 内，之前为静音。

## 已知限制

- 仅本地仿真与 TD 通过，尚未上板。
- 推演速度固定 1×（scenario_fsm 有 speed 输入），速度调节项在 M5 加入参数条；里程碑板测项“速度切换生效”移到 M5。
- 标题、字幕、图例、预警模式和 OSD 布局调整属于 M5；场景模式下左上状态栏和音频环仍会压住部分画面。
- 重新提交同一张图（例如只有一张图的卡上按 KEY2，未单独测试）时 t 重新开始，但 SND 文件不换、不从头播放（30 帧后解除静音），旁白会与画面错开。四图场景卡不会出现这种情况。
- 旁白为 TTS 合成，用于验证时间关系，正式配音可在 scene.yaml 中换成 `sound:` 录音。语音合成结果依赖本机语音引擎，不保证逐字节可复现。

## 板测

按 BOARD_VALIDATION.md 进行，请反馈候选名及实际通过/异常的项目。用户确认前不建 board 标签、不进入 M5。
