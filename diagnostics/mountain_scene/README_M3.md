# v0.17.0 M3 local.2 候选：hazard_layer 灾害图层（v2 效果、河谷村卡）

- 基线：v0.16.0（main 1818adc）。上一阶段：m1-local.1（已板测通过，v0.17.0-m1-board.1）。取代 m3-local.1（未上板）。回退：releases/v0.17.0/m1-local.1/demo.bit，或 releases/v0.16.0/demo.bit。分支 feature/mountain-escape-classroom。
- 构建 diagnostics/output/mountain_attempt17，选项与 M1、local.1 相同（HighFanoutOptimization、strategy 5、opt_timing high、post_place_opt high）；约束、时钟、引脚未改。
- 上板文件：本目录 demo.bit（664544 字节，与构建产物逐字节一致）。板测卡换为河谷村 `tools/scenes/valley_village/out/sd/PIC1–4.BMP`。

## 相对 local.1 的变化（用户 2026-10-16 提出）

1. **切图时 t 清零**：`hazard_test_source` 接入显示提交脉冲（`audio_update`，转场和换曲用的也是它）。每次提交（包括重新显示同一张图），下一个 frame_start 时 t=0、stage 换成新图。
2. **底图**：改用用户以生图 AI 生成的虚构河谷村（`tools/scenes/valley_village/`，缩放后的 640×480 底图经用户同意入库，原图 tools/Photo 不入库）。四个阶段的标注各自画在对应那张图上。
3. **v2 图层效果**（规则见 tools/scenes/README.md，Python 参考模型 `make_scene_pack.hazard_layer_model`）：
   - 阶段 1：斜向雨丝下落，t 越大越密；
   - 阶段 2：近黑裂缝，尖端亮黄闪烁；
   - 阶段 3：浑黄泥水，淹没越久越深（3 档），波纹向下游移动，前沿浪花；
   - 阶段 4：绿色路线，亮色虚线向避险点流动，前沿白/亮绿闪烁。
   - 消隐期一律原色。

## 生产文件改动（相对 v0.16.0，见 sources/）

- `scene/hazard_layer.v`：仍是 2 拍。第 1 级把像素归为"原色 / 3/4 / 1/2 / 1/4 / 常色"五种形式中的一种，并选出颜色项；第 2 级每通道一次 8 位加法。内部按 de 和 frame_start 计数 x/y，用于雨丝。不用 DSP、不用 BRAM。
- `scene/hazard_test_source.v`：临时驱动，切图清零；由顶层参数 `HAZARD_TEST_SOURCE` 隔离，M4 换成 scenario_fsm。
- `SD/video_delay.v`：参数 `SYNC_EXTRA`（默认 0，行为不变），端口与 v0.16.0 相同。
- `top_tf_hdmi_audio.v`：32 位读出经 hazard_layer 再进入亮度/对比度；缩略图旁路；图层的 de 取 read_en 延迟 2 拍（与 video_delay 输出像素同拍）。
- `TD_project/demo.al`：加入两个新文件。
- 另含 M1 的 5 个加载链路文件（相对 v0.16.0 的完整改动集）。

## 资源/时序

- 14652 LUT（74.8%；local.1 14608，M1 14224）、8408 寄存器、56 BRAM9K、0 BRAM32K、13 DSP。
- 布局后 hazard_layer 占 276 LUT（209 LUT + 67 进位链；local.1 为 126），测试源 30。
- Setup +0.116ns、Hold +0.014ns，0 违例端点；video_clk 域 Setup 裕量 +1.400ns（local.1 为 +1.941ns）。时序审计 14 类与 local.1 逐项相同；构建日志 0 条 ERROR。

## 构建过程（如实记录）

本轮共启动 16 次构建（attempt04–19，均在 diagnostics/output，未入发布），逐次结果：

