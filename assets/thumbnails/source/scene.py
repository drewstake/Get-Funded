"""Get Funded! thumbnail scenes (Blender 5 / bpy, Cycles CPU).
usage: python3 scene.py <focus|win|challenge> <res_pct> <samples> <out.png>
"""
import bpy, math, sys, os
from mathutils import Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "tex")
SCENE = sys.argv[1] if len(sys.argv) > 1 else "focus"
RES = int(sys.argv[2]) if len(sys.argv) > 2 else 25
SAMPLES = int(sys.argv[3]) if len(sys.argv) > 3 else 16
OUTP = sys.argv[4] if len(sys.argv) > 4 else f"/tmp/{SCENE}.png"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
D = bpy.data
R = math.radians


# ------------------------------------------------------------ materials
def rgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c] + [1]


_mats = {}


def mat(name, col, rough=0.42, metal=0.0, emit=None, estr=0.0, coat=0.25, spec=0.5):
    if name in _mats:
        return _mats[name]
    m = D.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = rgb(col)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.15
    if emit:
        b.inputs["Emission Color"].default_value = rgb(emit)
        b.inputs["Emission Strength"].default_value = estr
    _mats[name] = m
    return m


def emit_mat(name, col, strength):
    m = D.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = rgb(col)
    e.inputs[1].default_value = strength
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def image_emit_mat(name, path, strength, alpha=False):
    m = D.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = D.images.load(path)
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[1].default_value = strength
    nt.links.new(t.outputs[0], e.inputs[0])
    if alpha:
        mix = nt.nodes.new("ShaderNodeMixShader")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        nt.links.new(t.outputs[1], mix.inputs[0])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(e.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], o.inputs[0])
    else:
        nt.links.new(e.outputs[0], o.inputs[0])
    return m


