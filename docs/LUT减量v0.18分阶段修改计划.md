# v0.18.0 LUT 减量分阶段计划（可见行为不变）

状态：S0 计划已确认（2026-10-20），基线 main 361d1c5 / v0.17.0（mountain_attempt34_s3，15840 LUT），分支 feature/lut-optimization-v018，标签 v0.18.0-plan.1。S1 board.1 通过（15173 LUT，−667；批3 解码器/SD 字节计数收窄已放弃）。

## Context

v0.17.0 正式 bit（mountain_attempt34_s3）物理 15840 LUT / 19600（80.8%），BRAM9k 52/64，BRAM32k 2/16，DSP 26/29。v0.16.0 做完 S1/S2（-1212），S3（批8–11）未做；v0.17.0 场景层又 +1650。目标：可见行为不变，压到 ≤14000（约 -1800），为后续功能（免复位换卡、片上生成 T、答题模式）留余量、改善时序。

判据沿用 `diagnostics/lut_opt/LUT_RECORD.md`：**完整 TD 物理全设计 LUT（lut+ripple）**；单批 ±100～150 为噪声，按累计判断；Setup/Hold 非负，否则定点修或撤回。所有估算为读码手算、未综合。

用户已确认：删 case 字库；扫描表去数据字段同步清零并改分布式 RAM；3 阶段、每阶段一个 local 候选上板。

## 热点（attempt34_s3 物理层次）

scanner 1776 ｜ hazard_layer 1574 ｜ bridge 自身 ≈978（实为 `top_tf_hdmi_audio.v:562-614` 纯组合 OSD 叠加链 ring→param→scroll→timestamp→band→scene 被吸进 `rgb_q`）｜ file_streamer×2 1422 ｜ bmp_header_check×2 937 ｜ mode_key_control 486 ｜ audio_ring_levels 395 ｜ scene_osd 374。

## Git / 目录（遵循 执行规则.md）

- 原目录 `feature/lut-optimization-v018`（基于 main / v0.17.0），不建 worktree；未跟踪素材（tools/PIC*、Photo、board_samples、Qhc.wav、问题小记录.txt）不入提交。
- 计划落盘 `docs/LUT减量v0.18分阶段修改计划.md`，标签 `v0.18.0-plan.1`；候选 `v0.18.0-sN-local.N`，`v0.18.0-sN-board.N`，结项 `v0.18.0`。
- 等价台沿用 `diagnostics/lut_opt/` 模式（`*_v017.v` 冻结旧模块 + `tb_batchN_equiv.sv` + `run_batchN.ps1` + 变异体）；构建 `diagnostics/output/lut18_attemptNN`；记录续写 LUT_RECORD.md 新节。
- 构建：`diagnostics/run_td_build.ps1 -HighFanoutOptimization -PlacementStrategy 5`，约束不变；审计用 td_commands_prompt.exe。

## S1 低风险、逐位/逐周期等价（预计 -700～-1000）

- 批1 视频小项
  - 删 case 字库：`osd/osd_font_cn_16x16.v` 去实例，`osd/scroll_text_overlay.v:105` 改 `font_valid ? font_data : 0`，删 mixed_char 死逻辑（:73-85）；改 tb_m5_scroll_font 回退用例。（-120～200）
  - 7 份 `osd/osd_pixel_position` 合为 top 中 1 份，共享 line_y/frame_start。（-70～90）
- 批2 hazard_layer（`scene/hazard_layer.v`）
  - hash8：hc（:252）先选输入后算一次；h00/h10/h01/h11 共享 ncx*73、ncy*151（+73/+151 增量），不进 DSP。（-60～100）
  - 可变移位（:267-270）改定值移位 4:1；shake `sr` 去异步复位（:493）。（-40～80）
  - 等价：tb_m5_rain_top / hazard 逐像素对旧模块。
- 批3 SD 小项
  - `fat32_pcm_stream.v` loop_count 32 位→1 位标志（唯一使用 `sd_card_bmp.v:152` 的 !=0）。（-40）
  - `fat32_file_streamer.v` cluster 寄存/比较收窄到 28 位（:216-218）。（-30～60）
  - 批3 遗留：`bmp24_decoder.v` row_payload/row_last 13 位、pixel_y 递减；`image_scale_nearest.v` inside 改边沿标志；`sd_card_cmd.v:87` byte_cnt 10 位；确认 SD 写路径未被裁则加只读参数删 S_WRITE*/CMD24。（-100～170）
