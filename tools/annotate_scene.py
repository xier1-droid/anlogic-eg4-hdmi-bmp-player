#!/usr/bin/env python3
"""Point-and-click annotation tool for format 3 scene cards (scene.yaml).

Draws the T sources of each stage on its own picture: routes, cracks and
fault lines as polylines, danger zones and slide bodies as polygons, hazard
outlines, flood seeds and refuges; masks painted elsewhere (PS, GIMP, 画图)
are added as files. The T map and the animation are previewed with the same
functions make_scene_pack.py uses (stage_t3, hazard_v3.render), and
生成场景包 runs make_scene_pack.py --gif, so what is checked here is what
goes to the SD card.

Usage: py -I tools/annotate_scene.py [scene.yaml]
       (no argument: open or create a scene from the 文件 menu)
       tools/annotate_scene.exe [scene.yaml] is the same tool, built by
       py -I tools/build_annotate_exe.py

Mouse: left click adds a point; right click, double click or Enter finishes
the shape; Backspace removes the last point, Esc cancels. With a shape
selected, drag its vertices to move them. The brush paints a region into a
mask png (brush_pN_k.png, written on save) or into the selected mask; masks
not made by the brush, or shared, are copied first, never edited in place.
Ctrl+Z undoes (strokes too), Ctrl+S saves.
PyYAML drops comments on save, so an existing file is first copied to
scene.yaml.bak; reasons go into each stage's `note` (make_scene_pack ignores it).
"""
from pathlib import Path
import copy, os, shutil, subprocess, sys, tempfile, threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import numpy as np
import yaml
from PIL import Image, ImageDraw, ImageTk
sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I drops the script directory
import hazard_v3 as v3  # noqa: E402
import make_scene_pack as msp  # noqa: E402

W, H = 640, 480
FROZEN = getattr(sys, 'frozen', False)      # PyInstaller exe: lives in tools/, runs make_scene_pack itself
TOOLS_DIR = Path(sys.executable if FROZEN else __file__).resolve().parent
REPO = TOOLS_DIR.parent
HEADER = '# 由 tools/annotate_scene.py 保存。'
HAZARDS = {'flood': '山洪', 'landslide': '滑坡', 'debris_flow': '泥石流', 'earthquake': '地震'}
ROLES = {'cause': '致因', 'onset': '发生', 'aftermath': '后果', 'evacuation': '撤离'}
# Region meaning per (hazard, role) or role, from the constants in hazard_v3.py.
REGIONS = {
    'cause': ['隐患区轮廓'],
    ('earthquake', 'cause'): ['断层带', '震点白环', '白环暗边', '地震波场'],
    ('landslide', 'onset'): ['裂缝', '新鲜土体', '滑坡体', '落石'],
    ('landslide', 'aftermath'): ['堆积体', '滑坡后壁'],
    ('debris_flow', 'onset'): ['泥浆主体', '沟壁溅泥'],
    ('debris_flow', 'aftermath'): ['堆积扇', '沟床填满'],
    ('flood', 'onset'): ['淹没农田', '河道', '漫堤'],
    ('flood', 'aftermath'): ['淹没范围'],
    ('earthquake', 'onset'): ['裂缝', '扬尘', '倒塌房屋', '落石'],
    ('earthquake', 'aftermath'): ['废墟', '地裂缝', '碎石'],
    'evacuation': ['撤离路线', '危险区', '避险点（用避险点工具）'],
}
REGION_COLORS = [(255, 200, 0), (230, 50, 40), (60, 140, 255), (200, 80, 220)]
EVAC_COLORS = {v3.EVAC_ROUTE: (40, 210, 80), v3.EVAC_DANGER: (230, 50, 40)}
TOOLS = [('select', '选择 / 拖点'), ('polyline', '折线（路线、裂缝）'), ('polygon', '多边形（区域）'),
         ('brush', '画笔（涂区域）'), ('eraser', '橡皮擦'),
         ('outline', '轮廓线（隐患区）'), ('seeds', '种子点（扩散）'), ('spot', '避险点')]
PAINT_TOOLS = ('brush', 'eraser')
BRUSH_PREFIX = 'brush_'     # masks painted in this tool; others are never edited in place
TYPE_NAMES = {'polyline': '折线', 'polygon': '多边形', 'outline': '轮廓线', 'seeds': '种子点',
              'mask': '掩膜', 'paint': '灰度图', 'crack': '裂缝', 'rockfall': '落石',
              'patches': '土斑', 'distance': '波场', 'quakes': '震点', 'dust': '扬尘'}
HINTS = {
    'select': '点击形状的顶点选中它；选中后拖动顶点可以移动',
    'polyline': '左键逐点画线，起点最早出现、终点最晚；右键 / 双击 / 回车结束',
    'polygon': '左键逐点画区域边界；右键 / 双击 / 回车闭合',
    'outline': '左键逐点画轮廓；右键 / 双击 / 回车闭合',
    'brush': '按住左键涂抹。选中了掩膜或种子点就涂在它上面，否则新建一块画笔区域（Esc 取消选中）；[ ] 调笔刷大小',
    'eraser': '按住左键擦除选中的画笔区域、掩膜或种子掩膜；[ ] 调笔刷大小',
    'seeds': '左键放种子点（扩散起点）；右键 / 回车结束。记得设种子掩膜或最远距离',
    'spot': '左键点击避险点中心，半径取参数里的“避险点半径”',
}
GRADES = {'无': None, '自上而下': 'down', '自左向右': 'right'}


class Dumper(yaml.SafeDumper):
    pass


def _seq(d, data):
    num = (int, float)
    flow = bool(data) and all(isinstance(i, num) or (isinstance(i, list) and all(isinstance(j, num) for j in i))
                              for i in data)
    return d.represent_sequence('tag:yaml.org,2002:seq', data, flow_style=flow)


def _str(d, s):
    return d.represent_scalar('tag:yaml.org,2002:str', s, style='|' if '\n' in s else None)


Dumper.add_representer(list, _seq)
Dumper.add_representer(str, _str)