def decal_mat(name, path, rough=0.4):
    """Image with alpha over nothing (for faces / patches), lit normally."""
    m = D.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = D.images.load(path)
    t.interpolation = "Cubic"
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = 0.3
    nt.links.new(t.outputs[0], b.inputs["Base Color"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(t.outputs[1], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(b.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], o.inputs[0])
    return m


# ------------------------------------------------------------ geometry helpers
def empty(name, loc=(0, 0, 0), rot=(0, 0, 0), parent=None):
    e = D.objects.new(name, None)
    sc.collection.objects.link(e)
    e.location = loc
    e.rotation_euler = [R(a) for a in rot]
    if parent:
        e.parent = parent
    return e


def box(name, size, loc, m, rot=(0, 0, 0), bevel=0.06, seg=3, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.location = loc
    o.rotation_euler = [R(a) for a in rot]
    if bevel:
        bv = o.modifiers.new("bv", "BEVEL")
        bv.width = bevel
        bv.segments = seg
        bv.limit_method = "NONE"
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    if parent:
        o.parent = parent
    return o


def cyl(name, r, depth, loc, m, rot=(0, 0, 0), verts=32, parent=None, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.location = loc
    o.rotation_euler = [R(a) for a in rot]
    if bevel:
        bv = o.modifiers.new("bv", "BEVEL")
        bv.width = bevel
        bv.segments = 3
        bv.limit_method = "ANGLE"
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    if parent:
        o.parent = parent
    return o


def plane(name, w, h, loc, m, rot=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = (w, h, 1)
    bpy.ops.object.transform_apply(scale=True)
    o.location = loc
    o.rotation_euler = [R(a) for a in rot]
    o.data.materials.append(m)
    if parent:
        o.parent = parent
    return o


def sphere(name, r, loc, m, parent=None, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=32, ring_count=16)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    if parent:
        o.parent = parent
    return o


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def area(name, loc, target, energy, col, size=1.0, size_y=None, shape="RECTANGLE"):
    l = D.lights.new(name, "AREA")
    l.energy = energy
    l.color = rgb(col)[:3]
    l.shape = shape
    l.size = size
    l.size_y = size_y or size
    o = D.objects.new(name, l)
    sc.collection.objects.link(o)
    o.location = loc
    look_at(o, target)
    return o


def point(name, loc, energy, col, radius=0.2):
    l = D.lights.new(name, "POINT")
    l.energy = energy
    l.color = rgb(col)[:3]
    l.shadow_soft_size = radius
    o = D.objects.new(name, l)
    sc.collection.objects.link(o)
    o.location = loc
    return o


# ------------------------------------------------------------ palette
SKIN = mat("skin", "#F4BB8A", rough=0.4, coat=0.3)
JACKET = mat("jacket", "#7B3CFF", rough=0.5, coat=0.15)
JACKET_D = mat("jacket_dark", "#4B1FB0", rough=0.5)
GOLDM = mat("gold", "#FFC53A", rough=0.22, metal=0.85, coat=0.4)
TEE = mat("tee", "#F4F1FF", rough=0.6)
PANTS = mat("pants", "#16204A", rough=0.55)
SHOE = mat("shoe", "#FFFFFF", rough=0.45)
SOLE = mat("sole", "#22E07A", rough=0.4)
HAIR = mat("hair", "#FF7A1A", rough=0.4, coat=0.4)
HEADSET = mat("headset", "#1A1D33", rough=0.35, coat=0.4)
CYANM = mat("cyan", "#12D9FF", rough=0.3, emit="#12D9FF", estr=1.5)
DESK = mat("desk", "#1C1640", rough=0.35, coat=0.5)
DESK_TOP = mat("desk_top", "#2A2160", rough=0.28, coat=0.6)
BLACK = mat("black", "#0C0C18", rough=0.3, coat=0.5)
CHAIR = mat("chair", "#161229", rough=0.45)
CHAIR_ACC = mat("chair_acc", "#8A45FF", rough=0.4)
WALL = mat("wall", "#2A1E70", rough=0.8, coat=0)
WALL2 = mat("wall2", "#241A66", rough=0.8, coat=0)
FLOOR = mat("floor", "#1A1438", rough=0.25, coat=0.6)
WOOD = mat("shelf", "#3A2A7A", rough=0.5)
PLANT = mat("plant", "#27C46A", rough=0.5)
POT = mat("pot", "#FF6FA8", rough=0.4)
MUG = mat("mug", "#FFFFFF", rough=0.3)
RGB_KEYS = emit_mat("rgbkeys", "#A060FF", 3.0)

# ------------------------------------------------------------ character "Ticker"
def build_character(pose):
    root = empty("char_root", (0, 0, 0))
    hips = empty("hips", (0, 0, 1.85), parent=root)
    # torso pivot at hips so the whole upper body can lean
    torso = empty("torso", (0, 0, 0), rot=(pose.get("lean", 0), 0, pose.get("twist", 0)), parent=hips)
    box("torso_mesh", (2.0, 1.0, 2.0), (0, 0, 1.0), JACKET, parent=torso, bevel=0.1)
    # open jacket showing tee + gold zipper line
    box("tee", (0.62, 0.06, 1.72), (0, 0.49, 1.02), TEE, parent=torso, bevel=0.03)
    box("collar_l", (0.5, 0.14, 0.34), (-0.42, 0.46, 1.86), JACKET_D, rot=(0, 0, 0), parent=torso, bevel=0.05)
    box("collar_r", (0.5, 0.14, 0.34), (0.42, 0.46, 1.86), JACKET_D, parent=torso, bevel=0.05)
    box("hem", (2.02, 1.02, 0.22), (0, 0, 0.12), JACKET_D, parent=torso, bevel=0.06)
    # gold candle patch on chest (3D emblem: three rising candles)
    patch = empty("patch", (0.62, 0.52, 1.28), parent=torso)
    cyl("patch_disc", 0.26, 0.05, (0, 0, 0), GOLDM, rot=(90, 0, 0), parent=patch, bevel=0.01)
    for i, (x, hgt, z) in enumerate(((-0.11, 0.12, -0.05), (0, 0.18, 0.0), (0.11, 0.26, 0.05))):
        box(f"pc{i}", (0.07, 0.04, hgt), (x, 0.04, z), SOLE, parent=patch, bevel=0.01)
    # gold trim stripes on the sleeves are added on arms
    # ---- head
    neck = empty("neck", (0, 0, 2.0), rot=(pose.get("head_pitch", 0), pose.get("head_roll", 0), pose.get("head_yaw", 0)), parent=torso)
    neck.scale = (1.13, 1.13, 1.13)
    box("neck_mesh", (0.6, 0.6, 0.2), (0, 0, 0.08), SKIN, parent=neck, bevel=0.05)
    head = box("head", (1.34, 1.24, 1.24), (0, 0, 0.78), SKIN, parent=neck, bevel=0.3, seg=5)
    face = plane("face", 1.2, 1.2, (0, 0.623, 0.72), decal_mat("face_m", os.path.join(TEX, f"face_{pose['face']}.png")),
                 rot=(90, 0, 180), parent=neck)
    # blocky hair: top slab + swoosh blocks
    box("hair_top", (1.44, 1.34, 0.34), (0, -0.02, 1.43), HAIR, parent=neck, bevel=0.12)
    box("hair_back", (1.44, 0.34, 0.9), (0, -0.52, 1.1), HAIR, parent=neck, bevel=0.1)
    box("hair_sw1", (0.62, 0.42, 0.3), (0.28, 0.46, 1.62), HAIR, rot=(0, -14, 8), parent=neck, bevel=0.1)
    box("hair_sw2", (0.46, 0.36, 0.24), (-0.18, 0.5, 1.58), HAIR, rot=(0, 16, -10), parent=neck, bevel=0.09)
    box("hair_sw3", (0.34, 0.3, 0.22), (0.6, 0.3, 1.7), HAIR, rot=(0, -30, 20), parent=neck, bevel=0.08)
    # headset: band over the head + cups + mic
    band = box("band", (1.62, 0.2, 0.14), (0, 0.02, 1.64), HEADSET, parent=neck, bevel=0.06)
    for s in (-1, 1):
        box(f"band_side{s}", (0.14, 0.2, 0.62), (s * 0.78, 0.02, 1.34), HEADSET, parent=neck, bevel=0.05)
        cup = cyl(f"cup{s}", 0.3, 0.2, (s * 0.76, 0.02, 0.86), HEADSET, rot=(0, 90, 0), parent=neck, bevel=0.05)
        cyl(f"cupring{s}", 0.31, 0.06, (s * 0.87, 0.02, 0.86), CYANM, rot=(0, 90, 0), parent=neck)
    boom = cyl("boom", 0.04, 0.62, (0.74, 0.34, 0.62), HEADSET, rot=(62, 0, -8), parent=neck)
    sphere("mic", 0.08, (0.66, 0.62, 0.48), CYANM, parent=neck)

    # ---- arms (pivot at shoulder)
    def arm(side, rot):
        sh = empty(f"shoulder{side}", (side * 1.5, 0, 1.8), rot=rot, parent=torso)
        box(f"sleeve{side}", (1.0, 1.0, 1.36), (0, 0, -0.62), JACKET, parent=sh, bevel=0.1)
        box(f"cuff{side}", (1.04, 1.04, 0.2), (0, 0, -1.28), TEE, parent=sh, bevel=0.05)
        box(f"stripe{side}", (0.08, 1.02, 1.0), (side * 0.49, 0, -0.62), GOLDM, parent=sh, bevel=0.02)
        # hand: slightly narrower block with a thumb nub for a readable grip
        box(f"hand{side}", (0.9, 0.9, 0.66), (0, 0, -1.68), SKIN, parent=sh, bevel=0.16)
        box(f"thumb{side}", (0.26, 0.3, 0.34), (-side * 0.46, 0.2, -1.6), SKIN, parent=sh, bevel=0.1)
        return sh
    arm(-1, pose["arm_l"])
    arm(1, pose["arm_r"])
    # ---- legs (pivot at hip, seated -> rotated forward)
    for s, key in ((-1, "leg_l"), (1, "leg_r")):
        hp = empty(f"hip{s}", (s * 0.5, 0, 0.0), rot=pose.get(key, (90, 0, 0)), parent=hips)
        box(f"leg{s}", (0.98, 1.0, 1.7), (0, 0, -0.85), PANTS, parent=hp, bevel=0.08)
        box(f"shoe{s}", (1.02, 1.2, 0.46), (0, 0.12, -1.86), SHOE, parent=hp, bevel=0.14)
        box(f"sole{s}", (1.04, 1.22, 0.12), (0, 0.12, -2.08), SOLE, parent=hp, bevel=0.04)
    return root


# ------------------------------------------------------------ desk setup
def build_desk(width=9.6, cx=-1.4):
    rig = empty("desk_rig", (0, 0, 0))
    box("desk_top", (width, 3.2, 0.22), (cx, 2.4, 2.95), DESK_TOP, parent=rig, bevel=0.08)
    box("desk_trim", (width + 0.04, 0.08, 0.1), (cx, 0.8, 2.9), GOLDM, parent=rig, bevel=0.02)
    box("desk_led", (width - 0.2, 0.04, 0.05), (cx, 0.84, 2.78), emit_mat("deskled", "#B070FF", 12), parent=rig, bevel=0)
    box("desk_front", (width - 0.4, 0.12, 1.2), (cx, 1.0, 2.2), DESK, parent=rig, bevel=0.04)
    for s in (-1, 1):
        box(f"desk_leg{s}", (0.32, 2.8, 2.85), (cx + s * (width / 2 - 0.3), 2.4, 1.42), DESK, parent=rig, bevel=0.06)
    box("kb", (2.3, 0.8, 0.12), (-0.1, 1.45, 3.12), BLACK, rot=(3, 0, 0), parent=rig, bevel=0.04)
    kc = mat("keycap", "#2A2450", rough=0.3)
    for r in range(4):
        for c in range(12):
            box(f"key{r}_{c}", (0.14, 0.13, 0.05), (-1.08 + c * 0.18, 1.19 + r * 0.17, 3.2), kc, parent=rig, bevel=0.02, seg=1)
    box("kb_glow", (2.34, 0.84, 0.03), (-0.1, 1.45, 3.07), RGB_KEYS, parent=rig, bevel=0)
    box("mousepad", (1.2, 1.0, 0.03), (1.9, 1.55, 3.07), mat("pad", "#3B1C8C", rough=0.7), parent=rig, bevel=0.02)
    box("mouse", (0.34, 0.52, 0.18), (1.9, 1.5, 3.17), BLACK, parent=rig, bevel=0.12, seg=4)
    box("mouse_led", (0.06, 0.2, 0.04), (1.9, 1.62, 3.27), CYANM, parent=rig, bevel=0.01)
    mp = mat("mugp", "#FF6FA8", rough=0.3)
    cyl("mug", 0.24, 0.5, (2.9, 2.0, 3.31), mp, parent=rig, bevel=0.03)
    cyl("mug_coffee", 0.2, 0.02, (2.9, 2.0, 3.55), mat("coffee", "#4A2A18", rough=0.2), parent=rig)
    cyl("mug_handle", 0.14, 0.08, (3.16, 2.0, 3.32), mp, rot=(90, 0, 0), parent=rig)
    return rig


def monitor(name, img, loc, yaw, w=4.3, h=2.5, strength=1.7):
    mon = empty(name, loc, rot=(0, 0, yaw))
    box(name + "_bezel", (w, 0.18, h), (0, 0, 0.7 + h / 2), BLACK, parent=mon, bevel=0.06)
    plane(name + "_screen", w - 0.22, h - 0.22, (0, -0.095, 0.7 + h / 2),
          image_emit_mat(name + "_scr", os.path.join(TEX, f"chart_{img}.png"), strength), rot=(90, 0, 0), parent=mon)
    box(name + "_back", (w * 0.6, 0.3, h * 0.5), (0, 0.2, 0.7 + h / 2), BLACK, parent=mon, bevel=0.1)
    box(name + "_neck", (0.3, 0.2, 0.75), (0, 0.3, 0.4), GOLDM, parent=mon, bevel=0.04)
    box(name + "_foot", (1.1, 0.8, 0.08), (0, 0.2, 0.04), BLACK, parent=mon, bevel=0.03)
    box(name + "_glow", (w - 0.3, 0.02, 0.05), (0, 0.1, 0.72), emit_mat(name + "_g", "#12D9FF", 20), parent=mon, bevel=0)
    return mon


def build_chair():
    ch = empty("chair", (0, 0, 0))
    box("seat", (2.5, 2.3, 0.4), (0, -0.2, 1.35), CHAIR, parent=ch, bevel=0.14)
    box("seat_acc", (2.52, 2.32, 0.08), (0, -0.2, 1.2), CHAIR_ACC, parent=ch, bevel=0.03)
    box("back", (2.5, 0.42, 3.4), (0, -1.35, 3.0), CHAIR, rot=(-8, 0, 0), parent=ch, bevel=0.2)
    box("back_stripe_l", (0.26, 0.44, 3.0), (-0.6, -1.33, 3.0), CHAIR_ACC, rot=(-8, 0, 0), parent=ch, bevel=0.05)
    box("back_stripe_r", (0.26, 0.44, 3.0), (0.6, -1.33, 3.0), CHAIR_ACC, rot=(-8, 0, 0), parent=ch, bevel=0.05)
    box("headrest", (1.6, 0.5, 0.6), (0, -1.05, 4.55), CHAIR_ACC, rot=(-8, 0, 0), parent=ch, bevel=0.2)
    cyl("post", 0.14, 0.9, (0, -0.2, 0.7), BLACK, parent=ch)
    for i in range(5):
        a = R(i * 72)
        box(f"wleg{i}", (0.2, 1.2, 0.16), (math.sin(a) * 0.55, -0.2 + math.cos(a) * 0.55, 0.22), BLACK, rot=(0, 0, -i * 72), parent=ch, bevel=0.05)
        sphere(f"wheel{i}", 0.13, (math.sin(a) * 1.1, -0.2 + math.cos(a) * 1.1, 0.13), BLACK, parent=ch)
    return ch


# ------------------------------------------------------------ room
def build_room():
    plane("floor", 60, 60, (0, 0, 0), FLOOR)
    # back wall with panels + neon
    box("wall_back", (40, 0.4, 20), (0, 9.5, 10), WALL, bevel=0)
    box("wall_left", (0.4, 40, 20), (-11, 0, 10), WALL2, bevel=0)
    # window with night skyline
    win = empty("window", (-5.4, 9.25, 6.6))
    box("win_frame", (6.2, 0.2, 4.2), (0, 0, 0), mat("frame", "#2D2580", rough=0.4), parent=win, bevel=0.08)
    plane("win_sky", 5.8, 3.8, (0, -0.12, 0), image_emit_mat("sky", os.path.join(TEX, "skyline.png"), 1.6),
          rot=(90, 0, 180), parent=win)
    box("win_mullion", (0.12, 0.26, 3.8), (0, -0.1, 0), mat("frame", "#2D2580"), parent=win, bevel=0.03)
    # neon strips on back wall
    box("neon_top", (22, 0.1, 0.12), (4, 9.25, 11.6), emit_mat("neon_p", "#9A4DFF", 25), bevel=0)
    box("neon_low", (22, 0.1, 0.1), (4, 9.25, 0.3), emit_mat("neon_c", "#12D9FF", 18), bevel=0)
    # shelf with trophies and books
    sh = empty("shelf", (8.2, 9.0, 5.2))
    box("shelf_board", (4.0, 0.9, 0.18), (0, 0, 0), WOOD, parent=sh, bevel=0.04)
    box("shelf_board2", (4.0, 0.9, 0.18), (0, 0, 2.0), WOOD, parent=sh, bevel=0.04)
    for i, c in enumerate(("#FF6FA8", "#12D9FF", "#FFC53A", "#7B3CFF", "#2BE07A")):
        box(f"book{i}", (0.28, 0.7, 0.9 + (i % 2) * 0.2), (-1.6 + i * 0.32, 0, 0.55 + (i % 2) * 0.1), mat(f"book{i}", c), parent=sh, bevel=0.03)
    cyl("big_cup", 0.42, 0.7, (0.9, 0, 0.62), GOLDM, parent=sh, bevel=0.06)
    box("big_cup_base", (0.8, 0.6, 0.24), (0.9, 0, 0.2), BLACK, parent=sh, bevel=0.04)
    sphere("globe", 0.4, (-0.8, 0, 2.5), mat("orb", "#12D9FF", emit="#12D9FF", estr=2.0), parent=sh)
    # plant
    cyl("pot", 0.6, 1.1, (-8.6, 6.8, 0.55), POT, bevel=0.06)
    for i in range(7):
        a = i * 51
        box(f"leaf{i}", (0.28, 0.9, 1.7), (-8.6 + math.sin(R(a)) * 0.3, 6.8 + math.cos(R(a)) * 0.3, 1.9), PLANT,
            rot=(18 * math.cos(R(a)), 18 * math.sin(R(a)), a), bevel=0.1)


# ------------------------------------------------------------ scene variants
POSES = {
    # arm rotations are (x, y, z) degrees at the shoulder; +x swings the arm forward
    "focus": dict(face="determined", lean=-12, twist=4, head_pitch=4, head_yaw=13, head_roll=-4,
                  arm_l=(72, 0, -8), arm_r=(78, 0, 12)),
    "win": dict(face="cheer", lean=8, twist=0, head_pitch=-10, head_yaw=0, head_roll=4,
                arm_l=(170, -22, 0), arm_r=(170, 22, 0)),
    "challenge": dict(face="surprised", lean=7, twist=0, head_pitch=-8, head_yaw=-10, head_roll=5,
                      arm_l=(60, 0, 16), arm_r=(60, 0, -16)),
}


DT = 2.71  # desk top height
CFG = {
    "focus": dict(group_loc=(-2.2, 0, 0), group_yaw=207,
                  monitors=[("focus", (2.0, 1.4, DT), -26), ("side_a", (6.1, 4.2, DT), -40, 1.6, 2.5, 1.5)],
                  cam=(-0.8, -9.2, 6.9), tgt=(0.3, 0.8, 5.0)),
    "win": dict(group_loc=(-1.7, -0.7, 0), group_yaw=196, desk_loc=(0.6, 0.3, 0), desk_yaw=0, desk_cx=0.0,
                monitors=[("win", (2.3, 2.5, DT), -10, 5.8, 3.3, 2.2), ("side_a", (-5.0, 3.0, DT), 20, 1.6, 2.5, 1.5)],
                cam=(-0.5, -8.6, 4.5), tgt=(0.3, 0.8, 5.6), lens=28),
    "challenge": dict(group_loc=(1.9, 0, 0), group_yaw=147, desk_cx=1.4,
                      monitors=[("challenge", (-2.0, 1.4, DT), 26), ("side_b", (-6.1, 4.2, DT), 40, 1.6, 2.5, 1.5)],
                      cam=(0.8, -9.2, 6.9), tgt=(-0.3, 0.8, 5.0)),
}

pose = POSES[SCENE]
build_room()
char = build_character(pose)
chair = build_chair()
chair.location = (0, 0, 0.3)
char.location = (0, -0.25, 0.0)
cam_d = D.cameras.new("cam")
cam = D.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
cam_d.dof.use_dof = True
cam_d.dof.aperture_fstop = 5.6

group = empty("group", (0, 0, 0))
char.parent = group
chair.parent = group
C = CFG[SCENE]
desk = build_desk(cx=C.get("desk_cx", -1.4))
group.location = C["group_loc"]
group.rotation_euler = (0, 0, R(C["group_yaw"]))
desk.location = Vector(C.get("desk_loc", C["group_loc"])) + Vector((0, 0, -0.35))
desk.rotation_euler = (0, 0, R(C.get("desk_yaw", C["group_yaw"])))
mons = [monitor(f"mon{i}", *m) for i, m in enumerate(C["monitors"])]
mon = mons[0]
cam_d.lens = C.get("lens", 30)
cam.location = C["cam"]
look_at(cam, C["tgt"])
bpy.context.view_layer.update()
cam_d.dof.focus_distance = (Vector(C["cam"]) - D.objects["head"].matrix_world.translation).length



def trophy(loc, s=1.0):
    t = empty("trophy", loc)
    t.scale = (s, s, s)
    box("t_base", (0.6, 0.6, 0.2), (0, 0, 0.1), BLACK, parent=t, bevel=0.03)
    box("t_plate", (0.4, 0.02, 0.1), (0, -0.31, 0.1), GOLDM, parent=t, bevel=0.01)
    cyl("t_stem", 0.08, 0.35, (0, 0, 0.37), GOLDM, parent=t)
    cyl("t_cup", 0.3, 0.46, (0, 0, 0.77), GOLDM, parent=t, bevel=0.06)
    for q in (-1, 1):
        cyl(f"t_h{q}", 0.13, 0.06, (q * 0.34, 0, 0.8), GOLDM, rot=(90, 0, 0), parent=t)
    return t

# ------------------------------------------------------------ scene extras
import random
rnd = random.Random(4)
if SCENE == "focus":
    trophy((4.4, 0.2, DT), 1.1)
    point("tro_glow", (4.4, -0.6, DT + 1.2), 60, "#FFC53A", 0.3)
if SCENE == "challenge":
    trophy((-4.1, 0.6, DT), 1.0)
    for o in [o for o in D.objects if o.name.startswith(("pot", "leaf"))]:
        o.hide_render = True
if SCENE == "win":
    cols = ["#FFC53A", "#2BE07A", "#9A4DFF", "#12D9FF", "#FF6FA8"]
    cms = [mat(f"conf{i}", c, rough=0.3, emit=c, estr=0.6) for i, c in enumerate(cols)]
    for i in range(140):
        x = rnd.uniform(-6.5, 6.5); z = rnd.uniform(3.2, 9.5); y = rnd.uniform(-3.0, 3.5)
        if abs(x + 1.7) < 2.0 and z < 7.6:
            continue  # keep the face clear
        if 0.2 < x < 5.2 and 3.4 < z < 6.6 and y < 2.2 and rnd.random() < 0.7:
            continue  # keep the chart mostly clear
        box(f"cf{i}", (0.2, 0.2, 0.04), (x, y, z), rnd.choice(cms),
            rot=(rnd.uniform(0, 360), rnd.uniform(0, 360), rnd.uniform(0, 360)), bevel=0.01, seg=1)
    for i in range(0):  # (streamers removed)
        x = rnd.uniform(-6, 6); z = rnd.uniform(4, 9)
        if abs(x + 1.7) < 2.2:
            continue
        box(f"st{i}", (0.07, 0.07, 0.8), (x, rnd.uniform(-2, 2), z), GOLDM,
            rot=(rnd.uniform(-60, 60), rnd.uniform(-60, 60), 0), bevel=0.02)
if SCENE == "challenge":
    # candles bursting out of the main screen toward the viewer
    m0 = mons[0].matrix_world
    gm = mat("c3g", "#10C85A", rough=0.3, emit="#10C85A", estr=0.2)
    rm = mat("c3r", "#F0183E", rough=0.3, emit="#F0183E", estr=0.2)
    wick = mat("wick", "#FFFFFF", rough=0.3, emit="#FFFFFF", estr=1.0)
    spec = [(-2.7, -1.0, 2.9, 1.3, rm, 25), (-3.3, -2.0, 1.4, 0.9, gm, -18), (-1.4, -2.2, 0.4, 0.8, rm, 35),
            (-4.0, -0.8, 3.6, 1.0, gm, -14), (-3.0, -3.2, 3.4, 0.7, gm, 12)]
    for i, (lx, ly, lz, hgt, mm, tilt) in enumerate(spec):
        p = m0 @ Vector((lx, ly, lz))
        c = empty(f"c3_{i}", tuple(p), rot=(rnd.uniform(-15, 15), tilt, rnd.uniform(-30, 30)))
        box(f"c3b{i}", (0.34, 0.34, hgt), (0, 0, 0), mm, parent=c, bevel=0.06)
        box(f"c3w{i}", (0.07, 0.07, hgt + 0.7), (0, 0, 0), wick, parent=c, bevel=0.02)

# lighting: warm gold key, purple + cyan rims, screen glow fill, room ambience
area("key", (-4, -7, 10), (0, 0, 5.0), 1800, "#FFD68A", size=3.5)
area("rim_p", (-7, 7, 8), (0, 0, 4.8), 4200, "#9A4DFF", size=3)
area("rim_c", (7, 6, 7), (0, 0, 4.8), 3000, "#12D9FF", size=3)
area("gold_rim", (5, 5, 10), (0, 0, 5.5), 1500, "#FFB84A", size=2)
area("wash_l", (-6, 3, 1), (-5, 9.3, 9), 2500, "#8A3DFF", size=4)
area("wash_r", (7, 3, 1), (7, 9.3, 9), 2000, "#3D6BFF", size=4)
area("fill", (3, -9, 4), (0, 0, 4), 300, "#8FA8FF", size=5)
area("face_fill", tuple(Vector(C["cam"]) + Vector((0, 2, 1.5))), tuple(D.objects["head"].matrix_world.translation), 260, "#FFE2C0", size=2.5)
mon_world = mon.matrix_world.translation + mon.matrix_world.to_3x3() @ Vector((0, -1.2, 1.75))
face_world = D.objects["head"].matrix_world.translation
area("screen_glow", tuple(mon_world), tuple(face_world), 900 if SCENE != "win" else 1600,
     "#5CFFB0" if SCENE == "win" else "#7FE0FF", size=3, size_y=1.8)
if SCENE == "challenge":
    area("red_glow", tuple(mon_world + Vector((0, 0, 1.0))), tuple(face_world), 500, "#FF4A7A", size=2)

world = D.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = rgb("#0A0A30")
world.node_tree.nodes["Background"].inputs[1].default_value = 0.6

# ------------------------------------------------------------ render
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 6
sc.cycles.transparent_max_bounces = 8
sc.render.resolution_x = 1920
sc.render.resolution_y = 1080
sc.render.resolution_percentage = RES
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Punchy"
sc.render.filepath = OUTP
sc.render.image_settings.file_format = "PNG"
sc.render.film_transparent = False
bpy.ops.render.render(write_still=True)
print("RENDERED", OUTP)
