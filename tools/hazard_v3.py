"""hazard_layer v3 reference model: cause -> hazard -> evacuation cards.

Per image (BMP header bytes 6-7): hazard type and role. Per pixel (T byte):
255 = no layer, otherwise region = T[7:6] (0-3) and time = T[5:0] (0-59, in
units of 4 t_now steps). All effects use integer shifts, masks and adds so the
RTL can match bit for bit. Rain, evacuation, flood, landslide, debris
flow and earthquake are defined.
"""
import numpy as np

# Header byte 6: hazard type; byte 7: role.
HAZARDS = {'none': 0, 'landslide': 1, 'debris_flow': 2, 'flood': 3, 'earthquake': 4}
ROLES = {'none': 0, 'cause': 1, 'onset': 2, 'aftermath': 3, 'evacuation': 4}
T_NONE = 255
TIME_MAX = 59
SPECIAL = 60            # time 60..63: per-region special codes, never "covered"

# Evacuation regions.
EVAC_ROUTE, EVAC_DANGER, EVAC_REFUGE = 0, 1, 2
# Cause regions.
CAUSE_ZONE = 0          # outline of the hazard-prone area
# Landslide onset regions: cracks, fresh soil (scarp, bare patches, toe),
# slide body, rockfall paths. Aftermath: deposit, scar.
LS_CRACK, LS_SCARP, LS_BODY, LS_ROCKS = 0, 1, 2, 3
LS_DEPOSIT, LS_SCAR = 0, 1
LS_BODY_FROM = 64       # t_now when the slide body starts to move (rock paths join it)
LS_ROCKS_FROM = 80      # t_now when rocks start rolling
LS_DUST_FROM = 140      # t_now when dust starts rising at the slope foot (dense first)
# Flood onset regions: flooded fields, river channel, overtopped bank top.
FL_LAND, FL_RIVER, FL_SPILL = 0, 1, 2
# Earthquake cause (geological map): fault band, white ring, dark ring
# outline, wave field (time = distance from the mainshock).
EQ_FAULT, EQ_RING, EQ_RING_EDGE, EQ_WAVE = 0, 1, 2, 3
EQ_MAIN = 96            # t_now of the mainshock
# Earthquake onset (close-up): cracks, dust (special codes), collapsing
# house, rockfall paths. Aftermath: debris, ground crack, rubble.
EQ_CRACK, EQ_DUST, EQ_COLLAPSE, EQ_ROCKS = 0, 1, 2, 3
EQ_SHOCK = 40           # t_now the shaking starts in the close-up
EQ_DEBRIS, EQ_GCRACK, EQ_RUBBLE = 0, 1, 2
# Debris flow onset regions: slurry, mud on the banks. Aftermath: fan, filled bed.
DF_FLOW, DF_BANK = 0, 1
DF_FAN, DF_BED = 0, 1

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
SLURRY, SURGE, HEAD = (0x4E, 0x3A, 0x26), (0x7E, 0x62, 0x42), (0x34, 0x28, 0x1C)
BOULDER, WET_MUD = (0x58, 0x54, 0x50), (0x5A, 0x44, 0x2E)
FAULT_GLOW, RING_WHITE, RING_DARK = (0xE8, 0x30, 0x20), (0xFA, 0xFA, 0xFA), (0x18, 0x18, 0x18)
QUAKE_NEW = (0xFF, 0xE0, 0x40)
TILE, WALL, GAP = (0x40, 0x42, 0x44), (0xA4, 0x96, 0x80), (0x1E, 0x1A, 0x16)
ROCK_LIGHT = (0x8E, 0x8A, 0x84)


def hash8(a, b):
    """8-bit spatial hash from shifts, xors and constant multiplies."""
    h = (a * 73 + b * 151 + (a ^ b) * 37) & 255
    return h ^ (h >> 4)


def vnoise(u, v, sx, sy, salt):
    """Smooth 8-bit value noise: hash8 lattice with cells of 2^sx x 2^sy px,
    bilinear with 4-bit weights (RTL: 4 hashes, 3 small multiplies)."""
    cx, cy = (u >> sx) & 255, ((v >> sy) + salt) & 255
    fx = ((u << 4) >> sx) & 15
    fy = ((v << 4) >> sy) & 15
    h00, h10 = hash8(cx, cy), hash8((cx + 1) & 255, cy)
    h01, h11 = hash8(cx, (cy + 1) & 255), hash8((cx + 1) & 255, (cy + 1) & 255)
    a = h00 + (((h10 - h00) * fx) >> 4)
    b = h01 + (((h11 - h01) * fx) >> 4)
    return a + (((b - a) * fy) >> 4)


