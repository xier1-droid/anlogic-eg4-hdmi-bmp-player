"""hazard_layer v3 reference model: cause -> hazard -> evacuation cards.

Per image (BMP header bytes 6-7): hazard type and role. Per pixel (T byte):
255 = no layer, otherwise region = T[7:6] (0-3) and time = T[5:0] (0-59, in
units of 4 t_now steps). All effects use integer shifts, masks and adds so the
RTL can match bit for bit. Draft: rain, evacuation, flood and landslide
are defined; debris flow and earthquake follow once their base images exist.
"""
import numpy as np

# Header byte 6: hazard type; byte 7: role.
HAZARDS = {'none': 0, 'landslide': 1, 'debris_flow': 2, 'flood': 3, 'earthquake': 4}
ROLES = {'none': 0, 'cause': 1, 'onset': 2, 'aftermath': 3, 'evacuation': 4}
T_NONE = 255
TIME_MAX = 59

# Evacuation regions.
EVAC_ROUTE, EVAC_DANGER, EVAC_REFUGE = 0, 1, 2
# Cause regions.
CAUSE_ZONE = 0          # outline of the hazard-prone area
# Landslide onset regions: crack, main scarp (grows downhill from the crack),
# slide body, rockfall paths. Aftermath: deposit, scar.
LS_CRACK, LS_SCARP, LS_BODY, LS_ROCKS = 0, 1, 2, 3
LS_DEPOSIT, LS_SCAR = 0, 1
LS_BODY_FROM = 96       # t_now when the slide body starts to move (rock paths join it)
LS_ROCKS_FROM = 120     # t_now when rocks start rolling

RAIN_NEAR, RAIN_FAR = (0xC8, 0xD2, 0xDC), (0xA8, 0xB4, 0xC0)
ZONE = (0xFF, 0xD0, 0x00)
DANGER = (0xD8, 0x20, 0x20)
ROUTE, DASH = (0x20, 0xC8, 0x48), (0xAA, 0xFF, 0xBE)
ROUTE_TIP, ROUTE_TIP_OFF = (0xFF, 0xFF, 0xFF), (0x40, 0xFF, 0x40)
REFUGE = (0x00, 0xFF, 0x00)
MUD, RIPPLE, FOAM = (0x8C, 0x6A, 0x3C), (0xC4, 0xA8, 0x74), (0xF0, 0xE8, 0xD6)
CRACK, CRACK_TIP = (0x18, 0x10, 0x08), (0xFF, 0xD0, 0x00)
SLIDE_DARK, SOIL = (0x3A, 0x2C, 0x1E), (0x9A, 0x78, 0x50)
ROCK, DUST = (0x50, 0x4C, 0x48), (0xB0, 0xA0, 0x88)
DEPOSIT, STONE, DEPOSIT_EDGE = (0x7A, 0x5E, 0x40), (0x62, 0x5E, 0x58), (0xB8, 0x9C, 0x78)


def hash8(a, b):
    """8-bit spatial hash from shifts, xors and constant multiplies."""
    h = (a * 73 + b * 151 + (a ^ b) * 37) & 255
    return h ^ (h >> 4)


def encode(region, time):
    return (region << 6) | min(int(time), TIME_MAX)


def blend(a, c, k):
    """k quarters of colour c: k=1 (a>>1)+(a>>2)+(c>>2), 2 (a>>1)+(c>>1), 3 (a>>2)+(c>>1)+(c>>2)."""
    a = a.astype(np.int32)
    c = np.asarray(c, np.int32)
    k = np.broadcast_to(np.asarray(k)[..., None] if np.ndim(k) else k, a.shape)
    out = np.where(k == 1, (a >> 1) + (a >> 2) + (c >> 2),
                   np.where(k == 2, (a >> 1) + (c >> 1), (a >> 2) + (c >> 1) + (c >> 2)))
    return out.astype(np.uint8)


# Rain: drops live on a grid that moves down-left with the frame counter, so
# every drop crosses the screen; a hash of the cell picks which cells hold a
# drop and where. Two layers: near (long, fast, bright) and far (short, slow,
# faint). fc is 10 bits, so the pattern repeats every 1024 frames (~17 s).
RAIN_LAYERS = (  # (cell w shift, cell h shift, length, vx, vy, salt, colour, blend)
    (4, 6, 14, 4, 16, 0, RAIN_NEAR, 2),
    (3, 5, 6, 2, 8, 53, RAIN_FAR, 1),
)


