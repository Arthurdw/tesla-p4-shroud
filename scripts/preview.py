"""Render preview PNGs of the exported STLs (run scripts/export.sh first).

Usage: scripts/preview.sh   (wraps: uv run --python 3.12 --with pyvista python scripts/preview.py)

Card coordinates as in cad/params.scad: X = flow axis (fan toward +X), Y = card thickness, Z = card height.
"""
import pathlib
import re
import numpy as np
import pyvista as pv

OUT = pathlib.Path(__file__).resolve().parent.parent / "output"
SIZE = (1600, 1100)
BODY = "#9cc3d5"   # printed part
SLEEVE = "#b9d59c" # the separate sleeve (mouthpiece) part
CUT = "#e8833a"    # cut faces in section views
EDGE = "#1b2b33"


def load(name):
    return pv.read(OUT / f"{name}.stl").clean().triangulate()


def plotter(shape=(1, 1)):
    pl = pv.Plotter(off_screen=True, window_size=SIZE, shape=shape, border=False)
    pl.enable_anti_aliasing("ssaa")
    return pl


def style(pl, title, mesh=None):
    pl.set_background("#f7f9fb", top="#d9e2ea")
    t = pl.add_text(title, position="upper_left", font_size=13, color="#1b2b33")
    t.prop.background_color, t.prop.background_opacity = "#f7f9fb", 0.85  # readable over a dark part
    if mesh is not None:
        lo, hi = np.array(mesh.bounds).reshape(3, 2).T
        d = hi - lo
        pl.add_text(f"X {d[0]:.1f}   Y {d[1]:.1f}   Z {d[2]:.1f} mm", position="lower_right", font_size=10, color="#4a5a63")
    pl.add_axes(line_width=3, labels_off=False, color="#1b2b33")


def add_part(pl, m, color=BODY, opacity=1.0):
    shaded = m.compute_normals(feature_angle=35, split_vertices=True)
    pl.add_mesh(shaded, color=color, smooth_shading=True, specular=0.25, specular_power=20, opacity=opacity)
    pl.add_mesh(m.clean().extract_feature_edges(feature_angle=35, boundary_edges=False, manifold_edges=False,
                                        non_manifold_edges=False), color=EDGE, line_width=3)


def add_section(pl, m, normal, origin, color=BODY):
    """The half of the part on the side `normal` points to, cut face filled in CUT colour (view it from -normal).
    Returns that half, for framing."""
    normal = np.asarray(normal, float)
    half = m.clip_closed_surface(normal=normal, origin=origin).triangulate()
    centers = half.cell_centers().points
    on_plane = np.abs((centers - origin) @ normal) < 1e-3
    body = half.extract_cells(np.where(~on_plane)[0]).extract_surface(algorithm="dataset_surface").clean()
    cap = half.extract_cells(np.where(on_plane)[0]).extract_surface(algorithm="dataset_surface")
    add_part(pl, body, color)
    if cap.n_cells:
        pl.add_mesh(cap, color=CUT, ambient=0.25)
        pl.add_mesh(cap.extract_feature_edges(boundary_edges=True, feature_edges=False, manifold_edges=False),
                    color=EDGE, line_width=4)
    return half


def mouth_center(m):
    """Centre of the sleeve mouth (the end at minimum X)."""
    x0 = m.bounds[0]
    pts = m.points[m.points[:, 0] < x0 + 1]
    return np.array([x0, *(pts[:, 1:].min(0) + pts[:, 1:].max(0)) / 2])


def view(pl, pts, direction, up, margin=1.15, angle=20):
    """Camera looking along -direction, centred and fitted on the screen-space extent of `pts`
    (so the part fills the frame whatever its shape, unlike reset_camera's bounding sphere)."""
    pts = pts.points if hasattr(pts, "points") else np.asarray(pts)
    d = np.asarray(direction, float); d /= np.linalg.norm(d)
    u = np.asarray(up, float); u -= (u @ d) * d; u /= np.linalg.norm(u)
    r = np.cross(u, d)
    px, py, pz = pts @ r, pts @ u, pts @ d
    mid = lambda a: (a.min() + a.max()) / 2
    focal = mid(px) * r + mid(py) * u + mid(pz) * d
    rows, cols = pl.shape
    aspect = (SIZE[0] / cols) / (SIZE[1] / rows)
    half = max(np.ptp(py) / 2, np.ptp(px) / 2 / aspect) * margin
    dist = half / np.tan(np.radians(angle / 2)) + np.ptp(pz) / 2
    cam = pl.camera
    cam.focal_point, cam.position, cam.up, cam.view_angle = focal, focal + d * dist, u, angle
    pl.reset_camera_clipping_range()


