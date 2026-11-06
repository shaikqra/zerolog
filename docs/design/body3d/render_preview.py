"""Build the ZeroLog écorché preview: dark body, today's muscles glowing.

blender -b -P render_preview.py -- <lit:legs|push|pull>
Renders front + back PNGs to /opt/data/work/zerolog-assets/preview_*.png
"""
import bpy, sys, math

BLEND = "/opt/data/work/zerolog-assets/zanatomy/Z-Anatomy/Startup.blend"
OUT = "/opt/data/work/zerolog-assets"
lit_arg = (sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "legs")

bpy.ops.wm.read_factory_settings(use_empty=True)

# The superficial layer, plus visible muscles it leaves out (they sit under
# fascia sheets that we remove below).
EXTRA = ["Rectus abdominis muscle", "Semimembranosus muscle", "Soleus muscle",
         "Gluteus medius muscle", "Serratus anterior muscle", "Infraspinatus muscle",
         "Teres major muscle", "Adductor longus muscle", "Adductor magnus muscle",
         "Gracilis muscle", "Pectineus muscle", "Brachialis muscle",
         "Sternocleidomastoid muscle"]
with bpy.data.libraries.load(BLEND, link=False) as (src, dst):
    available = list(src.collections)
    # Report real names for anything we guessed wrong, then load what exists.
    for miss in [n for n in EXTRA if n not in available]:
        key = miss.lower().split(" muscle")[0]
        near = [a for a in available if key.split()[0].lower() in a.lower()]
        print("MISSING:", miss, "NEAR:", near[:4])
    want = ["Superficial muscles"] + [n for n in EXTRA if n in available]
    dst.collections = want
print("LOADED COLLECTIONS:", [c.name for c in dst.collections if c])

for col in list(dst.collections):
    if col:
        bpy.context.scene.collection.children.link(col)

# The atlas ships with render visibility OFF so layers can be toggled in the
# viewer; a headless render of the untouched file is a black frame.
def unhide(col):
    col.hide_render = False
    col.hide_viewport = False
    for ch in col.children:
        unhide(ch)
for col in bpy.data.collections:
    unhide(col)
for o in bpy.data.objects:
    o.hide_render = False
    o.hide_viewport = False

# Strip fascia, tendon sheets and face-detail thin bits that read as noise.
DROP = ("fascia", "aponeurosis", "ligament", "tendon", "iliotibial tract", "platysma")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    if any(k in o.name.lower() for k in DROP):
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
print("MESHES AFTER STRIP:", len(meshes))

GROUPS = {
    "chest":  ["pectoralis major"],
    "delts":  ["deltoid"],
    "biceps": ["biceps brachii", "brachialis"],
    "triceps":["triceps brachii"],
    "forearm":["carpi", "extensor digitorum", "brachioradialis"],
    "traps":  ["trapezius"],
    "lats":   ["latissimus", "infraspinatus", "teres major"],
    "glutes": ["gluteus"],
    "quads":  ["rectus femoris", "vastus", "sartorius"],
    "hams":   ["biceps femoris", "semitendinosus", "semimembranosus"],
    "adds":   ["adductor", "gracilis", "pectineus"],
    "calves": ["gastrocnemius", "soleus", "tibialis anterior", "fibularis"],
    "abs":    ["rectus abdominis", "abdominal oblique", "serratus"],
}
LIT = {
    "legs": {"quads", "hams", "glutes", "adds", "calves"},
    "push": {"chest", "delts", "triceps"},
    "pull": {"traps", "lats", "biceps", "forearm"},
}[lit_arg]

def group_of(name):
    n = name.lower()
    for g, keys in GROUPS.items():
        if any(k in n for k in keys):
            return g
    return None

# Materials: near-black body with a faint sheen; lit muscles emit white.
base = bpy.data.materials.new("Base")
base.use_nodes = True
bsdf = base.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.012, 0.012, 0.014, 1)
bsdf.inputs["Roughness"].default_value = 0.42
bsdf.inputs["Metallic"].default_value = 0.65

hot = bpy.data.materials.new("Lit")
hot.use_nodes = True
hb = hot.node_tree.nodes["Principled BSDF"]
hb.inputs["Base Color"].default_value = (0.62, 0.66, 0.72, 1)
hb.inputs["Emission Color"].default_value = (0.9, 0.93, 1.0, 1)
hb.inputs["Emission Strength"].default_value = 0.10
hb.inputs["Roughness"].default_value = 0.5

lit_count = 0
for o in meshes:
    g = group_of(o.name)
    o.data.materials.clear()
    if g in LIT:
        o.data.materials.append(hot)
        lit_count += 1
    else:
        o.data.materials.append(base)
print("LIT MESHES:", lit_count)

# Frame the body
xs, ys, zs = [], [], []
for o in meshes:
    for corner in o.bound_box:
        v = o.matrix_world @ bpy.mathutils.Vector(corner) if hasattr(bpy, "mathutils") else None