def rain_masks(x, y, fc, density):
    masks = []
    for sw, sh, length, vx, vy, salt, _, _ in RAIN_LAYERS:
        w, h = 1 << sw, 1 << sh
        u = (x + vx * fc) & 4095
        v = (y - vy * fc) & 16383
        cx, cy = u >> sw, v >> sh
        lu, lv = u & (w - 1), v & (h - 1)
        k = (cx * 167 + cy * 89 + salt) & 255
        hsh = k ^ (k >> 3)
        ox = (k >> 4) & (w // 2 - 1)
        oy = (k ^ (k >> 5)) & (h // 2 - 1)
        d = lv - oy
        on = (hsh < density) & (d >= 0) & (d < length) & (lu == ox + (length >> 2) - (d >> 2))
        masks.append(on)
    return masks


RAIN_LEVEL = {'cause': 2, 'onset': 1, 'aftermath': 1}


def rain_density(level, t_now):
    return (0, 28, 32 + (t_now >> 2))[level]


def render(rgb, T, hazard, role, t_now, fc, x=None, y=None):
    """rgb HxWx3 uint8, T HxW uint8, hazard/role names, t_now 0..239, fc 0..1023."""
    out = rgb.copy()
    if hazard == 'none' or role == 'none':
        return out
    if x is None:
        y, x = np.mgrid[0:T.shape[0], 0:T.shape[1]]
    T = T.astype(np.int32)
    layer = T != T_NONE
    region, time = T >> 6, T & 63
    t6 = t_now >> 2
    covered = layer & (time <= t6)
    age = (t6 - time) & 63
    slow = (fc >> 5) & 1
    fast = (fc >> (4, 4, 3, 2, 2)[ROLES[role]]) & 1

    level = RAIN_LEVEL.get(role, 0) if hazard != 'earthquake' else 0
    if level:
        for (*_, colour, k), m in zip(RAIN_LAYERS, rain_masks(x, y, fc, rain_density(level, t_now))):
            out[m] = blend(out[m], colour, k)

    if role == 'cause':
        # Hazard-prone outline: moving yellow dashes, blinking slowly.
        zone = layer & (region == CAUSE_ZONE) & ((((x + y) >> 2) - (fc >> 3)) & 3 < 2) & (slow == 1)
        out[zone] = blend(rgb[zone], ZONE, 3)

    elif role == 'evacuation':
        # Danger zone: sparse thin red hatching drifting slowly, base image untouched between.
        dz = layer & (region == EVAC_DANGER)
        hatch = dz & ((((x + y) + (fc >> 2)) & 31) < 3)
        out[hatch] = blend(rgb[hatch], DANGER, 3)
        route = covered & (region == EVAC_ROUTE)
        front = route & (age < 2)
        body = route & ~front
        dash = body & ((((time << 2) - (fc >> 1)) & 7) < 3)
        out[front] = ROUTE_TIP if fast else ROUTE_TIP_OFF
        out[dash] = DASH
        m = body & ~dash
        out[m] = blend(rgb[m], ROUTE, 3)
        refuge = layer & (region == EVAC_REFUGE) & (slow == 1)
        out[refuge] = REFUGE

    elif hazard == 'landslide' and role == 'onset':
        crack = covered & (region == LS_CRACK)
        tip = crack & (age < 2) & (fast == 1)
        out[crack & ~tip] = blend(rgb[crack & ~tip], CRACK, 3)
        out[tip] = blend(rgb[tip], CRACK_TIP, 2)
        # Main scarp: fresh soil exposed below the crack, growing downhill as
        # the body drops away; a darker lip marks its growing lower edge.
        scarp = covered & (region == LS_SCARP)
        lip = scarp & (age < 2)
        out[scarp & ~lip] = blend(rgb[scarp & ~lip], SOIL, 3)
        out[lip] = blend(rgb[lip], SLIDE_DARK, 2)
        # Slide body (rock paths are part of it) darkens as it sinks; the base
        # image's own stones stay visible through the blend.
        path = layer & (region == LS_ROCKS)
        body = (covered & (region == LS_BODY)) | (path & (t_now >= LS_BODY_FROM))
        body_age = np.where(region == LS_ROCKS, (t6 - (LS_BODY_FROM >> 2)) & 63, age)
        k = np.where(body_age < 12, 1, 2)
        out[body] = blend(rgb[body], SLIDE_DARK, k[body])
        # Rocks: two per path, rolling down every 128 frames once the slide moves.
        if t_now >= LS_ROCKS_FROM:
            p = (fc >> 1) & 63
            lead = ((time - p) & 63) < 2
            lead |= ((time - p - 30) & 63) < 2
            trail = ((((p - time) & 63) - 1) & 63) < 3
            trail |= ((((p + 30 - time) & 63) - 1) & 63) < 3
            out[path & trail & ~lead] = blend(out[path & trail & ~lead], DUST, 2)
            out[path & lead] = ROCK

    elif hazard == 'landslide' and role == 'aftermath':
        # 1-px gravel from a spatial hash: dark stones and pale grit.
        g = hash8(x, y)
        stone, grit = g < 28, (g >= 28) & (g < 52)
        # Scarp: fresh soil with gravel.
        scar = layer & (region == LS_SCAR)
        out[scar & ~stone] = blend(rgb[scar & ~stone], SOIL, 2)
        out[scar & stone] = blend(rgb[scar & stone], STONE, 2)
        # Deposit: mostly opaque earth (a quarter of the base texture shows),
        # with gravel and a paler advancing edge.
        dep = covered & (region == LS_DEPOSIT)
        edge = dep & (age < 2)
        body = dep & ~edge
        m = body & ~stone & ~grit
        out[m] = blend(rgb[m], DEPOSIT, 3)
        out[body & stone] = blend(rgb[body & stone], STONE, 3)
        out[body & grit] = blend(rgb[body & grit], DEPOSIT_EDGE, 3)
        out[edge] = blend(rgb[edge], DEPOSIT_EDGE, 2)

    elif hazard == 'flood' and role in ('onset', 'aftermath'):
        if role == 'aftermath':
            covered, age = layer, (63 - time)          # the whole extent, deepest where earliest
        water = covered & (region == 0)
        front = water & (age < 2) if role == 'onset' else water & False
        body = water & ~front
        k = np.where(age < 6, 1, np.where(age < 16, 2, 3))
        ripple = ((((time << 2) - (fc >> 1)) & 15) < 2)
        for colour, m in ((RIPPLE, body & ripple), (MUD, body & ~ripple)):
            out[m] = blend(rgb[m], colour, k[m])
        out[front] = blend(rgb[front], FOAM, 2 if fast else 1)
    return out