def fit_image(path):
    """Centre-crop to 4:3 and resize to 640x480."""
    im = Image.open(path).convert('RGB')
    w, h = im.size
    if w * 3 > h * 4:
        cw = h * 4 // 3
        im = im.crop(((w - cw) // 2, 0, (w - cw) // 2 + cw, h))
    elif w * 3 < h * 4:
        ch = w * 3 // 4
        im = im.crop((0, (h - ch) // 2, w, (h - ch) // 2 + ch))
    return im.resize((W, H), Image.LANCZOS)


def region_names(hazard, role):
    names = list(REGIONS.get((hazard, role)) or REGIONS.get(role) or [])
    names += [f'区域 {i}' for i in range(len(names), 4)]
    return [f'{i} {n}' for i, n in enumerate(names)]


def line_points(line):
    return line['points'] if isinstance(line, dict) else line


class App:
    def __init__(self, root, path=None):
        self.root = root
        self.path = None
        self.cfg = None
        self.stage_i = 0
        self.sel = None                 # ('src', i) or ('spot', i)
        self.note_stage = None          # stage whose note the 说明 box shows
        self.pending = []
        self.drag = None
        self.brush = {}                 # mask name -> 'L' image painted this session
        self.brush_dirty = set()        # painted since the last save
        self.stroke = None              # (mask name, fill value) while the brush is down
        self.last = None
        self.tmp = Path(tempfile.mkdtemp(prefix='annotate_'))   # unsaved strokes, for the T preview
        self.undo_stack = []            # (stage, stages, brush snapshot (name, image or None) or None)
        self.dirty = False
        self.had_comments = False
        self.backed_up = False
        self.img_cache = {}
        self.t_cache = {}
        self.mask_cache = {}
        self.fc = 0
        self.playing = False
        self.busy_params = False
        self.photo = None
        self.scale = 1
        self.build_ui()
        self.fit_screen()
        root.protocol('WM_DELETE_WINDOW', self.on_close)
        if path:
            self.load(Path(path))
        else:
            self.log('文件 → 打开 scene.yaml，或 文件 → 新建场景（选 4 张阶段图）')

    # ------------------------------------------------------------------ UI
    def build_ui(self):
        r = self.root
        r.title('场景标注工具')
        menu = tk.Menu(r)
        fm = tk.Menu(menu, tearoff=0)
        fm.add_command(label='新建场景…', command=self.new_scene)
        fm.add_command(label='打开…', command=self.open_dialog)
        fm.add_command(label='保存', accelerator='Ctrl+S', command=self.save)
        fm.add_command(label='另存为…', command=self.save_as)
        fm.add_separator()
        fm.add_command(label='退出', command=self.on_close)
        menu.add_cascade(label='文件', menu=fm)
        r.config(menu=menu)

        main = ttk.Frame(r)
        main.pack(fill='both', expand=True)
        left = ttk.Frame(main)
        left.pack(side='left', fill='both', padx=4, pady=4)
        self.canvas = tk.Canvas(left, width=int(W * self.scale), height=int(H * self.scale),
                                bg='#222', highlightthickness=0, cursor='crosshair')
        self.canvas.pack()
        self.canvas_img = self.canvas.create_image(0, 0, anchor='nw')
        self.status = ttk.Label(left, text='', anchor='w')
        self.status.pack(fill='x')
        self.hint = ttk.Label(left, text='', anchor='w', foreground='#555')
        self.hint.pack(fill='x')

        col1 = ttk.Frame(main)
        col1.pack(side='left', fill='y', padx=4, pady=4)
        col2 = ttk.Frame(main)
        col2.pack(side='left', fill='both', expand=True, padx=4, pady=4)

        f = ttk.LabelFrame(col1, text='场景')
        f.pack(fill='x', pady=2)
        ttk.Label(f, text='灾害').grid(row=0, column=0, sticky='w')
        self.hazard_cb = ttk.Combobox(f, values=[f'{k} {v}' for k, v in HAZARDS.items()], state='readonly', width=16)
        self.hazard_cb.grid(row=0, column=1, sticky='w')
        self.hazard_cb.bind('<<ComboboxSelected>>', self.on_hazard)
        ttk.Label(f, text='缩放').grid(row=1, column=0, sticky='w')
        self.scale_cb = ttk.Combobox(f, values=['1', '1.25', '1.5', '2'], state='readonly', width=6)
        self.scale_cb.set(str(self.scale))
        self.scale_cb.grid(row=1, column=1, sticky='w')
        self.scale_cb.bind('<<ComboboxSelected>>', self.on_scale)

        f = ttk.LabelFrame(col1, text='阶段')
        f.pack(fill='x', pady=2)
        self.stage_var = tk.IntVar(value=0)
        bar = ttk.Frame(f)
        bar.grid(row=0, column=0, columnspan=3, sticky='w')
        for n in range(4):
            ttk.Radiobutton(bar, text=f'PIC{n + 1}', value=n, variable=self.stage_var,
                            command=self.on_stage).pack(side='left')
        ttk.Label(f, text='名称').grid(row=1, column=0, sticky='w')
        self.name_var = tk.StringVar()
        ttk.Entry(f, textvariable=self.name_var, width=30).grid(row=1, column=1, columnspan=2, sticky='we')
        self.name_var.trace_add('write', self.on_name)
        ttk.Label(f, text='角色').grid(row=2, column=0, sticky='w')
        self.role_cb = ttk.Combobox(f, values=[f'{k} {v}' for k, v in ROLES.items()], state='readonly', width=16)
        self.role_cb.grid(row=2, column=1, sticky='w')
        self.role_cb.bind('<<ComboboxSelected>>', self.on_role)
        ttk.Label(f, text='底图').grid(row=3, column=0, sticky='w')
        self.image_lbl = ttk.Label(f, text='')
        self.image_lbl.grid(row=3, column=1, sticky='w')
        ttk.Button(f, text='换底图…', command=self.change_image).grid(row=3, column=2, sticky='e')

        f = ttk.LabelFrame(col1, text='工具')
        f.pack(fill='x', pady=2)
        self.tool = tk.StringVar(value='polyline')
        for k, label in TOOLS:
            ttk.Radiobutton(f, text=label, value=k, variable=self.tool, command=self.on_tool).pack(anchor='w')

        f = ttk.LabelFrame(col1, text='参数（新画的形状 / 选中的形状）')
        f.pack(fill='x', pady=2)
        self.region_cb = ttk.Combobox(f, state='readonly', width=22)
        self.region_cb.bind('<<ComboboxSelected>>', self.on_param)
        self.vars = {}
        rows = [('区域', self.region_cb)]
        for key, label, lo, hi, default in (('width', '线宽', 1, 20, 4), ('t0', '开始时刻 t0', 0, 239, 0),
                                            ('t1', '结束时刻 t1', 0, 239, 200), ('rough', '边缘起伏', 0, 12, 0),
                                            ('max_distance', '最远距离(0=不限)', 0, 2000, 0),
                                            ('radius', '避险点半径', 3, 30, 9),
                                            ('brush', '笔刷半径', 2, 60, 12)):
            v = tk.IntVar(value=default)
            sb = ttk.Spinbox(f, from_=lo, to=hi, textvariable=v, width=8, command=self.on_param)
            sb.bind('<Return>', self.on_param)
            sb.bind('<FocusOut>', self.on_param)
            self.vars[key] = v
            rows.append((label, sb))
        self.grade_cb = ttk.Combobox(f, values=list(GRADES), state='readonly', width=10)
        self.grade_cb.set('无')
        self.grade_cb.bind('<<ComboboxSelected>>', self.on_param)
        rows.append(('渐进方向', self.grade_cb))
        for n, (label, w) in enumerate(rows):
            ttk.Label(f, text=label).grid(row=n, column=0, sticky='w')
            w.grid(row=n, column=1, sticky='w')
        ttk.Label(f, text='时刻 0–239；同一阶段里后画的形状盖住先画的', foreground='#555').grid(
            row=len(rows), column=0, columnspan=2, sticky='w')

        f = ttk.LabelFrame(col2, text='本阶段的标注（后面的盖住前面的）')
        f.pack(fill='both', expand=True, pady=2)
        self.listbox = tk.Listbox(f, height=9, exportselection=False)
        self.listbox.pack(fill='both', expand=True)
        self.listbox.bind('<<ListboxSelect>>', self.on_list)
        bar = ttk.Frame(f)
        bar.pack(fill='x')
        for text, cmd in (('上移', lambda: self.move(-1)), ('下移', lambda: self.move(1)),
                          ('删除', self.delete_sel), ('添加掩膜…', self.add_mask),
                          ('设种子掩膜…', self.set_seed_mask)):
            ttk.Button(bar, text=text, command=cmd).pack(side='left')

        f = ttk.LabelFrame(col2, text='说明 / 取舍理由（存为 note）')
        f.pack(fill='x', pady=2)
        self.note = tk.Text(f, height=4, width=46, wrap='char')
        self.note.pack(fill='x')
        self.note.bind('<KeyRelease>', self.on_note)

        f = ttk.LabelFrame(col2, text='预览与生成')
        f.pack(fill='x', pady=2)
        self.mode = tk.StringVar(value='标注')
        bar = ttk.Frame(f)
        bar.pack(fill='x')
        for m in ('标注', 'T 图', '动画'):
            ttk.Radiobutton(bar, text=m, value=m, variable=self.mode, command=self.render).pack(side='left')
        self.play_btn = ttk.Button(bar, text='播放', command=self.toggle_play)
        self.play_btn.pack(side='left', padx=6)
        self.t_now = tk.IntVar(value=239)
        ttk.Scale(f, from_=0, to=239, variable=self.t_now, command=lambda _: self.render()).pack(fill='x')
        self.t_lbl = ttk.Label(f, text='')
        self.t_lbl.pack(anchor='w')
        bar = ttk.Frame(f)
        bar.pack(fill='x')
        ttk.Button(bar, text='检查本阶段', command=self.check_stage).pack(side='left')
        self.gen_btn = ttk.Button(bar, text='保存并生成场景包', command=self.generate)
        self.gen_btn.pack(side='left')
        ttk.Button(bar, text='打开输出目录', command=self.open_out).pack(side='left')

        f = ttk.LabelFrame(col2, text='日志')
        f.pack(fill='both', expand=True, pady=2)
        self.logbox = tk.Text(f, height=10, width=46, wrap='char', state='disabled')
        self.logbox.pack(fill='both', expand=True)

        c = self.canvas
        c.bind('<Button-1>', self.on_press)
        c.bind('<B1-Motion>', self.on_drag)
        c.bind('<ButtonRelease-1>', self.on_release)
        c.bind('<Double-Button-1>', lambda e: self.finish())
        c.bind('<Button-3>', lambda e: self.finish())
        c.bind('<Motion>', self.on_motion)
        c.bind('<Leave>', lambda e: c.delete('brushcur'))
        r.bind('[', lambda e: None if self.typing(e) else self.brush_size(-2))
        r.bind(']', lambda e: None if self.typing(e) else self.brush_size(2))
        r.bind('<Return>', lambda e: None if self.typing(e) else self.finish())
        r.bind('<Escape>', lambda e: self.cancel())
        r.bind('<BackSpace>', lambda e: None if self.typing(e) else self.pop_point())
        r.bind('<Delete>', lambda e: None if self.typing(e) else self.delete_sel())
        r.bind('<Control-z>', lambda e: None if self.typing(e) else self.undo())
        r.bind('<Control-s>', lambda e: self.save())
        self.on_tool()

    @staticmethod
    def typing(e):
        return isinstance(e.widget, (tk.Entry, tk.Text, ttk.Entry, ttk.Spinbox, tk.Spinbox))

    def log(self, msg):
        self.logbox.config(state='normal')
        self.logbox.insert('end', msg.rstrip() + '\n')
        self.logbox.see('end')
        self.logbox.config(state='disabled')

    # ---------------------------------------------------------- scene file
    @property
    def base_dir(self):
        return self.path.parent

    @property
    def stage(self):
        return self.cfg['stages'][self.stage_i]

    def load(self, path):
        try:
            text = path.read_text(encoding='utf-8')
            cfg = yaml.safe_load(text)
        except (OSError, yaml.YAMLError) as e:
            messagebox.showerror('打不开', str(e))
            return
        if cfg.get('format') != 3 or len(cfg.get('stages') or []) != 4:
            messagebox.showerror('格式不支持', '只支持 format: 3、正好 4 个阶段的 scene.yaml')
            return
        if tuple(cfg.get('size', (0, 0))) != (W, H):
            messagebox.showerror('尺寸不支持', f'只支持 {W}x{H} 的场景')
            return
        for n, st in enumerate(cfg['stages']):
            st.setdefault('sources', [])
            st['sources'] = st['sources'] or []
            st.setdefault('role', list(ROLES)[n])
            st.setdefault('hazard', cfg['stages'][0].get('hazard', 'flood'))
        self.note_stage = None
        self.cfg, self.path = cfg, path
        own = text.startswith(HEADER)     # saved by this tool: the only comment is its own header
        self.had_comments = not own and any(l.lstrip().startswith('#') or ' #' in l for l in text.splitlines())
        self.backed_up = False
        self.brush.clear()
        self.brush_dirty.clear()
        self.undo_stack.clear()
        self.dirty = False
        self.t_cache.clear()
        self.sel = None
        self.pending = []
        self.stage_var.set(0)
        self.root.title(f'场景标注工具 - {path}')
        hz = cfg['stages'][0]['hazard']
        self.hazard_cb.set(f'{hz} {HAZARDS.get(hz, "")}')
        self.log(f'已打开 {path}')
        self.on_stage()

    def open_dialog(self):
        if not self.confirm_discard():
            return
        p = filedialog.askopenfilename(title='打开 scene.yaml', filetypes=[('scene', '*.yaml'), ('全部', '*.*')],
                                       initialdir=TOOLS_DIR / 'scenes')
        if p:
            self.load(Path(p))

    def new_scene(self):
        if not self.confirm_discard():
            return
        d = filedialog.askdirectory(title='选择一个空目录作为场景目录（可先新建，如 tools/scenes/my_village）',
                                    initialdir=TOOLS_DIR / 'scenes')
        if not d:
            return
        d = Path(d)
        if (d / 'scene.yaml').exists():
            if messagebox.askyesno('已有场景', f'{d} 里已有 scene.yaml，直接打开它吗？'):
                self.load(d / 'scene.yaml')
            return
        hz = self.ask_choice('灾害类型', '这张场景卡是哪种灾害？', HAZARDS)
        if not hz:
            return
        files = filedialog.askopenfilenames(
            title='选 4 张阶段图（按文件名排序依次为 致因/发生/后果/撤离；只选 1 张则 4 个阶段共用）',
            filetypes=[('图片', '*.png *.jpg *.jpeg *.bmp *.webp'), ('全部', '*.*')])
        if not files:
            return
        files = sorted(files)
        if len(files) not in (1, 4):
            messagebox.showerror('张数不对', f'选了 {len(files)} 张，需要 1 张或 4 张')
            return
        d.mkdir(parents=True, exist_ok=True)
        stages = []
        for n, role in enumerate(ROLES):
            src = files[n if len(files) == 4 else 0]
            name = f'pic{n + 1}.png' if len(files) == 4 else 'pic1.png'
            if len(files) == 4 or n == 0:
                fit_image(src).save(d / name)
                self.log(f'{Path(src).name} → {name}（裁成 4:3，缩放到 {W}x{H}）')
            stages.append({'name': f'{ROLES[role]}：', 'image': name, 'hazard': hz, 'role': role, 'sources': []})
        self.cfg = {'name': d.name, 'format': 3, 'size': [W, H], 'base': 'pic1.png', 'output': 'out',
                    'stages': stages}
        self.path = d / 'scene.yaml'
        self.had_comments = False
        self.write_file()
        self.load(self.path)

    def ask_choice(self, title, prompt, options):
        top = tk.Toplevel(self.root)
        top.title(title)
        top.transient(self.root)
        ttk.Label(top, text=prompt).pack(padx=10, pady=6)
        cb = ttk.Combobox(top, values=[f'{k} {v}' for k, v in options.items()], state='readonly')
        cb.current(0)
        cb.pack(padx=10)
        result = []
        ttk.Button(top, text='确定', command=lambda: (result.append(cb.get().split()[0]), top.destroy())).pack(pady=6)
        top.grab_set()
        self.root.wait_window(top)
        return result[0] if result else None

    def write_file(self):
        try:
            rel = self.path.resolve().relative_to(REPO).as_posix()
        except ValueError:
            rel = self.path.as_posix()
        head = (HEADER + f'坐标为 {W}x{H} 像素；各阶段的取舍理由写在 note 里。\n'
                f'# 生成：py -I tools/make_scene_pack.py {rel} --gif\n')
        body = yaml.dump(self.cfg, Dumper=Dumper, allow_unicode=True, sort_keys=False, width=200)
        self.path.write_text(head + body, encoding='utf-8')

    def save(self):
        if not self.cfg:
            return False
        self.sync_note()
        if self.had_comments and not self.backed_up:
            bak = self.path.with_name(self.path.name + '.bak')
            if not messagebox.askokcancel('保存会去掉注释', f'原文件里的 # 注释保存后会丢失。\n'
                                          f'原文件先备份为 {bak.name}，理由请写在“说明”栏里。继续保存？'):
                return False
            shutil.copy2(self.path, bak)
            self.backed_up = True
            self.log(f'原文件已备份为 {bak}')
        for name, im in self.brush.items():
            if self.references(name) and (name in self.brush_dirty or not (self.base_dir / name).exists()):
                im.save(self.base_dir / name)
        self.brush_dirty.clear()
        self.write_file()
        self.dirty = False
        self.log(f'已保存 {self.path}')
        return True

    def save_as(self):
        if not self.cfg:
            return
        p = filedialog.asksaveasfilename(title='另存为（放在同一个场景目录里，图片路径才对得上）',
                                         initialdir=self.base_dir, initialfile='scene.yaml',
                                         defaultextension='.yaml')
        if p:
            if Path(p).parent.resolve() != self.base_dir.resolve():
                messagebox.showwarning('目录不同', '图片和掩膜按相对路径引用，另存到别的目录后需要把它们一起拷过去')
            self.path, self.had_comments = Path(p), False
            self.save()
            self.root.title(f'场景标注工具 - {self.path}')

    def confirm_discard(self):
        if not self.dirty:
            return True
        ans = messagebox.askyesnocancel('未保存', '当前场景有改动，先保存吗？')
        if ans is None:
            return False
        return self.save() if ans else True

    def on_close(self):
        if self.confirm_discard():
            shutil.rmtree(self.tmp, ignore_errors=True)
            self.root.destroy()

    # ------------------------------------------------------------ editing
    def push_undo(self, brush=None):
        """brush: (mask name, image before the stroke, or None if the stroke creates it)."""
        self.undo_stack.append((self.stage_i, copy.deepcopy(self.cfg['stages']), brush))
        del self.undo_stack[:-50]

    def touch(self):
        self.dirty = True
        self.t_cache.pop(self.stage_i, None)
        self.refresh_list()
        self.render()

    def undo(self):
        if not self.undo_stack:
            return
        self.stage_i, self.cfg['stages'], brush = self.undo_stack.pop()
        if brush:
            name, im = brush
            if im is None:
                self.brush.pop(name, None)
                self.brush_dirty.discard(name)
            else:
                self.brush[name] = im
                self.brush_dirty.add(name)
                self.flush_tmp(name)
        self.stage_var.set(self.stage_i)
        self.sel = None
        self.t_cache.clear()
        self.dirty = True
        self.on_stage()

    def on_hazard(self, _=None):
        hz = self.hazard_cb.get().split()[0]
        self.push_undo()
        for st in self.cfg['stages']:
            st['hazard'] = hz
        self.t_cache.clear()
        self.load_regions()
        self.touch()

    def on_role(self, _=None):
        self.push_undo()
        self.stage['role'] = self.role_cb.get().split()[0]
        self.load_regions()
        self.on_tool()
        self.touch()

    def on_name(self, *_):
        if self.cfg and not self.busy_params and self.stage.get('name') != self.name_var.get():
            self.stage['name'] = self.name_var.get()
            self.dirty = True

    def on_note(self, _=None):
        self.dirty = True

    def sync_note(self):
        if self.cfg and self.note_stage is not None:
            st = self.cfg['stages'][self.note_stage]
            text = self.note.get('1.0', 'end').strip()
            if text:
                st['note'] = text
            else:
                st.pop('note', None)

    def on_stage(self):
        if not self.cfg:
            return
        self.sync_note()
        self.stage_i = self.stage_var.get()
        self.sel, self.pending = None, []
        st = self.stage
        self.busy_params = True
        self.name_var.set(st.get('name', ''))
        self.busy_params = False
        self.role_cb.set(f'{st["role"]} {ROLES.get(st["role"], "")}')
        self.image_lbl.config(text=st.get('image', self.cfg['base']))
        self.note.delete('1.0', 'end')
        self.note.insert('1.0', st.get('note', ''))
        self.note_stage = self.stage_i
        self.load_regions()
        self.on_tool()
        self.refresh_list()
        self.render()

    def load_regions(self):
        st = self.stage
        self.region_cb.config(values=region_names(st['hazard'], st['role']))
        if not self.region_cb.get() or self.region_cb.get() not in self.region_cb['values']:
            self.region_cb.current(0)

    def on_tool(self):
        tool = self.tool.get()
        self.pending = []
        self.draw_pending()
        self.canvas.delete('brushcur')
        self.hint.config(text=HINTS[tool])
        if not self.cfg:
            return
        keep = tool in PAINT_TOOLS and self.paint_key(self.selected_src())   # paint into the selected mask
        if self.sel and not keep:
            self.sel = None
            self.refresh_list()
            self.render()
        if not self.sel:
            self.auto_region()

    def auto_region(self):
        """Default region of the current tool on evacuation and cause stages."""
        tool, role = self.tool.get(), self.stage['role']
        auto = None
        if role == 'evacuation':
            auto = {'polyline': v3.EVAC_ROUTE, 'polygon': v3.EVAC_DANGER, 'brush': v3.EVAC_DANGER}.get(tool)
            if tool == 'polyline':
                self.vars['t1'].set(200)
        elif role == 'cause' and tool == 'outline' and self.stage['hazard'] != 'earthquake':
            auto = v3.CAUSE_ZONE
        if auto is not None:
            self.region_cb.current(auto)

    def change_image(self):
        if not self.cfg:
            return
        p = filedialog.askopenfilename(title=f'PIC{self.stage_i + 1} 的底图',
                                       filetypes=[('图片', '*.png *.jpg *.jpeg *.bmp *.webp'), ('全部', '*.*')])
        if not p:
            return
        name = f'pic{self.stage_i + 1}.png'
        others = [n for n, st in enumerate(self.cfg['stages'])
                  if n != self.stage_i and st.get('image', self.cfg['base']) == name]
        if others and not messagebox.askyesno('底图共用', f'{name} 也是 PIC{others[0] + 1} 的底图，一起替换吗？'):
            return
        fit_image(p).save(self.base_dir / name)
        self.push_undo()
        self.stage['image'] = name
        self.img_cache.clear()
        self.image_lbl.config(text=name)
        self.log(f'{Path(p).name} → {name}（裁成 4:3，缩放到 {W}x{H}）')
        self.touch()

    def params(self):
        out = {}
        for k, v in self.vars.items():
            try:
                out[k] = int(v.get())
            except (tk.TclError, ValueError):
                out[k] = 0
        out['t0'] = max(0, min(239, out['t0']))
        out['t1'] = max(out['t0'], min(239, out['t1']))
        out['region'] = self.region_cb.current()
        out['grade'] = GRADES.get(self.grade_cb.get())
        return out

    def finish(self):
        tool = self.tool.get()
        pts = []
        for p in self.pending:
            if not pts or pts[-1] != p:
                pts.append(p)
        need = {'polyline': 2, 'polygon': 3, 'outline': 3, 'seeds': 1}.get(tool)
        if not need:
            return
        if len(pts) < need:
            if pts:
                self.log(f'至少需要 {need} 个点')
            return
        p = self.params()
        src = {'type': tool, 'region': p['region']}
        if tool == 'polyline':
            src.update(width=p['width'], t0=p['t0'], t1=p['t1'], lines=[pts])
        elif tool == 'outline':
            src.update(width=p['width'], t0=p['t0'], points=pts)
        elif tool == 'polygon':
            src.update(t0=p['t0'], points=pts)
            if p['grade']:
                src.update(grade=p['grade'], t1=p['t1'])
            if p['rough']:
                src.update(rough=p['rough'], seed=len(self.stage['sources']) + 1)
        else:
            src.update(points=pts, t0=p['t0'], t1=p['t1'])
            if p['max_distance']:
                src['max_distance'] = p['max_distance']
            else:
                self.log('提示：种子点没有掩膜和最远距离时会扩散到整张图。'
                         '用“设种子掩膜…”指定可通过的范围（白色可通过），或设最远距离')
        self.push_undo()
        self.stage['sources'].append(src)
        # Not selected: the next shape may start on this one's vertex (two cracks from one point).
        self.sel = None
        self.pending = []
        self.draw_pending()
        self.touch()

    def cancel(self):
        if not self.pending and self.sel:     # Esc with nothing being drawn: deselect
            self.sel = None
            self.refresh_list()
            self.render()
            self.auto_region()
        self.pending = []
        self.draw_pending()

    def pop_point(self):
        if self.pending:
            self.pending.pop()
            self.draw_pending()

    def delete_sel(self):
        if not self.sel:
            return
        kind, i = self.sel
        self.push_undo()
        if kind == 'src':
            del self.stage['sources'][i]
        else:
            del self.stage['spots'][i]
            if not self.stage['spots']:
                del self.stage['spots']
        self.sel = None
        self.touch()

    def move(self, step):
        if not self.sel or self.sel[0] != 'src':
            return
        srcs, i = self.stage['sources'], self.sel[1]
        j = i + step
        if 0 <= j < len(srcs):
            self.push_undo()
            srcs[i], srcs[j] = srcs[j], srcs[i]
            self.sel = ('src', j)
            self.touch()
            self.select_in_list()

    def pick_mask(self, title):
        p = filedialog.askopenfilename(title=title, initialdir=self.base_dir,
                                       filetypes=[('图片', '*.png *.bmp'), ('全部', '*.*')])
        if not p:
            return None
        p = Path(p)
        im = Image.open(p)
        if im.size != (W, H):
            messagebox.showerror('尺寸不对', f'掩膜是 {im.size[0]}x{im.size[1]}，需要 {W}x{H}（和底图一样）')
            return None
        if p.parent.resolve() != self.base_dir.resolve():
            dst = self.base_dir / p.name
            if dst.exists() and not messagebox.askyesno('同名文件', f'场景目录里已有 {p.name}，覆盖吗？'):
                return None
            shutil.copy2(p, dst)
            self.log(f'已拷贝 {p.name} 到场景目录')
        self.mask_cache.pop(p.name, None)
        return p.name

    def add_mask(self):
        if not self.cfg:
            return
        name = self.pick_mask('选择掩膜图（白色 = 区域，黑色 = 不是；和底图同尺寸）')
        if not name:
            return
        p = self.params()
        src = {'type': 'mask', 'region': p['region'], 'file': name, 't0': p['t0']}
        if p['grade']:
            src.update(grade=p['grade'], t1=p['t1'])
        if p['rough']:
            src.update(rough=p['rough'], seed=len(self.stage['sources']) + 1)
        self.push_undo()
        self.stage['sources'].append(src)
        self.sel = ('src', len(self.stage['sources']) - 1)
        self.touch()
        self.select_in_list()

    def set_seed_mask(self):
        src = self.selected_src()
        if not src or src['type'] != 'seeds':
            messagebox.showinfo('先选种子点', '先在列表里选中一组种子点')
            return
        name = self.pick_mask('种子扩散的可通过范围（白色可通过，黑色挡住）')
        if name:
            self.push_undo()
            src['mask'] = name
            self.touch()

    def selected_src(self):
        if self.sel and self.sel[0] == 'src':
            return self.stage['sources'][self.sel[1]]
        return None

    def on_param(self, _=None):
        if self.busy_params or not self.sel:
            return
        p = self.params()
        if self.sel[0] == 'spot':
            spot = self.stage['spots'][self.sel[1]]
            if spot[2] != p['radius']:
                self.push_undo()
                spot[2] = p['radius']
                self.touch()
            return
        src = self.selected_src()
        before = copy.deepcopy(src)
        t = src['type']
        src['region'] = p['region']
        src['t0'] = p['t0']
        if t in ('polyline', 'outline'):
            src['width'] = p['width']
        if t in ('polyline', 'seeds') or src.get('grade') or p['grade']:
            src['t1'] = p['t1']
        if t == 'polyline':
            for line in src['lines']:
                if isinstance(line, dict):
                    line.pop('t0', None)
                    line.pop('t1', None)
        if t in ('polygon', 'mask'):
            if p['grade']:
                src['grade'] = p['grade']
            else:
                src.pop('grade', None)
            if p['rough']:
                src['rough'] = p['rough']
                src.setdefault('seed', self.sel[1] + 1)
            else:
                src.pop('rough', None)
        if t == 'seeds':
            if p['max_distance']:
                src['max_distance'] = p['max_distance']
            else:
                src.pop('max_distance', None)
        if src != before:
            self.undo_stack.append((self.stage_i, copy.deepcopy(self.cfg['stages']), None))
            self.undo_stack[-1][1][self.stage_i]['sources'][self.sel[1]] = before
            self.touch()

    def show_params(self):
        """Load the selected shape's values into the parameter fields."""
        self.busy_params = True
        try:
            if self.sel and self.sel[0] == 'spot':
                self.vars['radius'].set(self.stage['spots'][self.sel[1]][2])
            elif self.sel:
                src = self.selected_src()
                if src.get('region', 0) < len(self.region_cb['values']):
                    self.region_cb.current(src.get('region', 0))
                lines = src.get('lines') or [{}]
                first = lines[0] if isinstance(lines[0], dict) else {}
                self.vars['t0'].set(first.get('t0', src.get('t0', 0)))
                self.vars['t1'].set(first.get('t1', src.get('t1', 239)))
                self.vars['width'].set(src.get('width', 4 if src['type'] == 'polyline' else 3))
                self.vars['rough'].set(src.get('rough', 0))
                self.vars['max_distance'].set(src.get('max_distance', 0))
                self.grade_cb.set({v: k for k, v in GRADES.items()}.get(src.get('grade'), '无'))
        finally:
            self.busy_params = False

    # ------------------------------------------------------------ list
    def items(self):
        return ([('src', i) for i in range(len(self.stage['sources']))] +
                [('spot', i) for i in range(len(self.stage.get('spots') or []))])

    def refresh_list(self):
        self.listbox.delete(0, 'end')
        if not self.cfg:
            return
        names = region_names(self.stage['hazard'], self.stage['role'])
        for kind, i in self.items():
            if kind == 'spot':
                x, y, r = self.stage['spots'][i]
                self.listbox.insert('end', f'避险点 ({x}, {y}) 半径 {r}')
                continue
            s = self.stage['sources'][i]
            reg = s.get('region', 0)
            kind = '画笔' if str(s.get('file', '')).startswith(BRUSH_PREFIX) else TYPE_NAMES.get(s['type'], s['type'])
            text = f'{i + 1}. {kind} · {names[reg] if reg < 4 else reg}'
            if 't0' in s or 't1' in s:
                text += f' · t {s.get("t0", 0)}–{s.get("t1", 239)}'
            if s.get('file') or s.get('mask'):
                text += f' · {s.get("file") or s.get("mask")}'
            self.listbox.insert('end', text)
        self.select_in_list()

    def select_in_list(self):
        self.listbox.selection_clear(0, 'end')
        if self.sel in self.items():
            n = self.items().index(self.sel)
            self.listbox.selection_set(n)
            self.listbox.see(n)

    def on_list(self, _=None):
        cur = self.listbox.curselection()
        if not cur:
            return
        self.sel = self.items()[cur[0]]
        self.show_params()
        self.render()

    # ------------------------------------------------------------ mouse
    def to_img(self, e):
        return [max(0, min(W - 1, round(e.x / self.scale))), max(0, min(H - 1, round(e.y / self.scale)))]

    def vertices(self, sel):
        kind, i = sel
        if kind == 'spot':
            return [self.stage['spots'][i]]
        s = self.stage['sources'][i]
        if 'lines' in s:
            return [p for line in s['lines'] for p in line_points(line)]
        if 'points' in s:
            return s['points']
        if 'center' in s:
            return [s['center']]
        return []

    def nearest(self, xy, sels):
        best, dist = None, 10 / self.scale
        for sel in sels:
            for p in self.vertices(sel):
                d = ((p[0] - xy[0]) ** 2 + (p[1] - xy[1]) ** 2) ** 0.5
                if d <= dist:
                    best, dist = (sel, p), d
        return best

    def on_press(self, e):
        if not self.cfg:
            return
        xy = self.to_img(e)
        tool = self.tool.get()
        if tool in PAINT_TOOLS:
            self.start_stroke(xy)
            return
        if not self.pending:
            # Drawing tools drag only the selected shape's vertices; elsewhere a click is a new point.
            cands = self.items() if tool == 'select' else [self.sel] if self.sel else []
            hit = self.nearest(xy, cands)
            if hit:
                self.sel, self.drag = hit[0], hit[1]
                self.push_undo()
                self.refresh_list()
                self.show_params()
                self.render()
                return
        if tool == 'select':
            if self.sel:
                self.sel = None
                self.refresh_list()
                self.render()
            return
        if tool == 'spot':
            self.push_undo()
            self.stage.setdefault('spots', []).append([xy[0], xy[1], self.params()['radius']])
            self.sel = ('spot', len(self.stage['spots']) - 1)
            self.touch()
            return
        if self.sel and not self.pending:
            self.sel = None
            self.refresh_list()
            self.render()
            self.auto_region()
        self.pending.append(xy)
        self.draw_pending()

    def on_drag(self, e):
        if self.stroke:
            self.paint(self.to_img(e))
        elif self.drag is not None:
            self.drag[0], self.drag[1] = self.to_img(e)
            self.dirty = True
            self.render(fast=True)

    def on_release(self, _):
        if self.stroke:
            self.end_stroke()
        elif self.drag is not None:
            self.drag = None
            self.touch()

    def on_motion(self, e):
        if not self.cfg:
            return
        x, y = self.to_img(e)
        text = f'x {x}  y {y}'
        T = (self.t_cache.get(self.stage_i) or (None,))[0]
        if T is not None and T[y, x] != 255:
            v = int(T[y, x])
            names = region_names(self.stage['hazard'], self.stage['role'])
            text += f'   区域 {names[v >> 6]}，时刻 {(v & 63) * 4}'
        if self.pending:
            text += f'   已放 {len(self.pending)} 个点'
        self.status.config(text=text)
        self.draw_pending(cursor=(x, y))
        self.draw_brush_cursor((x, y))

    # ------------------------------------------------------------ brush
    @staticmethod
    def paint_key(src):
        """Field of `src` naming the mask the brush paints into, or None if it has none."""
        if src and src['type'] == 'mask':
            return 'file'
        if src and src['type'] == 'seeds':
            return 'mask'
        return None

    def references(self, name):
        return sum(s.get('file') == name or s.get('mask') == name
                   for st in self.cfg['stages'] for s in st['sources'])

    def new_brush_name(self):
        k = 1
        while True:
            name = f'{BRUSH_PREFIX}p{self.stage_i + 1}_{k}.png'
            if name not in self.brush and not (self.base_dir / name).exists() and not self.references(name):
                return name
            k += 1

    def load_brush(self, name):
        path = self.base_dir / name
        if not path.exists():
            self.log(f'找不到 {name}，从空白开始涂')
            return Image.new('L', (W, H), 0)
        im = Image.open(path).convert('L')
        if im.size != (W, H):
            im = im.resize((W, H), Image.NEAREST)
        return im.point(lambda v: 255 if v >= 128 else 0)

    def flush_tmp(self, name):
        self.brush[name].save(self.tmp / name)

    def start_stroke(self, xy):
        """Pick the mask this stroke paints into, creating or copying it first."""
        erase = self.tool.get() == 'eraser'
        src = self.selected_src()
        key = self.paint_key(src)
        name = src.get(key) if key else None
        if erase and not name:
            self.log('橡皮擦只擦选中的形状：先在列表里选中一块画笔区域、掩膜，或带种子掩膜的种子点')
            return
        if name in self.brush or (name and name.startswith(BRUSH_PREFIX) and self.references(name) == 1):
            if name not in self.brush:
                self.brush[name] = self.load_brush(name)
            self.push_undo((name, self.brush[name].copy()))
        elif name:
            # A mask painted elsewhere, or shared with other shapes: paint a copy.
            new = self.new_brush_name()
            self.push_undo((new, None))
            self.brush[new] = self.load_brush(name)
            src[key] = new
            self.log(f'为了不改动 {name}，复制成 {new} 再涂改')
            name = new
        else:
            name = self.new_brush_name()
            self.push_undo((name, None))
            self.brush[name] = Image.new('L', (W, H), 0)
            if key:     # seeds without a mask: paint where they may spread
                src['mask'] = name
            else:
                p = self.params()
                new_src = {'type': 'mask', 'region': p['region'], 'file': name, 't0': p['t0']}
                if p['grade']:
                    new_src.update(grade=p['grade'], t1=p['t1'])
                if p['rough']:
                    new_src.update(rough=p['rough'], seed=len(self.stage['sources']) + 1)
                self.stage['sources'].append(new_src)
                self.sel = ('src', len(self.stage['sources']) - 1)
                self.refresh_list()
        self.stroke = (name, 0 if erase else 255)
        self.last = None
        self.paint(xy)

    def paint(self, xy):
        name, value = self.stroke
        r = max(1, self.params()['brush'])
        d = ImageDraw.Draw(self.brush[name])
        if self.last:
            d.line([tuple(self.last), tuple(xy)], fill=value, width=2 * r)
        d.ellipse((xy[0] - r, xy[1] - r, xy[0] + r, xy[1] + r), fill=value)
        self.last = xy
        self.render(fast=True)
        self.draw_brush_cursor(xy)

    def end_stroke(self):
        name = self.stroke[0]
        self.stroke = self.last = None
        self.brush_dirty.add(name)
        self.flush_tmp(name)
        self.touch()

    def brush_size(self, step):
        v = self.vars['brush']
        v.set(max(2, min(60, self.params()['brush'] + step)))
        self.log(f'笔刷半径 {v.get()}')

    def draw_brush_cursor(self, xy):
        c, s = self.canvas, self.scale
        c.delete('brushcur')
        if self.tool.get() not in PAINT_TOOLS:
            return
        r = max(1, self.params()['brush']) * s
        x, y = xy[0] * s, xy[1] * s
        col = '#ff6060' if self.tool.get() == 'eraser' else 'white'
        c.create_oval(x - r, y - r, x + r, y + r, outline=col, tags='brushcur')

    def draw_pending(self, cursor=None):
        c, s = self.canvas, self.scale
        c.delete('pending')
        if not self.pending:
            return
        pts = [v * s for p in self.pending for v in p]
        if cursor:
            pts += [cursor[0] * s, cursor[1] * s]
        if len(pts) >= 4:
            c.create_line(*pts, fill='white', width=2, dash=(4, 3), tags='pending')
        for x, y in self.pending:
            c.create_rectangle(x * s - 3, y * s - 3, x * s + 3, y * s + 3, outline='black', fill='white',
                               tags='pending')

    # ------------------------------------------------------------ render
    def rgb(self, st):
        path = self.base_dir / st.get('image', self.cfg['base'])
        key = (path, path.stat().st_mtime)
        if key not in self.img_cache:
            im = Image.open(path).convert('RGB')
            if im.size != (W, H):
                im = im.resize((W, H))
                self.log(f'{path.name} 不是 {W}x{H}，预览先缩放；生成场景包会报错，请用“换底图…”重新导入')
            self.img_cache[key] = np.asarray(im, np.uint8)
        return self.img_cache[key]

    def stage_T(self):
        """(T, error) for the current stage; T is computed even when the evacuation check fails."""
        if self.stage_i not in self.t_cache:
            st, err = self.stage, None
            if self.brush:      # painted masks: read this session's copies, saved or not
                tmp = lambda s: {**s, **{k: str(self.tmp / s[k]) for k in ('file', 'mask') if s.get(k) in self.brush}}
                st = {**st, 'sources': [tmp(s) for s in st['sources']]}
            try:
                T = msp.stage_t3((H, W), st, self.base_dir)
            except SystemExit as e:
                err = str(e)
                try:
                    T = msp.stage_t3((H, W), {**st, 'role': 'none'}, self.base_dir)
                except SystemExit as e2:
                    T, err = None, str(e2)
            except Exception as e:      # a half-edited shape must not kill the tool
                T, err = None, f'{type(e).__name__}: {e}'
            self.t_cache[self.stage_i] = (T, err)
        return self.t_cache[self.stage_i]

    def colour(self, region):
        if self.stage['role'] == 'evacuation' and region in EVAC_COLORS:
            return EVAC_COLORS[region]
        return REGION_COLORS[region % 4]

    def mask_alpha(self, name, paint=False):
        if name in self.brush:
            return np.asarray(self.brush[name]) >= 128
        path = self.base_dir / name
        key = (name, path.stat().st_mtime, paint)
        if key not in self.mask_cache:
            g = np.asarray(Image.open(path).convert('L').resize((W, H)))
            self.mask_cache[key] = (g < 255) if paint else (g >= 128)
        return self.mask_cache[key]

    def draw_annotations(self, base):
        ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        for i, s in enumerate(self.stage['sources']):
            sel = self.sel == ('src', i)
            col = self.colour(s.get('region', 0))
            t = s['type']
            try:
                if t in ('mask', 'paint') or (t == 'seeds' and s.get('mask')):
                    hit = self.mask_alpha(s.get('file') or s['mask'], t == 'paint')
                    a = np.zeros((H, W, 4), np.uint8)
                    a[hit] = col + ((110 if sel else 70) if t != 'seeds' else 35,)
                    ov = Image.alpha_composite(ov, Image.fromarray(a))
                    d = ImageDraw.Draw(ov)
            except OSError as e:
                self.log(f'读不到 {e.filename}')
            pts = [tuple(p) for p in s.get('points', [])]
            if t in ('polygon', 'patches') and len(pts) >= 3:
                d.polygon(pts, fill=col + (110 if sel else 70,), outline=col + (255,))
            elif t == 'outline' and len(pts) >= 3:
                d.line(pts + [pts[0]], fill=col + (255,), width=s.get('width', 3) + (2 if sel else 0))
            elif t == 'seeds' or (pts and t not in ('polygon', 'outline')):
                for x, y in pts:
                    d.ellipse((x - 4, y - 4, x + 4, y + 4), outline=col + (255,), width=2)
                    d.line((x - 6, y, x + 6, y), fill=col + (255,))
                    d.line((x, y - 6, x, y + 6), fill=col + (255,))
            for line in s.get('lines', []):
                lp = [tuple(p) for p in line_points(line)]
                width = max(2, s.get('width', 4)) + (2 if sel else 0)
                d.line(lp, fill=col + (255,), width=width, joint='curve')
                (x0, y0), (x1, y1) = lp[0], lp[-1]
                d.ellipse((x0 - 4, y0 - 4, x0 + 4, y0 + 4), outline=(255, 255, 255, 255), width=2)  # 起点
                d.ellipse((x1 - 5, y1 - 5, x1 + 5, y1 + 5), fill=col + (255,), outline=(255, 255, 255, 255))  # 终点
            if 'center' in s:
                x, y = s['center']
                d.line((x - 8, y, x + 8, y), fill=col + (255,), width=2)
                d.line((x, y - 8, x, y + 8), fill=col + (255,), width=2)
        for i, (x, y, r) in enumerate(self.stage.get('spots') or []):
            sel = self.sel == ('spot', i)
            d.ellipse((x - r, y - r, x + r, y + r), fill=(0, 255, 0, 120 if sel else 80),
                      outline=(255, 255, 255, 255), width=3 if sel else 2)
        return Image.alpha_composite(base.convert('RGBA'), ov).convert('RGB')

    def render(self, fast=False):
        if not self.cfg:
            return
        st = self.stage
        rgb = self.rgb(st)
        mode = '标注' if fast else self.mode.get()
        t = int(self.t_now.get())
        self.t_lbl.config(text=f't = {t}（时刻 0–239，动画模式下拖动查看）' if mode == '动画' else '')
        if mode == '标注':
            img = self.draw_annotations(Image.fromarray(rgb))
        else:
            T, err = self.stage_T()
            if T is None:
                self.log(f'算不出 T：{err}')
                self.mode.set('标注')
                img = self.draw_annotations(Image.fromarray(rgb))
            elif mode == 'T 图':
                tm = msp.t_preview3(T)
                on = (T != 255)[..., None]
                img = Image.fromarray(np.where(on, (tm.astype(np.uint16) * 3 + rgb) // 4, rgb).astype(np.uint8))
            else:
                img = Image.fromarray(v3.render(rgb, T, st['hazard'], st['role'], t, self.fc))
        if self.sel and self.sel in self.items():
            d = ImageDraw.Draw(img)
            for x, y, *_ in self.vertices(self.sel):
                d.rectangle((x - 3, y - 3, x + 3, y + 3), fill='white', outline='black')
        if self.scale != 1:
            img = img.resize((int(W * self.scale), int(H * self.scale)), Image.BILINEAR)
        self.photo = ImageTk.PhotoImage(img)
        self.canvas.itemconfig(self.canvas_img, image=self.photo)
        self.canvas.tag_raise('pending')
        self.canvas.tag_raise('brushcur')

    def fit_screen(self):
        """Largest canvas scale whose window still fits on the screen."""
        r = self.root
        r.update_idletasks()
        cw, ch = self.canvas.winfo_reqwidth(), self.canvas.winfo_reqheight()
        extra_w, extra_h = r.winfo_reqwidth() - cw + 40, r.winfo_reqheight() - ch + 100   # borders, title, taskbar
        fit = [s for s in (2, 1.5, 1.25, 1) if W * s + extra_w <= r.winfo_screenwidth()
               and H * s + extra_h <= r.winfo_screenheight()]
        self.scale_cb.set(str(fit[0] if fit else 1))
        self.on_scale()
        r.update_idletasks()      # centre it, or the default position may push the right panels off screen
        x = max(0, (r.winfo_screenwidth() - r.winfo_reqwidth()) // 2)
        y = max(0, (r.winfo_screenheight() - r.winfo_reqheight()) // 3)
        r.geometry(f'+{x}+{y}')

    def on_scale(self, _=None):
        self.scale = float(self.scale_cb.get())
        self.canvas.config(width=int(W * self.scale), height=int(H * self.scale))
        self.draw_pending()
        self.render()

    def toggle_play(self):
        self.playing = not self.playing
        self.play_btn.config(text='暂停' if self.playing else '播放')
        if self.playing:
            self.mode.set('动画')
            self.tick()

    def tick(self):
        if not self.playing or not self.cfg:
            return
        self.t_now.set((int(self.t_now.get()) + 1) % 240)
        self.fc = (self.fc + 2) & 1023
        self.render()
        self.root.after(33, self.tick)

    # ------------------------------------------------------------ check / build
    def check_stage(self):
        if not self.cfg:
            return
        st = self.stage
        T, err = self.stage_T()
        self.log(f'— PIC{self.stage_i + 1} {ROLES.get(st["role"], st["role"])} —')
        if T is not None:
            names = region_names(st['hazard'], st['role'])
            for r in range(4):
                n = int((((T >> 6) == r) & (T != 255)).sum())
                if n:
                    self.log(f'{names[r]}：{n} 像素')
        if st['role'] == 'evacuation':
            has_danger = any(s.get('region') == v3.EVAC_DANGER for s in st['sources'])
            has_route = any(s.get('region') == v3.EVAC_ROUTE for s in st['sources'])
            if not has_danger:
                self.log('⚠ 没有标危险区（区域 1），无法检查路线是否避开危险区')
            if not has_route:
                self.log('⚠ 没有撤离路线（区域 0）')
            if not st.get('spots'):
                self.log('⚠ 没有避险点')
            if has_danger and not err:
                self.log('✓ 避险点在危险区外' + ('；路线离开危险区后没有再进入' if has_route else ''))
        if err:
            self.log(f'✗ {err}')
        if not st['sources'] and not st.get('spots'):
            self.log('本阶段没有标注')

    def generate(self):
        if not self.cfg or not self.save():
            return
        if FROZEN:
            cmd = [sys.executable, '--make-scene-pack', str(self.path), '--gif']
        else:
            cmd = [sys.executable, '-I', str(TOOLS_DIR / 'make_scene_pack.py'), str(self.path), '--gif']
        self.gen_btn.config(state='disabled')
        self.log('生成中…（gif 预览要一点时间）')

        result = []

        def run():          # worker thread: no Tk calls here
            env = {**os.environ, 'PYTHONIOENCODING': 'utf-8'}
            flags = subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0
            result.append(subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8',
                                         errors='replace', env=env, creationflags=flags))

        def poll():
            if not result:
                self.root.after(200, poll)
                return
            p = result[0]
            self.gen_btn.config(state='normal')
            self.log((p.stdout + p.stderr).strip())
            if p.returncode == 0:
                out = self.base_dir / self.cfg.get('output', 'out')
                self.log(f'✓ 完成。SD 卡文件：{out / "sd"}\\PIC1–4.BMP；总览 overview.png，动画 gif/')
            else:
                self.log('✗ 生成失败，见上面的报错')
        threading.Thread(target=run, daemon=True).start()
        self.root.after(200, poll)

    def open_out(self):
        if not self.cfg:
            return
        out = self.base_dir / self.cfg.get('output', 'out')
        if not out.exists():
            self.log('还没有输出目录，先生成场景包')
            return
        if sys.platform == 'win32':
            os.startfile(out)
        else:
            subprocess.Popen(['open' if sys.platform == 'darwin' else 'xdg-open', str(out)])


def main():
    if sys.argv[1:2] == ['--make-scene-pack']:     # the exe running make_scene_pack for 生成场景包
        for f in (sys.stdout, sys.stderr):
            if f:
                f.reconfigure(encoding='utf-8')
        sys.argv = ['make_scene_pack.py'] + sys.argv[2:]
        msp.main()
        return
    if sys.platform == 'win32':     # sharp text on scaled (125 %, 150 %) displays
        try:
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError, OSError):
            pass
    root = tk.Tk()
    App(root, sys.argv[1] if len(sys.argv) > 1 else None)
    root.mainloop()


if __name__ == '__main__':
    main()
