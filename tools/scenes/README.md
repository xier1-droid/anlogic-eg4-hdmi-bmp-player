# 场景包工具使用说明（v0.17.0 M2，图像部分）

`tools/make_scene_pack.py` 按 `scene.yaml` 生成一张场景卡的 PIC1–4.BMP，以及 `hazard_layer` 的参考图像。音频（SND1–4）在 M4 接入，字库和文本（FONT.BIN/TEXT.BIN）在 M5 接入。

设计依据：[02_技术实现.md](../../docs/选题方案/02_技术实现.md) §2.3、§2.4、§4.2、§5。

## 运行

```
py -I tools/scenes/demo_village/draw_demo_village.py        # 只有示意村需要：重画底图、DEM 和手绘 T 图
py -I tools/make_scene_pack.py tools/scenes/demo_village/scene.yaml
```

- 依赖：Python 3、Pillow、numpy、PyYAML。不依赖 scipy，距离变换由工具自己实现，结果不受环境影响。
- 本机 `py` 启动器默认指向的 Python 3.13 没有安装这三个包。可以在 3.13 里安装：`py -m pip install pillow numpy pyyaml`；也可以直接用已经装好依赖的 scoop Python 3.11：`python -I ...`。M2 的产物是用 scoop Python 3.11.9 带 `-I` 生成的。
- 输出写到 `scene.yaml` 的 `output` 目录（示意村是 `demo_village/out/`），重复运行会覆盖。生成物可以随时重建，不入库（见 `.gitignore`）。也可以用 `--out DIR` 指定其他目录。
- 相同的输入，重复生成的 BMP 和 PNG 逐字节相同。

## 输出

| 路径 | 内容 |
|---|---|
| `sd/PIC1.BMP` … `sd/PIC4.BMP` | 直接拷到 SD 卡根目录。32bpp、40 字节 BITMAPINFOHEADER、compression=0、BGRA 自下而上、alpha=T |
| `expected/PICn_tTTT_on.png` / `_off.png` | `hazard_layer` 参考输出：t=0/120/239，frame_cnt=0x3F（on，闪烁亮相）和 0x00（off，暗相） |
| `tmap/PICn_T.png` | T 可视化：白色表示永不覆盖；深蓝到浅蓝表示从早到晚到达；红色表示避险点 |
| `overview.png` | 目视总览，半尺寸。每行是一个阶段，各列依次为：t=0 亮相、t=120 亮相、t=239 亮相、t=239 暗相、T 图 |

每个 BMP 写完后都会立即读回自检。自检按 `bmp_header_check.v` 的条件检查：`BM`、文件长度、dib≥40、planes=1、bitcount=32、compression=0、尺寸、尺寸范围 ≤1920×1080、像素区边界。然后逐像素比较 RGB 和 T 是否与源数据一致。任何一项不通过，工具就报错退出。

## scene.yaml

```yaml
name: demo_village
size: [640, 480]        # 宽 高。底图必须是这个尺寸；与 HDMI 640x480 相同时板上 1:1 不缩放
base: base.png          # 底图，路径相对 scene.yaml
output: out
stages:                 # 必须正好 4 个，依次对应 PIC1–4、阶段 1–4
  - name: 降雨预警
    image: other.png    # 可选：这个阶段改用另一张底图
    sources: [...]      # T 来源列表，可以为空。多个来源在每个像素上取最早的时刻
    spots: [[x, y, r]]  # 可选：避险点圆，T=250，覆盖来源的结果
```

T 来源（`sources` 的每一项）。`t0`/`t1` 可选，默认值为 0/239，要求 0 ≤ t0 ≤ t1 ≤ 239：