- 批4 按键共享 1ms 节拍（原批8）：`SD/mode_key_control.v`、`key_press_debounce.v`、`adjust_key_gestures` 共用 17 位预分频，计数位 ~169→~70，计时 ±1ms；按键专项改时间窗断言。（-120～160）
- S1 门槛：沿用 v0.16 S1 回归集（21 项基础、调节、缩放、四宫格、生产顶层、SDRAM 预览/完整系统、42 项 FAT32 读取）+ v0.17 场景回归（run_m1/m3/m4/m5、18 项 m5r）；时序审计；固定 `releases/v0.18.0/s1-local.1`，板测按 v0.17.0 BOARD_VALIDATION（含 R2 雨丝、按键手感）。

## S2 结构复用与存储迁移（预计 -800～-1200，每项单独 TD）

- 批5 单 header checker：`fat32_bmp_reader.v:177` preflight 与 `bmp24_decoder.v:68` 的 bmp_header_check 分时共用（HEADER_WAIT / READ_FILE 互斥），寄存的 loading 标志选择 valid/byte/offset/reset，输出经 `bmp_scale_stream` 上引；保持 HEADER_OFFSET_LOOKAHEAD。（-420～470，-2 DSP）风险：offset→file_len.ce 曾 -1.009ns。
- 批6 扫描表（`SD/fat32_volume_scanner.v:114-126`）
  - 6a 同步清零只保留 resource_valid/bgm_found/snd_found/font_found/text_found 等标志，数据字段去掉；改 `diagnostics/pcm_audio/tb_audio_scan.sv:45` 为“未找到即不被使用”。依据：`sd_card_bmp.v:104` parser_rst 每次扫描前在 SC_RESET 复位 8 拍。（-200～450）
  - 6b 表改分布式 RAM（11 槽同拍同源写，单写口）：音频 5 项一块按 audio_slot 读；图片+FONT/TEXT 一块，读地址按 reader 状态寄存选择，替代 reader 两个 64 位 4:1 与 41 位选择器（`fat32_bmp_reader.v:88-95,239`）。（约 -250）
- 批7 hazard `tterm` 124×24 常数表（:52-180，三处调用 :455-457）改同步 BRAM（C3 地址已就绪，延迟不变）。（-100～150）
- 批8 音频环
  - `audio_ring_rom` 9216×12 由 21 BRAM9k 改约 4 BRAM32k（释放 BRAM9k，去级联选择）。（-40～80）
  - `audio_vis/audio_ring_levels.v` 两个 96×5 异步读改同步 BRAM：update_heights 用 copy_index 提前一拍；display_heights 由 ROM 提前一像素寻址。（-150～250）
- 批9 SD 选择器：reader cand_*/selected_* 合一 4:1（批6b 后视剩余再定）；scanner 5 路 11 字节名比较改“首字母 kind + 位置查表 + 单 8 位比较”。（-150～220）风险：候选检查路径（曾 -0.165ns）、sector_byte→audio_match（曾 -0.116ns），选择信号一律寄存。
- S2 门槛：S1 全部 + 42 项 FAT32 读取 ByteGap 0/2、BGM+图片并发、四卡换卡/预警、真实 PCM；`s2-local.1` 板测重点：读卡、换卡重扫、音乐、字幕/FONT。

## S3 OSD 叠加链合并（预计 -300～-500，需逐像素）

- 批10 5 份 `osd_font_5x7`（adjust/status/scroll/timestamp/scene）合为 FONT BRAM32k 空闲槽或单份共享，提前寻址；先证明各 OSD 的 x 在 de 内逐拍递增。
- 批11 叠加链改“每像素叠加码 + 暗化次数 + 单一终选”，scene_osd 区域标志由 lead_x 提前寄存，与 osd_alpha_band 共享区域比较；注意 scene 模式两层暗化叠加。
- 验证：生产顶层逐帧像素转储旧新对比（各模式、各 OSD 状态、场景阶段 1–N、预警）。
- `s3-local.1` 板测：全部 OSD 显示核对、Flash 冷启动、长时间运行。

## 不做

改时钟/引脚/约束；删除调试显示（数码管/UART 内容）；合并图片与 PCM streamer（并发需要）；attempt43 已试过且失败的 MBR 单 LBA 与 FAT index[8:2] 改法。

## 结项

S3 板测通过后复用原 bit 发布 v0.18.0（逐字节核对，不重建），更新 README/CHANGELOG/HANDOFF/VALIDATION_STATUS，归档 `docs/history/<日期>/lut-optimization-v018/`，合并 main 并推送。

## 风险

- 时序：Hold 余量曾仅 3–4ps；Slice>90% 时 TD 跳过 Hold 修复。每批复核，负值定点修或撤回。
- 布局敏感：无关改动也可能使 SD 扫描候选路径失败，SD 批次单独 TD。
- TD 曾在布局后崩溃（attempt07/08），复现则以小网表变化绕开并记录。
- 改端口后用脚本扫所有测试台实例（TFMPC 警告会被回归判失败）；BRAM 初值 X 时测试台用 `===`。