def shot(pl, name):
    pl.screenshot(OUT / name)
    pl.close()
    print(f"ok  output/{name}")


def near_mouth(m, length):
    """Points of `m` within `length` of the mouth end (min X)."""
    return m.points[m.points[:, 0] < m.bounds[0] + length]


def param(name):
    """A plain numeric value from cad/params.scad."""
    import re
    txt = (OUT.parent / "cad" / "params.scad").read_text()
    return float(re.search(rf"^{name}\s*=\s*([-0-9.]+)", txt, re.M).group(1))


# The -D flags of the optional stator-layer build (scripts/export.sh: layer_cfg). The default build is already the spacer stack.
LAYER_CFG = ["-D", "stator_layer=true", "-D", "stack_max_len=999"]


def scad(*names, defines=()):
    """Values derived in cad/shroud.scad (numbers or lists of [y, z] points), echoed by OpenSCAD without building geometry.
    `defines`: extra OpenSCAD arguments (e.g. LAYER_CFG) to read the values of another configuration."""
    import json, subprocess, tempfile
    cad = OUT.parent / "cad"
    with tempfile.TemporaryDirectory() as d:
        src, echo = pathlib.Path(d, "v.scad"), pathlib.Path(d, "v.echo")
        src.write_text(f"include <{cad / 'shroud.scad'}>\n" + "".join(f'echo(V_{n}={n});\n' for n in names))
        subprocess.run(["openscad", *defines, "-D", 'part="none"', "-o", str(echo), str(src)], check=True, capture_output=True)
        found = dict(re.findall(r"ECHO: V_(\w+) = (.*)", echo.read_text()))
    return {n: json.loads(found[n]) for n in names}


shroud, sleeve = load("shroud"), load("sleeve")
duct = shroud.merge(sleeve)   # both printed parts, assembled (they do not touch)
mc = mouth_center(sleeve)


def add_duct(pl):
    add_part(pl, shroud); add_part(pl, sleeve, SLEEVE)


def section_duct(pl, normal, origin):
    """Section of both parts (sleeve in its own colour); returns the halves merged, for framing."""
    return add_section(pl, shroud, normal, origin).merge(add_section(pl, sleeve, normal, origin, SLEEVE))


# 1. overview from the card side
pl = plotter(); style(pl, "Shroud + sleeve (green) - from the card side (the spacer, then the fan, bolt to the far face)", duct)
add_duct(pl); view(pl, duct, (-1, 0.9, 0.6), (0, 0, 1)); shot(pl, "preview_iso.png")

# 2. overview from the fan side
pl = plotter(); style(pl, "Shroud + sleeve - fan-side face (bellmouth, lug plate, M3 countersunk pockets)", duct)
add_duct(pl); view(pl, duct, (0.8, -1, 0.55), (0, 0, 1)); shot(pl, "preview_fan_side.png")

# 3. sections through the mouth centre: flow path, channel step, vanes, bellmouth
pl = plotter((1, 2))
pl.subplot(0, 0); style(pl, "Section at mouth centre Z (card thickness, Y)")
h = section_duct(pl, (0, 0, -1), mc); view(pl, h, (0, 0, 1), (0, 1, 0), 1.08)
pl.subplot(0, 1); style(pl, "Section at mouth centre Y (card height, Z)")
h = section_duct(pl, (0, 1, 0), mc); view(pl, h, (0, -1, 0), (0, 0, 1), 1.08)
shot(pl, "preview_section.png")

