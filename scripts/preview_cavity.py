"""Cross-section of the sleeve cavity with the measured card outline drawn inside it.

Usage: scripts/preview_cavity.sh   (needs output/sleeve.stl from scripts/export.sh)
Card coordinates: horizontal = Y (card thickness, fins to the right), vertical = Z (card height).
Reads the card dimensions from cad/params.scad so the drawing follows the parameters.
"""
import pathlib, re
import numpy as np
import pyvista as pv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

ROOT = pathlib.Path(__file__).resolve().parent.parent
txt = (ROOT / "cad" / "params.scad").read_text()
def num(n): return float(re.search(rf"^{n}\s*=\s*([0-9.]+)\s*;", txt, re.M).group(1))
pcb_t, pcb_h, back_t, back_w, hs_t, hs_w, hs_w_tip, chan_h, chan_hz, clr = (num(n) for n in
    ["pcb_t", "pcb_h", "back_t", "back_w", "hs_t", "hs_w", "hs_w_tip", "hs_h", "chan_hz", "slide_clear"])
cz = pcb_h / 2

m = pv.read(ROOT / "output" / "sleeve.stl").clean()
x_cut = m.bounds[0] + 1.5   # inside the grip, before the stop face
sl = m.slice(normal=(1, 0, 0), origin=(x_cut, 0, 0))

fig, ax = plt.subplots(figsize=(10, 6.5), dpi=150)
# sleeve section: draw the cut contour (outer wall + cavity)
for i in range(sl.n_lines if hasattr(sl, "n_lines") else 0):
    pass
pts = sl.points
lines = sl.lines.reshape(-1, 3)[:, 1:]
for a, b in lines:
    ax.plot([pts[a][1], pts[b][1]], [pts[a][2], pts[b][2]], color="#1b2b33", lw=1.4)
# card layers
def poly(c, pts_, label):
    ax.add_patch(Polygon(pts_, closed=True, fc=c, ec="#333", alpha=0.65, lw=1, label=label))
poly("#8f8f8f", [(-pcb_t - back_t, cz - back_w/2), (-pcb_t, cz - back_w/2), (-pcb_t, cz + back_w/2), (-pcb_t - back_t, cz + back_w/2)], f"back cover {back_t:g} x {back_w:g}")
poly("#3f8f4f", [(-pcb_t, 0), (0, 0), (0, pcb_h), (-pcb_t, pcb_h)], f"PCB {pcb_t:g} x {pcb_h:g}")
poly("#d9822b", [(0, cz - hs_w/2), (hs_t, cz - hs_w_tip/2), (hs_t, cz + hs_w_tip/2), (0, cz + hs_w/2)], f"cooling block {hs_t:g} thick, {hs_w:g} -> {hs_w_tip:g}")
ax.add_patch(plt.Rectangle((hs_t - chan_h, cz - chan_hz/2), chan_h, chan_hz, fill=False, ec="#c0392b", ls="--", lw=1.4, label=f"inlet channel {chan_h:g} x {chan_hz:g} at the fin tips, y {hs_t - chan_h:g} to {hs_t:g} (beyond the stop)"))
ax.axvline(hs_t - chan_h, color="#555", ls=":", lw=1, label=f"solid base {hs_t - chan_h:g} mm | fins {chan_h:g} mm")
ax.set_aspect("equal"); ax.set_xlabel("Y (mm): back of card  ->  fin tips"); ax.set_ylabel("Z (mm): card height")
bce = num("back_clear_extra")
ax.set_title(f"Sleeve cavity section with the measured card outline (slide_clear {clr:g} mm per side, +{bce:g} mm above the back cover)")
ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.12), ncol=2, fontsize=8)
ax.autoscale(); ax.grid(alpha=0.25)
fig.savefig(ROOT / "output" / "preview_cavity.png", bbox_inches="tight")
print("wrote output/preview_cavity.png")