import mathutils
# An outlier object (atlas furniture parked far from the body) wrecks a naive
# bounding box: the first render aimed the camera below the feet. Cluster on
# object centres around the median before trusting any bounds.
centers = []
for o in meshes:
    pts = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    centers.append((o, sum(pts, mathutils.Vector()) / 8))
zs_sorted = sorted(c.z for _, c in centers)
median_z = zs_sorted[len(zs_sorted) // 2]
outliers = [(o.name, round(c.z, 2)) for o, c in centers if abs(c.z - median_z) > 2.5]
print("OUTLIERS DROPPED:", outliers[:6])
body = [o for o, c in centers if abs(c.z - median_z) <= 2.5]
for o, _ in centers:
    if o not in body:
        bpy.data.objects.remove(o, do_unlink=True)
meshes = body
# bound_box lied: it is the raw mesh's box, and these objects carry modifiers
# that reposition the final geometry (the first renders aimed a metre low).
# Only the evaluated depsgraph tells the truth about what will be rendered.
dg = bpy.context.evaluated_depsgraph_get()
for o in meshes:
    ev = o.evaluated_get(dg)
    mw = ev.matrix_world
    for corner in ev.bound_box:
        v = mw @ mathutils.Vector(corner)
        xs.append(v.x); ys.append(v.y); zs.append(v.z)
# Median of object centres for x: a splayed arm drags a bbox midpoint
# sideways, and the frame with it.
ev_centers = []
for o in meshes:
    ev = o.evaluated_get(dg)
    pts = [ev.matrix_world @ mathutils.Vector(c) for c in ev.bound_box]
    ev_centers.append(sum(pts, mathutils.Vector()) / 8)
exs = sorted(c.x for c in ev_centers)
cx = exs[len(exs) // 2]
cy, cz = (min(ys)+max(ys))/2, (min(zs)+max(zs))/2
height = max(zs) - min(zs)
print("BODY HEIGHT:", round(height, 2), "CENTER:", round(cx,2), round(cy,2), round(cz,2))

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 620
scene.render.resolution_y = 1280
scene.render.film_transparent = False
world = bpy.data.worlds.new("W"); scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)

# Rim lights left/right + soft key, so the dark body still has silhouette
def light(name, loc, energy, size=4.0):
    ld = bpy.data.lights.new(name, "AREA"); ld.energy = energy; ld.size = size
    lo = bpy.data.objects.new(name, ld); scene.collection.objects.link(lo)
    lo.location = loc
    look = mathutils.Vector((cx, cy, cz)) - lo.location
    lo.rotation_euler = look.to_track_quat("-Z", "Z").to_euler()
    return lo

cam_data = bpy.data.cameras.new("Cam"); cam_data.lens = 70
cam_data.sensor_fit = "VERTICAL"   # portrait: fit the body to frame HEIGHT
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam); scene.camera = cam
# Distance from lens geometry, not a guess: fit body height plus 12% margin.
import math as _m
vfov = 2 * _m.atan((cam_data.sensor_height / 2) / cam_data.lens)
dist = (height * 1.12) / (2 * _m.tan(vfov / 2))
print("CAMERA DIST:", round(dist, 2))

for label, sign in (("front", -1), ("back", +1)):
    # Deterministic transforms, no tracking math: a camera at -Y rotated 90
    # degrees about X looks along +Y (the model faces -Y, so that is the
    # front); the +Y camera adds a Z half-turn to look back along -Y.
    px, py = cx, cy + sign * dist
    cam.location = (px, py, cz)
    cam.rotation_euler = (math.radians(90), 0, math.radians(0 if sign < 0 else 180))
    ang = 0.0 if sign > 0 else math.radians(180)
    for l in [o for o in scene.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(l, do_unlink=True)
    side = mathutils.Vector((-math.cos(ang), math.sin(ang), 0))
    light("rimL", (cx + side.x*height*0.9,  cy + side.y*height*0.9,  cz + height*0.25), 900)
    light("rimR", (cx - side.x*height*0.9,  cy - side.y*height*0.9,  cz + height*0.25), 900)
    light("key",  (px*0.7 + cx*0.3, py*0.7 + cy*0.3, cz + height*0.45), 350, size=6)
    bpy.context.view_layer.update()
    print("CAM", label, "loc", tuple(round(v,2) for v in cam.matrix_world.translation),
          "euler", tuple(round(v,2) for v in cam.matrix_world.to_euler()))
    # Where does the central camera ray hit the body plane?
    fwd = cam.matrix_world.to_quaternion() @ mathutils.Vector((0, 0, -1))
    print("CAM forward", tuple(round(v,2) for v in fwd))
    scene.render.filepath = f"{OUT}/preview_{lit_arg}_{label}.png"
    bpy.ops.render.render(write_still=True)
    print("WROTE", scene.render.filepath)