# 4. close-up of the mouth and the step into the inlet channel
pl = plotter((1, 2))
pl.subplot(0, 0); style(pl, "Mouth, looking in from the card")
add_part(pl, sleeve, SLEEVE); view(pl, near_mouth(sleeve, 25), (-1, 0.35, 0.3), (0, 0, 1), 1.7)
pl.subplot(0, 1); style(pl, "Mouth, cut: grip -> flat stop -> 8 mm channel")
h = add_section(pl, sleeve, (0, 0, -1), mc, SLEEVE); view(pl, near_mouth(h, 35), (-0.25, 0.2, 1), (0, 1, 0), 1.2)
shot(pl, "preview_mouth.png")

# 5. print orientation on a bed: shroud (fan face down) and sleeve (socket end down)
pl = plotter((1, 2))
for col, (name, title, color) in enumerate([("shroud_print", "Shroud print - fan face on the bed, no supports", BODY),
                                            ("sleeve_print", "Sleeve print - socket end on the bed, no supports", SLEEVE)]):
    pr = load(name)
    pl.subplot(0, col); style(pl, title, pr)
    lo = pr.bounds
    bed = pv.Plane(center=((lo[0] + lo[1]) / 2, (lo[2] + lo[3]) / 2, lo[4] - 0.2), i_size=220, j_size=220, i_resolution=22, j_resolution=22)
    pl.add_mesh(bed, color="#c9d1d8", show_edges=True, edge_color="#aab4bd", line_width=1)
    add_part(pl, pr, color); view(pl, np.vstack([pr.points, bed.points]), (1, -1.2, 0.8), (0, 0, 1), 1.05)
shot(pl, "preview_print.png")

# 5b. the sleeve / shroud joint, cut through the screw axis (Y = channel centre): spigot in the socket, lug, boss, insert hole
jy = param("hs_t") - param("hs_h") / 2   # channel centre = screw axis Y
pl = plotter((1, 2))
pl.subplot(0, 0); style(pl, "Joint, cut through the M3 axis: spigot in socket, lug (green) -> insert boss")
# the joint side: the lug is the sleeve's Z extreme on that side (joint_side "bottom" = low Z, "top" = high Z)
js = 1 if '"top"' in re.search(r'^joint_side\s*=\s*("\w+")', (OUT.parent / "cad" / "params.scad").read_text(), re.M).group(1) else -1
zc = (sleeve.bounds[4] + sleeve.bounds[5]) / 2   # card centre in Z
near = lambda p, d: js * (p[:, 2] - zc) > d       # points beyond d mm from the card centre on the joint side
h = section_duct(pl, (0, 1, 0), np.array([0.0, jy, 0.0]))
win = h.points[(h.points[:, 0] > 2) & (h.points[:, 0] < 48) & near(h.points, 16)]
view(pl, win, (0, -1, 0), (0, 0, 1), 1.1)
pl.subplot(0, 1); style(pl, "Joint, outside")
add_duct(pl)
win = duct.points[(duct.points[:, 0] > 2) & (duct.points[:, 0] < 48) & near(duct.points, 12)]
view(pl, win, (-0.6, -0.8, 0.7 * js), (0, 0, 1), 1.2)
shot(pl, "preview_joint.png")

# 6. stack, exploded (no fan): the default build (sleeve, shroud, key ring, spacer; the fan bolts to the spacer).
# 6b below adds the optional stator layer and nose puck. The direct mount (stack_module "none") has no preview of its own.
def shifted(m, dx):
    return m.copy().translate((dx, 0, 0), inplace=False)


def on_axis(m, x0):
    """`m` moved so its min X is x0 and its Y/Z centre is on the fan axis."""
    lo, hi = np.array(m.bounds).reshape(3, 2).T
    return m.translate((x0 - lo[0], fcy - (lo[1] + hi[1]) / 2, fcz - (lo[2] + hi[2]) / 2), inplace=False)


sp, sl, ring, nose = load("spacer"), load("stator_layer"), load("seal_ring"), load("stator_nose")
xe = shroud.bounds[1]
fcy = (sp.bounds[2] + sp.bounds[3]) / 2; fcz = (sp.bounds[4] + sp.bounds[5]) / 2
ring = ring.copy(); ring.rotate_y(90, inplace=True)    # ring axis along X
nose = nose.copy(); nose.rotate_y(-90, inplace=True)   # puck axis along X, peg toward the shroud (-X)
peg = param("nose_peg_len")
sv_x = shifted(sleeve, -15)   # sleeve pulled off the spigot toward the card
g6_ring, g6_spacer = 40, 75                              # display-only shift of the ring and the spacer along X from their fitted place
ring_6 = on_axis(ring, xe + g6_ring)
sp_6 = shifted(sp, g6_spacer)
pl = plotter(); style(pl, "Default stack, exploded (fan not shown): sleeve -> shroud -> key ring -> spacer, all M3x10 countersunk + heat-set inserts\n"
                           "dashed = assembly guides: M3 screws (grey), inserts (brass); the fan bolts to the spacer from the fan side")