def rubble(a, x, y):
    """Collapsed building: broken roof tiles, wall chunks and dark gaps in
    2-4 px clumps, 1 px grit; a quarter of the base texture shows."""
    n = vnoise(x & 4095, y & 1023, 2, 2, 71)
    g = hash8(x & 255, y & 255)
    out = np.where((n < 70)[:, None], blend(a, GAP, 2),
                   np.where((n < 150)[:, None], blend(a, TILE, 2), blend(a, WALL, 2)))
    grit = g < 24
    out[grit] = blend(a[grit], STONE, 2)
    return out


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

    if hazard == 'earthquake' and role == 'cause':
        # Seismicity map. The fault band glows faintly while foreshocks occur
        # and pulses red after the mainshock. Each event is a hollow white
        # circle with a thin dark outline, appearing at its time (new ones
        # flash yellow briefly); the mainshock sends rings outward.
        main6 = EQ_MAIN >> 2
        fault = layer & (region == EQ_FAULT)
        if t_now >= EQ_MAIN:
            out[fault] = blend(rgb[fault], FAULT_GLOW, 3 if fast else 2)
        elif t_now >= 16:
            out[fault] = blend(rgb[fault], FAULT_GLOW, 1 + slow)
        wave = layer & (region == EQ_WAVE)
        k = t6 - main6 - time
        front = wave & (k >= 0) & (k < 24) & ((k % 6) == 0)
        out[front] = blend(rgb[front], RING_WHITE, 1)
        edge = covered & (region == EQ_RING_EDGE)
        out[edge] = blend(rgb[edge], RING_DARK, 2)
        ring = covered & (region == EQ_RING)
        new = ring & (age < 2)
        out[ring & ~new] = blend(rgb[ring & ~new], RING_WHITE, 3)
        out[new] = QUAKE_NEW

    elif role == 'cause':
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
        # Realistic close-up, no warning colours. All shapes come from the
        # scene tool; here pixels only appear by time and take a tint that
        # keeps part of the base texture.
        # Cracks (main scarp crown, transverse and flank cracks): dark.
        crack = covered & (region == LS_CRACK)
        out[crack] = blend(rgb[crack], CRACK, np.where(age[crack] < 2, 2, 3))
        # Fresh soil (main scarp, bare patches, toe bulge): lighter earth.
        # Late, small exposures (bare patches, toe) stay light; the main scarp,
        # exposed early, deepens to k=2.
        soil = covered & (region == LS_SCARP)
        out[soil] = blend(rgb[soil], SOIL, np.where(age[soil] < 12, 1, 2))
        # Slide body: each pixel starts to sink at its own time, top first;
        # it darkens in two steps so the front stays soft.
        body = covered & (region == LS_BODY)
        out[body] = blend(rgb[body], SLIDE_DARK, np.where(age[body] < 4, 1, 2))
        # Rock paths lie inside the body and sink with it: approximate the
        # body's top-down front by row, LS_BODY_FROM + y/4 - 16.
        path = layer & (region == LS_ROCKS)
        sunk = path & (t_now + 16 >= LS_BODY_FROM + (y >> 2))
        out[sunk] = blend(rgb[sunk], SLIDE_DARK, 2)
        # Dust at the slope foot (soil region, special codes 60..63 = density
        # 0..3): denser codes appear first, then thinner ones further up; a
        # 1-px grain drifts upward over a light haze.
        dust = layer & (region == LS_SCARP) & (time >= SPECIAL)
        level = time - SPECIAL
        # Levels open 16 steps apart; the grain thickens for ~64 steps after.
        shown = dust & (t_now >= LS_DUST_FROM + ((3 - level) << 4))
        haze = shown & (level == 3)
        out[haze] = blend(out[haze], DUST, 1)
        grow = np.minimum(np.maximum(t_now - LS_DUST_FROM, 0) >> 2, 16)
        grain = shown & (hash8(x, (y + (fc >> 1)) & 255) < 4 + (level << 4) + grow)
        out[grain] = blend(out[grain], DUST, 2)
        # Falling rocks: times along each path grow with sqrt(distance), so a
        # rock at constant phase speed accelerates downhill. Two rocks per path;
        # paths start and end at different times, so rocks set off at
        # different moments and fall at different speeds.
        if t_now >= LS_ROCKS_FROM:
            p = (fc >> 1) & 63
            lead = ((time - p) & 63) == 0
            lead |= ((time - p - 32) & 63) == 0
            puff = (((p - time) & 63) == 1) | (((p + 32 - time) & 63) == 1)
            out[path & puff & ~lead] = blend(out[path & puff & ~lead], DUST, 1)
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

    elif hazard == 'earthquake' and role == 'onset':
        # Wall and ground cracks open after the shock.
        crack = covered & (region == EQ_CRACK)
        out[crack] = blend(rgb[crack], CRACK, np.where(age[crack] < 2, 2, 3))
        # A weak house collapses from the roof down into a heap of broken
        # tiles, wall chunks and dark gaps (smooth-noise clumps, 1 px grit).
        col = covered & (region == EQ_COLLAPSE)
        out[col] = rubble(rgb[col], x[col], y[col])
        # Rocks shaken loose from the scree roll down onto the top row.
        path = layer & (region == EQ_ROCKS)
        if t_now >= EQ_SHOCK + 16:
            p = (fc >> 1) & 63
            lead = (((time - p) & 63) == 0) | (((time - p - 32) & 63) == 0)
            puff = (((p - time) & 63) == 1) | (((p + 32 - time) & 63) == 1)
            out[path & puff & ~lead] = blend(out[path & puff & ~lead], DUST, 1)
            out[path & lead] = ROCK
        # Dust (special codes) rises from the collapse and the scree foot.
        dust = layer & (region == EQ_DUST) & (time >= SPECIAL)
        level = time - SPECIAL
        shown = dust & (t_now >= EQ_SHOCK + 24 + ((3 - level) << 4))
        haze = shown & (level >= 2)
        out[haze] = blend(out[haze], WALL, np.where(level[haze] == 3, 2, 1))
        grow = np.minimum(np.maximum(t_now - EQ_SHOCK - 24, 0) >> 2, 16)
        grain = shown & (hash8(x, (y + (fc >> 1)) & 255) < 4 + (level << 4) + grow)
        out[grain] = blend(out[grain], DUST, 2)
        # The whole frame shakes left and right, decaying in four steps.
        amp = 0 if t_now < EQ_SHOCK else max(0, 4 - ((t_now - EQ_SHOCK) >> 5))
        s = (0, 1, 0, -1)[fc & 3] * amp
        if s:
            out = np.concatenate([np.repeat(out[:, :1], s, 1), out[:, :-s]], 1) if s > 0 else \
                np.concatenate([out[:, -s:], np.repeat(out[:, -1:], -s, 1)], 1)

    elif hazard == 'earthquake' and role == 'aftermath':
        # Debris from the collapsed cliff covers the foot of the slope and the
        # top row of houses; a fresh crack runs along the fault trace; a few
        # houses are rubble.
        # Rock debris: a fresh light-grey rock tint over the base texture,
        # lighter and darker in broad smooth patches, 1 px dark grit; a dusty
        # advancing edge.
        deb = covered & (region == EQ_DEBRIS)
        edge = deb & (age < 2)
        body = deb & ~edge
        n = vnoise(x & 4095, y & 1023, 4, 4, 61)
        lite = body & (n >= 128)
        out[lite] = blend(rgb[lite], ROCK_LIGHT, 2)
        out[body & ~lite] = blend(rgb[body & ~lite], STONE, 2)
        grit = body & (hash8(x, y) < 18)
        out[grit] = blend(rgb[grit], GAP, 1)
        out[edge] = blend(rgb[edge], WALL, 2)
        gc = covered & (region == EQ_GCRACK)
        out[gc] = blend(rgb[gc], CRACK, 3)
        rub = layer & (region == EQ_RUBBLE)
        out[rub] = rubble(rgb[rub], x[rub], y[rub])

    elif hazard == 'debris_flow' and role == 'onset':
        # Slurry coats the gully bed: a half blend keeps the bed's own boulders
        # visible as stones carried in the mud. Surge fronts follow the
        # arrival-time contours (gentle lobes) and move downstream; the head
        # is a darker, denser band.
        flow = covered & (region == DF_FLOW)
        head = flow & (age < 3)
        body = flow & ~head
        surge = body & ((((time << 2) - (fc >> 1)) & 31) < 4)
        out[body & ~surge] = blend(rgb[body & ~surge], SLURRY, 2)
        out[surge] = blend(rgb[surge], SURGE, 2)
        out[head] = blend(rgb[head], HEAD, 3)
        # Mud splashed on the banks once the head has passed; fresh splashes
        # are darker, then dry to a thin stain.
        bank = covered & (region == DF_BANK)
        out[bank] = blend(rgb[bank], WET_MUD, np.where(age[bank] < 4, 2, 1))

    elif hazard == 'debris_flow' and role == 'aftermath':
        # Wet debris buries the fan: fresh deposit dark wet mud, older deposit
        # drying lighter; sparse 1 px gravel and a few 2 px boulders.
        stone = hash8(x, y) < 18
        big = hash8(x >> 1, y >> 1) < 8
        bed = layer & (region == DF_BED)
        out[bed] = blend(rgb[bed], SLURRY, 2)
        fan = covered & (region == DF_FAN)
        fresh = fan & (age < 10)
        dry = fan & ~fresh
        out[fresh & ~stone & ~big] = blend(rgb[fresh & ~stone & ~big], WET_MUD, 3)
        # Successive surges leave lobes: alternate tones every 4 time steps.
        lobe = ((time >> 2) & 1) == 1
        out[dry & lobe & ~stone & ~big] = blend(rgb[dry & lobe & ~stone & ~big], DEPOSIT, 3)
        out[dry & ~lobe & ~stone & ~big] = blend(rgb[dry & ~lobe & ~stone & ~big], DEPOSIT, 2)
        out[fan & stone & ~big] = blend(rgb[fan & stone & ~big], STONE, 3)
        out[fan & big] = blend(rgb[fan & big], BOULDER, 3)

    elif hazard == 'flood' and role == 'onset':
        # Broken water from smooth noise in cells 32 px along the flow by 4 px
        # across, sliding downstream: high values are white foam, the band
        # below is lighter rough water.
        def rough_water(speed, salt):
            return vnoise((x - speed * fc) & 4095, y & 1023, 5, 2, salt)
        # River channel (FL_RIVER): a flood wave sweeps downstream (left to
        # right); its head is a dark churning band; behind it the water is
        # muddier, keeps the base image's rapids, and carries foam patches.
        river = covered & (region == FL_RIVER)
        rhead = river & (age == 0)
        rbody = river & ~rhead
        n = rough_water(6, 3)
        out[rbody] = blend(rgb[rbody], MUD, 1)
        m = rbody & (n >= 150) & (n < 185)
        out[m] = blend(rgb[m], RIPPLE, 1)
        m = rbody & (n >= 185)
        out[m] = blend(rgb[m], FOAM, 2)
        out[rhead] = blend(rgb[rhead], MUD, 2)
        m = rhead & (n >= 120)
        out[m] = blend(rgb[m], FOAM, 2)
        # Bank top (FL_SPILL): where the river overtops the bank, water pours
        # over as falling spray.
        spill = covered & (region == FL_SPILL)
        pour = spill & (vnoise(x & 4095, (y - 3 * fc) & 1023, 3, 1, 9) >= 165)
        out[spill & ~pour] = blend(rgb[spill & ~pour], MUD, 2)
        out[pour] = blend(rgb[pour], FOAM, 2)
        # Fields (FL_LAND): muddy water spreading from the overflow, upstream
        # end first; rough patches run downstream; a thin churning front.
        land = covered & (region == FL_LAND)
        front = land & (age == 0)
        body = land & ~front
        k = np.where(age < 4, 1, 2)
        out[body] = blend(rgb[body], MUD, k[body])
        n = rough_water(3, 17)
        m = body & (n >= 190)
        out[m] = blend(rgb[m], RIPPLE, 1)
        churn = front & (vnoise(x & 4095, (y + fc) & 1023, 2, 2, 23) >= 110)
        out[front & ~churn] = blend(rgb[front & ~churn], FOAM, 1)
        out[churn] = blend(rgb[churn], FOAM, 2 if fast else 1)

    elif hazard == 'flood' and role == 'aftermath':
        # Whole extent; time is the distance from the river centre line, so
        # the channel is deep and the overbank shallow. Small foam flecks
        # drift downstream (lower right).
        water = layer & (region == 0)
        k = np.where(time < 12, 2, 1)
        out[water] = blend(rgb[water], MUD, k[water])
        fleck = water & (hash8(((x - fc) >> 1) & 255, ((y - (fc >> 1)) >> 1) & 255) < 10)
        out[fleck] = blend(rgb[fleck], RIPPLE, 2)
    return out