| 结果 | 次数 | attempt（布局策略） |
|---|---|---|
| TD 在 phy 的 Hold Fix 阶段内部崩溃（minidump），崩溃前只剩 1 条约 −11ps 的 hold 待修 | 6 | 04/05/06（5）、08（2）、11（7）、15（10） |
| 跑完 bitgen，但日志含 `PHY-8103 ERROR: x_offset.size() <= 0`（布局优化阶段）；构建脚本把任何 ERROR 判为失败 | 5 | 10（6）、12（8）、13（9）、18（6）、19（9） |
| 无 ERROR 但 Setup 为负（−0.082ns） | 2 | 07（3）、09（4） |
| 源码修正后中途停止 | 2 | 14（1）、16（11） |
| **完全通过** | 1 | **17（5），即本候选** |

- 崩溃时机器空闲虚拟内存约 11GB，与 M1 那次内存耗尽无关；同一输入、同一策略重跑也会崩溃（04/05/06），是工具在该布局下的问题，没有找到确定的触发条件。
- attempt04–16 使用 de_pix 版源码（见下），attempt17–19 使用最终源码。

## 验证（validation/）

- `m3v2_hazard4`（run_m3.ps1，河谷村卡）：
  - 重新生成场景包，PIC1–4 与 `tools/scenes/valley_village/out/sd` 逐字节一致；24 张 expected PNG 与参考模型逐像素一致。
  - `tb_m3_hazard_sweep`：每阶段遍历 T 0..255 × t_now 0..255（262144 个向量），以 256 行帧送入，同时检查图层自身的 x/y；rgb、alert、frame_cnt、enable、thumbnail 随机。
  - `tb_m3_hazard_card`：52 帧 640×480（4 张图 × t=0/120/239 × frame_cnt 3F/00，t=160 下 5 种帧计数以覆盖雨丝、波纹、虚线运动和闪烁相位，enable=0、缩略图旁路），共 15974400 个像素逐一比对。
  - `tb_m3_chain`：以 v0.16.0 video_delay 为参照，read_en 相同，同步晚 2 拍逐拍一致，图层 de 与参照 de 一致，x/y 与参照光栅一致，含雨丝帧和第二次复位。
  - `tb_m3_test_source`：2000 帧，覆盖换图、同图重显、提交与 frame_start 同拍。
  - `tb_m3_top`：生产顶层，从 32 位读出到亮度/对比度输出，含 40 行雨丝（检查 x/y 与 adjust_x/adjust_y）、4 个阶段、缩略图、24 位 T=FF、首图前黑屏。
  - 变异体：前沿宽度、雨丝长度、闪烁取位、SYNC_EXTRA=1，四个都被检出。
- 受影响回归 `m3v2r2`（run_m3_regression.ps1，18 项）全部通过。生产顶层（336271 像素/1148 样本/43 警告）、预览（165 帧/105578 刷新/26 警告）、完整系统（591 帧/365203 刷新/183705600 转场像素/32 警告）、PCM 9279/9279 样本，与 M1 逐项相同；video_delay 默认参数与优化前参照 300000 拍逐拍一致。
- 过程记录：第一轮回归 m3v2r1 的 four_bank 基础回归失败——v0.3.0 的 tb_hdmi_s6_phy 实例化 video_delay，新增的 de_pix 端口未连接，产生 2 条警告。已把 de 的生成移到顶层、恢复 video_delay 端口（提交 f3696d8），m3v2r1 作废。

## 已知限制

- 仅本地仿真与 TD 通过，尚未上板。
- t 由临时测试源驱动，没有按键或音频控制；M4 由 scenario_fsm 实现。
- 标题、字幕、图例等 OSD 布局已与用户确认，属于 M4/M5，本候选画面上仍是原有 OSD（左上状态栏和音频环会压住部分灾害区域）。
- TD 在本设计上不稳定（见"构建过程"）。后续里程碑构建可能需要多试几个布局策略。
- `lut_reduction/run_batch2.ps1`、`bmp_decoder/run_sim.ps1` 的既有问题同 local.1，未计入。

## 板测

按 BOARD_VALIDATION.md 第 1–11 项进行，请反馈候选名及实际通过/异常的项目。用户确认前不建 board 标签、不进入 M4。