| type | 参数 | 规则 |
|---|---|---|
| `paint` | `file` | 手绘灰度图，越黑越早到达：T = v×239÷254（向下取整）；纯白（255）表示不覆盖 |
| `polyline` | `lines`、`width`（默认 4） | 离折线 ≤ width/2 的像素被覆盖。T 沿折线按累计长度从 t0 线性增加到 t1，向下取整。每条线可以写成点列表，也可以写成 `{points, t0, t1}`，用来让支线晚于主线出现 |
| `seeds` | `points`；可选 `mask`、`dem`、`max_level`、`climb`、`max_distance` | 从种子点开始，按 8 邻域测地距离扩散，T = t0 +（t1−t0）×d÷dmax。`mask` 中白色表示可以通过；`dem` 中高于 `max_level` 的像素不可通过；每走一步上坡，额外代价为 climb×高差；dmax 默认取可达范围内的最大距离 |

保留值：240–249、251–254 工具不会生成；255 表示永不覆盖。

## hazard_layer 参考模型（M3 RTL 按这里逐位实现）

`make_scene_pack.hazard_layer_model(rgb, T, t_now, stage, frame_cnt, alert_level=stage, enable, thumbnail)` 和 `blink_phase()` 可以直接 import，供 M3 测试台生成激励。阶段号 stage 取 0–3，对应阶段 1–4。v2 效果（2026-10-16）以 make_scene_pack.py 中的注释为准，概要如下：

```
covered = T < 240 && T <= t_now ;  age = t_now - T（8 位）
front   = covered && age < 6    ;  spot = T == 250
f = frame_cnt（6 位）; fast = f[FAST_BLINK_BIT[alert]] ; slow = f[5]
blend k（k 个 1/4 的颜色 c），每个通道：
  k=1: (a>>1)+(a>>2)+(c>>2)   k=2: (a>>1)+(c>>1)   k=3: (a>>2)+(c>>1)+(c>>2)
优先级：covered（阶段 2–4）> spot && slow（00FF00）> 雨丝（阶段 1）> 原色；de=0 时一律原色
```

| stage | 阶段 | 本体 | 前沿（age<6） | 动画 |
|---|---|---|---|---|
| 0 | 降雨预警 | — | — | 雨丝：col=(x+(y>>2)) mod 1024，h=(((col·157) mod 2048)>>3) ^ (col mod 256)；h < 4+(t>>5) 且 ((y−8f+4col) mod 32) < 12 时 blend 2 C8D2DC。斜向下落，t 越大越密 |
| 1 | 裂缝 | blend 3 180E06（近黑） | fast ? FFD000 : 本体 | — |
| 2 | 山洪 | 浑水 8C6A3C，按淹没时长加深：age<24 blend 1，<64 blend 2，其余 blend 3 | blend (fast ? 2 : 1) F0E8D6（浪花） | 波纹：((T−(f>>1)) mod 16) < 2 的像素颜色换成 C4A874，向下游移动 |
| 3 | 撤离 | blend 3 20C848 | fast ? FFFFFF : 40FF40 | 流动虚线：((T−(f>>1)) mod 8) < 3 的像素为 AAFFBE，朝避险点移动 |

- 闪烁：`fast` 各级取 bit 4/4/3/2，按 60fps 约为 1.9/1.9/3.75/7.5Hz；`slow` 取 bit 5，约 0.94Hz。阶段 1–4 的 alert_level 依次为 0–3。
- x/y 是像素在有效区内的坐标，由 hazard_layer 根据 de 和 frame_start 自行计数。
- v1（m3-local.1）的配色是：深褐 603818 / 蓝 2060FF / 绿 20C040，前沿为单色闪烁，没有动画。v2 按河谷村写实底图重新选色，洪水改为浑黄泥水色。
- 避险点（T=250）与 covered 互斥，在所有阶段都会闪烁。

## 示意村 demo_village

虚构地形，不使用任何地图数据。一条河从北向南流过谷底；村庄在河西侧的谷底，西面是坡体和一条支沟；东侧高地、西南小丘是两个避险点，有桥和小路通往这两处。

| 文件 | 说明 |
|---|---|
| `scene.yaml` | 场景定义。裂缝、撤离路线、避险点的坐标都在这里 |
| `draw_demo_village.py` | 生成下面三张图，固定随机种子。路线和避险点从 `scene.yaml` 读取，所以底图和 T 图对得上 |
| `base.png` | 底图：分层设色、山体阴影、河流、桥、村庄、小路、避险棚 |
| `dem.png` | 高程，谷底为 40，供山洪种子扩散使用 |
| `gully_flood.png` | 代替手绘的支沟山洪 T 图：上游端黑，越往沟口越浅，沟口逐渐展宽 |