add_part(pl, sv_x, SLEEVE); add_part(pl, shroud); add_part(pl, ring_6, "#7fa36b"); add_part(pl, sp_6)

# assembly guides, manual style: each fastener pulled out along its axis (all screws run along +X, head toward -X), with a
# dashed line through the holes it goes in. Positions are the CAD's own (echoed from shroud.scad), moved with the exploded parts.
v = scad("jt_y", "jt_z", "x_s", "lug_t", "cb_depth", "cs_depth", "jt_x_b0", "joint_hole_depth", "x_end", "stack_hole_depth",
         "spacer_t", "fan_hole_depth", "fan_tab_t", "screw_len", "insert_od", "insert_len", "stack_pts", "fan_pts")
SCREW, BRASS = "#5d6670", "#c9a227"


def frustum(x0, x1, r0, r1, y, z):
    """Solid along X from radius r0 at x0 to r1 at x1."""
    c = pv.Cylinder(center=((x0 + x1) / 2, y, z), direction=(1, 0, 0), radius=1, height=x1 - x0, resolution=32).triangulate()
    p = c.points
    r = np.where(p[:, 0] < (x0 + x1) / 2, r0, r1)
    p[:, 1:] = (p[:, 1:] - (y, z)) * r[:, None] + (y, z)
    return c


def screw(xh, y, z, s=1):
    """M3 countersunk screw, head's flat top at xh, tip at xh + s * screw_len (s = -1: head toward +X, pointing -X)."""
    if s < 0:
        return frustum(xh - v["screw_len"], xh - v["cs_depth"], 1.5, 1.5, y, z) + \
               frustum(xh - v["cs_depth"], xh, 1.5, param("cs_head_d") / 2, y, z)
    head = frustum(xh, xh + v["cs_depth"], param("cs_head_d") / 2, 1.5, y, z)
    return head + frustum(xh + v["cs_depth"], xh + v["screw_len"], 1.5, 1.5, y, z)


def insert(x0, y, z):
    return pv.CylinderStructured(center=(x0 + v["insert_len"] / 2, y, z), direction=(1, 0, 0), radius=[1.5, v["insert_od"] / 2],
                                 height=v["insert_len"], theta_resolution=32).extract_surface(algorithm="dataset_surface").triangulate()


def dashed(x0, x1, y, z, dash=3.0, gap=2.0):
    xs = np.arange(x0, x1, dash + gap)
    pts = np.array([[a, y, z] for x in xs for a in (x, min(x + dash, x1))])
    lines = np.hstack([[2, 2 * i, 2 * i + 1] for i in range(len(xs))])
    return pv.PolyData(pts, lines=lines)


glyphs, labels = [], {}
def guide(x0, x1, y, z, parts):
    pl.add_mesh(dashed(x0, x1, y, z), color="#c0392b", line_width=3)
    for m, color in parts:
        add_part(pl, m, color); glyphs.append(m.points)

# sleeve -> shroud: one M3 through the sleeve lug into an insert in the shroud's boss
ds = sv_x.bounds[0] - sleeve.bounds[0]
xh = v["x_s"] - v["lug_t"] + v["cb_depth"] + ds - 20
guide(xh - 2, v["jt_x_b0"] + v["joint_hole_depth"], v["jt_y"], v["jt_z"],
      [(screw(xh, v["jt_y"], v["jt_z"]), SCREW), (insert(v["jt_x_b0"] - v["insert_len"] - 4, v["jt_y"], v["jt_z"]), BRASS)])
