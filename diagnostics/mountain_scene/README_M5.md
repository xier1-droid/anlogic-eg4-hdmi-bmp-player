# v0.17.0 M5 local.2 候选：卡上字库文本、场景 OSD、预警模式与推演速度

- 基线：v0.16.0（main 1818adc）。上一候选：m5-local.1（板测未通过：雨丝一度不显示、场景模式参数条与右上面板重叠，见 releases/v0.17.0/m5-local.1/BOARD_RESULT.md）；已验收的上一阶段为 m4-local.1（v0.17.0-m4-board.1）。回退：releases/v0.17.0/m4-local.1/demo.bit，或 releases/v0.16.0/demo.bit。分支 feature/mountain-escape-classroom。
- 构建 diagnostics/output/mountain_attempt34_s3：HighFanoutOptimization、strategy 3、opt_timing high、post_place_opt high（与 m4-local.1 相同）。
- 上板文件：本目录 demo.bit（与构建产物逐字节一致）。构建用的全部输入与仓库当前源码逐字节一致，见 MANIFEST.md。

## 相对 m5-local.1 的修订

1. **参数条位置**：场景模式下 mode 1/2 的参数条移到左上（文字 y 8–23、暗底 y 4–27，状态栏在场景模式下隐藏，这一行空着），不再与右上面板（x 348–635、y 28–59）重叠；非场景模式位置不变。
2. **读卡器时序**：扫描时检查候选图片改用寄存后的簇号和大小（晚一拍），把状态译码和 4 选 1 从 32 位范围比较路径中去掉。该路径在 M5 每次构建中都是 sd_card_clk 最差路径，改参数条后 attempt33 又以 -0.165 ns 失败。
3. **雨丝**：用户随后反馈 m4-local.1 有雨、m5-local.1 再测也正常，原因未能复现。新增 tb_m5_rain_top：生产顶层由 scenario_fsm 驱动图层（不强制），雨丝逐像素与模型一致；M4/M5 布线网表中雨丝单元都在。本候选未改雨丝逻辑，板测清单单列雨丝检查。

## 相对 m4-local.1 的变化

1. **FONT.BIN / TEXT.BIN 载入 BRAM32k**：扫描器识别 FONT.BIN、TEXT.BIN；扫描读完 PIC 表头后依次把两个文件（各 ≤4096 字节）流入 `scene/bin_to_bram_loader.v` 的两块 BRAM32k（FONT 2048×16、TEXT 4096×8），之后才报扫描完成。扫描开始时清“已载入”标志，文件完整读完（TEXT 还要求 `"TX"`+版本 1）后置位，像素域两级同步使用。缺文件、超长或魔数错时不置位。
2. **中文字幕改为 BRAM 字库**：原字幕（胆子肥嘟嘟的 FPGA）的汉字在 FONT.BIN 载入后从 BRAM 读取，字符码 0x80+i 读 FONT 第 i 字；BRAM 读延迟一拍，字符按下一像素提前形成地址。没有 FONT.BIN 时回退原 case 字库。工具把原 13 字放在 FONT.BIN 前 13 位，字形与 case 字库逐点相同。
3. **场景 OSD**（新增 `scene/scene_osd.v`，HDMI 前最后一层，不增加像素延迟）：场景模式下右上预警色块（阶段 1–4 蓝/黄/橙/红）、TEXT 段中的阶段标题、进度条（t 每 1 点 1 像素）；左下图例（色块 + 文字）；底部字幕从右边进入、每帧左移 2 像素。左上状态栏（及其暗底）和音频环隐藏，时间戳保留；缩略图模式下不显示。段号与字符码见计划文档 M5 一节和 tools/scenes/README.md。
4. **预警模式**：场景模式、mode 0 下 KEY1 进入/退出。进入时按普通翻图（含转场）跳到最后一张（阶段 4，SND4 循环），已在最后一张则不重新加载；t 固定 239；画面四周 8px 红框与红色色块闪烁（约 1.9Hz）；标题为村名（段 0）、字幕为预警语（段 9）、图例为段 13；KEY2 与 AUTO 不换阶段。退出时停在当前图、t 从 0 重新推演；退出场景模式时一并退出。
5. **推演速度参数项**：场景模式下 mode 1/2 的 KEY4 选择增加 S（B→V→S、C→V→S），KEY1/KEY2 在 1X/2X/4X 间调节，KEY1+KEY2 恢复 1X；参数条在 V 之后显示 `S:1X`。速度经两级同步在帧起点送入 scenario_fsm（1600>>speed 个样本一步）。
6. **数码管**：场景模式下末位显示阶段 1–4，预警模式显示 A；错误码 D/E/F 照常显示。
7. **M2 工具**：`make_scene_pack.py --text` 生成 FONT.BIN/TEXT.BIN 和 OSD 预览 `out/osd/`（`tools/scene_text.py`）。四张 v3 卡写好标题、图例和预警语，字幕默认取旁白；村名为占位。