| 阶段 | T 来源 | 预期效果 |
|---|---|---|
| PIC1 降雨预警 | 无（全为 255） | 原图 |
| PIC2 裂缝出现 | 主裂缝 1 条、支线 3 条（polyline，宽 6） | 村子西北坡上的裂缝逐渐延伸，前沿亮黄闪烁 |
| PIC3 山洪暴发 | 支沟手绘图 + 上游种子（DEM 限高 62，上坡代价 3） | 支沟洪水先冲进村子，主河洪水从北向南漫过整个谷底，前沿白色闪烁 |
| PIC4 避险撤离 | 两条撤离路线（polyline，宽 5，t 从 0 到 200）+ 两个避险点 | 绿色路线从村子伸向高地，避险点绿色闪烁 |

> 阶段 3 的灾害色由阶段统一决定（蓝色），所以第三张图只表现水体。如果画滑坡体，它也会被染成蓝色。

## 河谷村 valley_village（板测用卡）

底图由用户用生图 AI 生成（虚构村庄，原图在 tools/Photo/，不入库），`prepare_valley_village.py` 缩放为 640×480 的 pic1–4.png，并生成山洪用的掩膜和代价场。四张图各自对应一个阶段，地物之间有几个像素的偏移，所以每个阶段的 T 都标注在它自己那张图上。

| 文件 | 说明 |
|---|---|
| `scene.yaml` | 裂缝、撤离路线、避险点坐标，以及山洪的种子点 |
| `prepare_valley_village.py` | 从 tools/Photo 生成 pic1–4.png、flood_dem.png、flood_mask.png、gully_mask.png；河道中线、洪水最大范围、支沟走廊的多边形写在脚本里，边缘用固定种子的平滑噪声做出起伏 |

| 阶段 | 底图 | T 来源 | 效果 |
|---|---|---|---|
| PIC1 降雨预警 | 乌云 | 无 | 雨丝越下越密 |
| PIC2 裂缝出现 | 晴 | 折线，宽 3：西北坡滑坡体后缘弧形 → 右侧缘 → 伸向村后，另有左侧缘和坡顶分叉 | 近黑裂缝延伸，尖端亮黄闪烁 |
| PIC3 山洪暴发 | 雾、浑水 | 支沟走廊种子（沿沟冲下，在村后散开成扇）+ 主河整排种子（先涨满河道，再自北向南漫上西岸农田，直到桥边最低的几户） | 浑水逐渐加深，波纹向下游移动，前沿浪花 |
| PIC4 避险撤离 | 薄雾 | 两条折线，宽 4（东线过石桥上台地，西南线沿田间小路上山丘）+ 两处避险棚 | 流动绿色虚线，避险点慢闪 |


## 撤离标注规则（format 3，用户 2026-10-16 要求）

- 路线和避险点必须全部在危险区以外。make_scene_pack.py 会检查撤离图中路线（region 0）、避险点与危险区（region 1）的重叠，有重叠就报出像素数和范围并停止生成。
- 危险区按灾害类型和具体图片划定，不套用固定形状：
  - 山洪：河道及可能漫淹的低地；不过桥、不沿河走。
  - 滑坡：滑坡体及其下方的滑移、堆积范围（坡脚）；路线横向离开坡体，不沿坡脚走、不往坡下跑到堆积区。
  - 泥石流：沟道及沟口堆积扇；向沟道两侧的高处撤离，不顺沟、不横穿沟口。
  - 地震：陡坡崩塌落石区、建筑密集区和临河陡岸；避险点选开阔平地，远离建筑和山坡。
- 工具只能检查重叠，路线是否合理（是否沿真实道路、方向是否背离灾害源、是否需要穿越其他危险地形）要逐张图判断，并在 scene.yaml 注释中写明取舍理由。