labels["sleeve -> shroud: M3x10 + insert (underside, see preview_joint)"] = (xh, v["jt_y"], v["jt_z"])
# spacer -> shroud: 4x M3 from behind the shroud's lug (head in its countersunk pocket) into inserts in the spacer's shroud-side face
x_sp0, x_sp1 = sp_6.bounds[0], sp_6.bounds[1]
for i, (y, z) in enumerate(v["stack_pts"]):
    xh = xe - v["lug_t"] + v["cb_depth"] - 90             # pulled well back, so each head clears the flange behind the funnel
    xi = x_sp0 - v["insert_len"] - 6
    guide(xh - 2, x_sp0 + v["stack_hole_depth"], y, z, [(screw(xh, y, z), SCREW), (insert(xi, y, z), BRASS)])
    if i == 0:
        labels["4x M3x10 from behind the shroud lug"] = (xh, y, z)
        labels["4x insert (spacer, shroud side)"] = (xi, y, z)
# fan -> spacer: 4x M3 from the fan side (head on the fan's corner tab, fan not shown), into inserts in the spacer's fan face,
# so the fan comes off without touching the rest
for i, (y, z) in enumerate(v["fan_pts"]):
    xi = x_sp1 + 4
    xh = xi + v["insert_len"] + 6 + v["fan_tab_t"] + v["screw_len"]
    guide(x_sp1 - v["fan_hole_depth"], xh + 2, y, z, [(insert(xi, y, z), BRASS), (screw(xh, y, z, -1), SCREW)])
    if i == 0:
        labels["4x M3x10 from the fan side (through its corner tab)"] = (xh, y, z)
        labels["4x insert (spacer, fan face)"] = (xi + v["insert_len"], y, z)
top6 = lambda m, f=0.5: (m.bounds[0] + f * (m.bounds[1] - m.bounds[0]), (m.bounds[2] + m.bounds[3]) / 2, m.bounds[5])
labels["key ring (TPU)"] = top6(ring_6)
labels["spacer"] = top6(sp_6, 1.0)
pl.add_point_labels(np.array(list(labels.values())), list(labels.keys()), font_size=16, point_size=1, shape_color="white", shape_opacity=0.85,
                    always_visible=True, text_color=EDGE)
view(pl, np.vstack([sv_x.points, shroud.points, ring_6.points, sp_6.points, *glyphs]), (0.9, -1, 0.7), (0, 0, 1), 1.05); shot(pl, "preview_stack.png")

# 6b. the full modular stack with the optional stator layer, exploded the same way (no fan): sleeve -> shroud (thin lug flange with
# countersunk pockets and the key groove) -> stator layer -> nose puck -> key ring -> spacer. Positions are echoed from the CAD
# with the layer fitted (LAYER_CFG); every part is moved only along X, by the gaps below (display only).
shs = shroud
v = scad("jt_y", "jt_z", "x_s", "lug_t", "cb_depth", "cs_depth", "jt_x_b0", "joint_hole_depth", "x_end", "stack_hole_depth",
         "spacer_t", "stator_layer_t", "fan_hole_depth", "fan_tab_t", "screw_len", "insert_od", "insert_len", "stack_pts", "fan_pts",
         defines=LAYER_CFG)
xe, lt = v["x_end"], v["stator_layer_t"]
g_layer, g_nose, g_ring, g_spacer = 45, 78, 108, 140      # display-only shift of each part along X from its fitted place
sl_x = shifted(sl, g_layer)                                # layer as modelled (x_end .. x_end + layer), pulled out
nose_x = on_axis(nose, xe + lt + g_nose)                   # puck, peg toward the layer's hub socket (-X)
ring_x = on_axis(ring, xe + lt + g_ring)                   # key ring, sits in the layer's and the spacer's facing grooves
sp_x = shifted(sp, lt + g_spacer)                          # spacer: modelled at x_end, fitted at x_end + layer
x_sp0, x_sp1 = sp_x.bounds[0], sp_x.bounds[1]              # spacer's shroud face, fan face
parts6 = [(sv_x, SLEEVE), (shs, BODY), (sl_x, BODY), (nose_x, BODY), (ring_x, "#7fa36b"), (sp_x, BODY)]
pl = plotter(); style(pl, "Stack with the optional stator layer, exploded (fan not shown): sleeve -> shroud -> stator layer -> nose puck -> key ring -> spacer\n"
                           "dashed = assembly guides: M3x10 countersunk screws (grey), heat-set inserts (brass); the fan bolts to the spacer")