## 生产文件改动（相对 m4-local.1）

- 新增 `scene/bin_to_bram_loader.v`、`scene/scene_osd.v`。
- `SD/fat32_volume_scanner.v`（FONT/TEXT 目录项）、`SD/fat32_bmp_reader.v`（SCAN_FINISH 下的 FONT/TEXT 载入子状态与标志；local.2 扫描候选寄存一拍）、`SD/sd_card_bmp.v`（预警模式跳转、KEY2/AUTO 保持、端口）、`SD/mode_key_control.v`（KEY1 预警）、`adjust/media_adjust_control.v`（S 项）、`adjust/adjust_osd_overlay.v`（S 显示；local.2 场景模式下移到左上行）
、`osd/scroll_text_overlay.v`（BRAM_FONT）、`scene/scenario_fsm.v`（warn 输入、scene_on/warn_on）、`top_tf_hdmi_audio.v`（接线、数码管、速度同步、音频环与状态栏隐藏）、`TD_project/demo.al`（加入两个新文件）。
- 时钟、引脚、约束不变。sources/ 保存相对 v0.16.0 的全部改动文件。

## 资源/时序

| | m4-local.1（attempt30_s3） | **m5-local.2（attempt34_s3）** |
|---|---|---|
| LUT | 14740（75.2%） | **15840（80.8%，+1100）** |
| 寄存器 | 8372 | 8677 |
| BRAM9k | 52 | 52 |
| BRAM32k | 0 | **2** |
| DSP | 26 | 26 |
| Setup / Hold | +0.101 / +0.024 ns | **+0.143 / +0.003 ns** |

- 0 违例端点，构建日志 0 条 ERROR。Hold 最差 +0.003 ns 在 hdmi_5x_clk 的串行复位释放到 lane_lvds 移位寄存器，与 v0.16.0 基线（+0.003 ns）同一类路径；sd_card_clk Hold +0.054 ns。m5-local.1（attempt32_s3）为 +0.135 / +0.030 ns。
- 第一次构建（attempt31，载入状态并入 5 位主状态）strategy 3/4 为 sd_card_clk -0.387 ns（既有的 PIC 候选簇号比较路径变深），strategy 5 为 -1.517 ns，均不作候选；改为 SCAN_FINISH 的子状态、保持 4 位主状态后 attempt32_s3 通过。
- 时序审计 14 类与 m4-local.1 相同，仅“dangling 节点”由 3 变为 4，新增的是 `u_bin_loader` BRAM32K 的未用输出位 dob[9]。
- LUT 距 85% 目标（约 16660）还有约 840。case 字库仍保留作回退（计划要求按实测决定是否删除）：80.7% 未超目标，本候选不删；删除能省多少 LUT 未单独测量，M6 需要余量时再评估。

## 验证（validation/）