# the shroud is see-through here: from any one camera, one of the 4 stack screws behind its lug sits behind the funnel
pl.enable_depth_peeling()
for m, color in parts6:
    add_part(pl, m, color, 0.3 if m is shs else 1.0)
glyphs, labels = [], {}
# sleeve -> shroud: the same joint as above
ds = sv_x.bounds[0] - sleeve.bounds[0]
xh = v["x_s"] - v["lug_t"] + v["cb_depth"] + ds - 20
guide(xh - 2, v["jt_x_b0"] + v["joint_hole_depth"], v["jt_y"], v["jt_z"],
      [(screw(xh, v["jt_y"], v["jt_z"]), SCREW), (insert(v["jt_x_b0"] - v["insert_len"] - 4, v["jt_y"], v["jt_z"]), BRASS)])
labels["sleeve -> shroud: M3x10 + insert"] = (xh, v["jt_y"], v["jt_z"])
# spacer -> shroud: 4x M3 from behind the shroud's lug (head in its countersunk pocket), through the stator layer,
# into inserts pressed into the spacer's shroud-side face
for i, (y, z) in enumerate(v["stack_pts"]):
    xh = xe - v["lug_t"] + v["cb_depth"] - 90             # pulled well back, so each head clears the flange behind the funnel
    xi = x_sp0 - v["insert_len"] - 6
    guide(xh - 2, x_sp0 + v["stack_hole_depth"], y, z, [(screw(xh, y, z), SCREW), (insert(xi, y, z), BRASS)])
    if i == 0:
        labels["4x M3x10 from behind the shroud lug, through the layer"] = (xh, y, z)
        labels["4x insert (spacer, shroud side)"] = (xi, y, z)
# fan -> spacer: 4x M3 from the fan side (through the fan's corner tab, fan not shown) into inserts in the spacer's fan face
for i, (y, z) in enumerate(v["fan_pts"]):
    xi = x_sp1 + 4
    xh = xi + v["insert_len"] + 6 + v["fan_tab_t"] + v["screw_len"]
    guide(x_sp1 - v["fan_hole_depth"], xh + 2, y, z, [(insert(xi, y, z), BRASS), (screw(xh, y, z, -1), SCREW)])
    if i == 0:
        labels["4x M3x10 from the fan side (through its corner tab)"] = (xh, y, z)
        labels["4x insert (spacer, fan face)"] = (xi + v["insert_len"], y, z)
# the parts themselves, labelled on their top edge (+Z; the shroud on its bottom edge, clear of the screw label)
top = lambda m, f=0.5: (m.bounds[0] + f * (m.bounds[1] - m.bounds[0]), (m.bounds[2] + m.bounds[3]) / 2, m.bounds[5])
labels["shroud (lug + key groove)"] = (shs.bounds[0] + 0.55 * (shs.bounds[1] - shs.bounds[0]), shs.bounds[2], shs.bounds[4])   # bottom edge
labels["stator layer (vanes + tail cone reach into the shroud)"] = top(sl_x, 0.97)
labels["nose puck (peg into the layer's hub)"] = top(nose_x)
labels["key ring (TPU)"] = top(ring_x)
labels["spacer (the fan bolts to its far face)"] = top(sp_x, 1.0)
pl.add_point_labels(np.array(list(labels.values())), list(labels.keys()), font_size=16, point_size=1, shape_color="white", shape_opacity=0.85,
                    always_visible=True, text_color=EDGE)
view(pl, np.vstack([m.points for m, _ in parts6] + glyphs), (0.9, -1, 0.7), (0, 0, 1), 1.05); shot(pl, "preview_stack_modules.png")