- `m5_text5`（run_m5.ps1，local.2 源码）：
  - `check_scene_text`：1671 项——四张卡 FONT/TEXT 的表头与 14 个描述符、段连续、每个字形与期望字符的渲染（原 13 字等于 case 字库）逐点相同、无重复字形、重复生成逐字节相同；宋体渲染“胆肥嘟的”与原 case 字形相同；17 格标题与 129 个字形被拒绝。
  - `tb_m5_osd`（滑坡卡、地震卡各一遍）：bin_to_bram_loader 经字节口写入卡上 FONT/TEXT，scene_osd 在 640×480 时序下 24 帧、7,679,999 个有效像素与按布局规则写的模型逐像素一致：非场景模式直通、四个阶段的标题/字幕/图例、字幕滚动（换段从头、中途位置）、转义符号与色块、预警红框与色块的两个闪烁相位、段 0/9/13、缺 FONT 或 TEXT、左上暗底取消。滑坡卡 31,644 个字形像素、1,280 个符号像素、5,616 个色块像素、35,328 个红框像素。
  - `tb_m5_scroll_font`：原字幕 BRAM 字库（卡上 FONT.BIN）、无字库回退、case 字库三者 87 帧、27,033,599 个像素逐点相同（59,673 个字形像素），覆盖 13 个原字在每个字内偏移和生产默认文案。
  - `tb_m5_fsm` 19 项：预警下 t 次帧起为 239、进出预警重新开始阶段、1600/800/400 样本一步、中途提速立即生效、scene_on/warn_on 帧起更新。
  - `tb_m5_keys` 35 项：场景模式 mode 0 KEY1 切预警（无上一张事件）、场景外 KEY1 上一张、mode 1 KEY1 不切预警、退出场景模式清预警；B→V→S、C→V→S 只在场景模式、1X/2X/4X 夹紧、同按恢复 1X、S 不动亮度音量、换 mode 离开 S 且速度保留；参数条位置：非场景模式文字与暗底在 y 32–47/28–51、y 16 无内容，场景模式文字与暗底在 y 8–23/4–27、y 30 与 y 40 无内容（local.2 修订）；S 项显示与选中黄色。
  - `tb_m5_scene`：生产 sd_card_bmp + 模拟 FAT 卡，14,788 次 bin 写入与 BRAM 内容逐字节比对；好卡、魔数错、FONT 5000 字节（超长）+TEXT 4096 字节、无 FONT/TEXT、再换回好卡五种扫描的标志；每次重扫标志先清零；bin_wr 只在扫描中。预警：跳到第 4 张并播 SND4 且循环（不重开会话）、KEY2 与 AUTO 不换阶段、KEY1 退出停在原图、在第 4 张进入不重载、退出场景模式一并退出；场景外 KEY1 仍为上一张。5 个播放会话 2,586 个样本逐个比对。
  - `tb_m5_top` 15 项：速度同步到帧起、预警到 FSM（t=239）与 OSD、场景模式音频环关闭与 FONT 地址切换、数码管 4 与 A、HDMI 取 scene_osd 输出、FONT/TEXT 扫描打开。`tb_m4_top` 13 项照常通过。
  - `tb_m5_rain_top`（local.2 新增）：生产顶层，图层由 scenario_fsm 驱动（只强制场景模式、类型表和提交事件），像素 T=FF 只看雨丝；滑坡致因与山洪发生 10 帧 158,720 个有效像素与 hazard_v3 雨丝模型逐点一致，雨丝像素 739 个；非场景模式图层关闭。
  - 变异体 14 个（字幕行偏移、格数比较、描述符地址、滚动步长、左上暗底、提前一字、预警 t、预警随场景模式清零、速度上限、TEXT 魔数、长度上限、预警目标图、预警屏蔽 KEY2、FONT 文件名）全部检出。
- `m5_m4_3`（run_m4.ps1）：M4 全部单元、tb_m4_scene_audio、tb_m4_top 与 9 个变异体通过。tb_m4_scene_audio 中“场景模式 KEY1 不响应”一项已移到 tb_m5_scene（KEY1 现为预警键）。
- `m5_m3v3_2`（run_m3.ps1）：四张卡逐字节一致、向量、逐像素、链路、读卡类型、tb_m3_top 与 5 个变异体全部通过。
- `m5q_m1`（run_m1.ps1）9 项、`m5q2_reader0`/`m5q2_reader2`（fat32/run_reader.ps1，字节间隔 0 和 2）84 个用例：local.2 读卡器修订后全部通过、0 警告。
- `m5_adjust_unit3`（media_adjust/run_unit.ps1）6 项通过。
- `m5r4_*`（run_m3_regression.ps1，18 项）：全部通过；生产顶层 336271 像素/1148 样本/43 警告、预览 165 帧/105578 刷新/26 警告、完整系统 183705600 转场像素、PCM（含 tb_pcm_preview_rescan）、video_delay，与 m4-local.1 逐项相同。
- 已有测试台按新端口补连接（输出悬空、输入接常量），共 26 个文件，不改检查内容。local.1 首轮回归 m5r1 因读卡测试台未连新端口产生警告而判失败（功能 PASS），补连后为 m5r3；local.2 为 m5r4。

## 已知限制

- 仅本地仿真与 TD 通过，尚未上板。
- 村名为占位名；标题、图例、预警语为本次撰写的初稿，可在各卡 scene.yaml 中修改后用 `--text` 重新生成，FPGA 不需要重建。
- 标题最多 16 格、图例最多 38 格，超出工具报错；字幕在窗口内滚动，长度不限（≤255 格）。
- 卡上 TEXT 有效但 FONT 缺失（或反之）时不显示场景文字行，只显示色块、进度条、红框。
- 预警模式下 AUTO 指示（小数点）仍可切换，只是不换阶段。