# 7. spacer and stator layer
pl = plotter((1, 2))
pl.subplot(0, 0); style(pl, "spacer - shroud-side face (groove, insert holes)", sp)
add_part(pl, sp); view(pl, sp, (-1, 0.5, 0.5), (0, 0, 1))
pl.subplot(0, 1); style(pl, "stator layer - shroud side (tongue, vanes, hub, tail cone)", sl)
add_part(pl, sl); view(pl, sl, (-1, -0.45, 0.4), (0, 0, 1))
shot(pl, "preview_modules.png")
# seated: layer as modelled (x_end..x_end + stator_layer_t), ring across the layer/spacer joint, nose pegged into the hub,
# spacer moved out by the layer's thickness
lt = sl.bounds[1] - xe
seated = [shs.clip_closed_surface(normal=(1, 0, 0), origin=(xe - 95, 0, 0)).triangulate(),   # spacer-build shroud: only its last 95 mm
          sl, on_axis(ring, sl.bounds[1] - (ring.bounds[1] - ring.bounds[0]) / 2),
          on_axis(nose, sl.bounds[1] - peg), shifted(sp, lt)]
pl = plotter((1, 2))
pl.subplot(0, 0); style(pl, "fitted stack, cut through the fan axis: shroud end, layer, spacer; nose puck in the spacer bore")
o = np.array([0, fcy, 0])
halves = [add_section(pl, m, (0, 1, 0), o) for m in seated[1:]]
halves.append(add_section(pl, seated[0], (0, 1, 0), o))
view(pl, np.vstack([h.points for h in halves]), (0, -1, 0), (0, 0, 1), 1.1)
pl.subplot(0, 1); style(pl, "stator layer - from the shroud side (9 vanes, hub, tail cone)")
add_part(pl, sl); view(pl, sl, (-1, 0, 0), (0, 0, 1), 1.1)
shot(pl, "preview_stator.png")

# 8. supports
cl, cb = load("support_clip"), load("snap_comb")
has_leg = (OUT / "support_leg.stl").exists()   # support_style "block" exports no leg or foot
pl = plotter((1, 3) if has_leg else (1, 1))
pl.subplot(0, 0); style(pl, "support_clip (hex bar seat, snap arms)" if has_leg else "support_clip (block: base stands on the case floor)", cl)
add_part(pl, cl); view(pl, cl, (0.6, -0.6, 0.8), (0, 1, 0))
if has_leg:
    lg, ft = load("support_leg"), load("support_foot")
    pl.subplot(0, 1); style(pl, "support_leg (tenon up, thread socket below)", lg); add_part(pl, lg); view(pl, lg, (1, -1, 0.9), (0, 0, 1))
    pl.subplot(0, 2); style(pl, "support_foot (disc on the bed, thread stud)", ft); add_part(pl, ft); view(pl, ft, (1, -1, 0.9), (0, 0, 1))
shot(pl, "preview_support_parts.png")
pl = plotter(); style(pl, "snap_comb - bar plus clips at 5 interference values (dimples = index)", cb)
add_part(pl, cb); view(pl, cb, (0.8, -0.8, 1), (0, 1, 0)); shot(pl, "preview_comb.png")
sa = load("support_assy")
pl = plotter(); style(pl, "support_assy - as in the tower: +Y (fins, separator) points down (no fan)", sa)
add_part(pl, sa); view(pl, sa, (0.35, -0.25, 1), (0, -1, 0), 1.05); shot(pl, "preview_support_assy.png")

# 9. fit-check interface coupon
fi = load("fitcheck_interface")
pl = plotter((1, 2))
pl.subplot(0, 0); style(pl, "fitcheck_interface - fan face (-Z, on the bed): insert holes", fi); add_part(pl, fi); view(pl, fi, (0.35, -0.3, -1), (0, 1, 0))
pl.subplot(0, 1); style(pl, "fitcheck_interface - funnel side (+Z, up)", fi); add_part(pl, fi); view(pl, fi, (0.35, -0.3, 1), (0, 1, 0))
shot(pl, "preview_interface.png")

# 10. fan-face coupons: the three flare variants side by side (index holes 1 / 2 / 3), plus a cut through the default
fv = [load(f"fitcheck_fanface_d{d}") for d in (127, 132, 137)]
pl = plotter((1, 3))
for i, (d, m) in enumerate(zip((127, 132, 137), fv)):
    pl.subplot(0, i); style(pl, f"fitcheck_fanface_d{d} - {i + 1} index hole(s)", m); add_part(pl, m); view(pl, m, (0.05, -0.05, 1), (0, 1, 0))
shot(pl, "preview_fanface.png")
