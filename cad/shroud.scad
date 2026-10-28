// SPDX-License-Identifier: CERN-OHL-P-2.0
// Copyright 2026 Arthurdw. See LICENSE and NOTICE.
// Tesla P4 cooling shroud: parametric model.  All inputs live in params.scad.
// Build a part with:  openscad -D 'part="shroud_print"' -o out.stl shroud.scad
// Nothing here validates cooling performance; it only builds geometry. The fan and the GPU are never part of any output
// (they only exist in the interference check and in cfd/).
include <params.scad>

eps = 0.01;

// Countersunk head seat (see head_pocket): cone depth below the pocket floor, and how far the head sits below that floor.
cs_depth = screw_head == "countersunk" ? (cs_head_d + cs_clear - screw_clear_d)/2 / tan(cs_angle/2) : 0;   // cone depth below the floor
cs_drop  = screw_head == "countersunk" ? cs_clear/2 / tan(cs_angle/2) : 0;   // the head's flat top sits this far below the floor, so the tip goes this much deeper than a flat head's
cs_head_h = screw_head == "countersunk" ? (cs_head_d - 3)/2 / tan(cs_angle/2) : 0;  // cone height of the head; on a flat fan tab it stands proud by up to this much

// ---- derived geometry (card coordinates, see params.scad) ----
cav_cz = pcb_h / 2;                     // card centre in Z; back cover and block are centred on the PCB [MEASURED, user visual check]
// Stepped sleeve cavity: the union of the back cover, PCB and cooling block outlines in the Y-Z plane (2D x = card Y, 2D y = card Z),
// each grown by g. g = slide_clear gives the cavity, g = slide_clear + wall the sleeve's outer wall (same wall thickness everywhere).
// cav = true for the cavity: the PCB slot is then added again with square corners (offset delta), so the square board edge
// does not ride on the rounded r = g slot ends. The outer wall (cav = false) keeps the rounded corners.
module card2d(g, cav = false) {
    offset(r = g) union() {
        translate([-(pcb_t + back_t + back_clear_extra), cav_cz - back_w/2]) square([back_t + back_clear_extra, back_w]);   // back cover (+ extra room above it)
        pcb_slot2d();
        polygon([[0, cav_cz - hs_w/2], [hs_t, cav_cz - hs_w_tip/2], [hs_t, cav_cz + hs_w_tip/2], [0, cav_cz + hs_w/2]]);   // block, tapered
    }
    if (cav) offset(delta = g) pcb_slot2d();
}
// PCB slot before the slide clearance: the board plus pcb_slot_extra_y on each face (Y) and pcb_clear_extra at each edge (Z).
module pcb_slot2d() {
    translate([-pcb_t - pcb_slot_extra_y, cav_cz - pcb_h/2 - pcb_clear_extra]) square([pcb_t + 2*pcb_slot_extra_y, pcb_h + 2*pcb_clear_extra]);
}
// Only the bare PCB slot (the part of the card that sticks out pcb_extra past the block end; the back cover ends flush with the block),
// grown by g with square corners (it is only ever used as a cavity).
module pcb2d(g) { offset(delta = g) pcb_slot2d(); }
// Bounding box of the cavity (used for the fan placement, the funnel and the CFD).
y_lo = -(pcb_t + back_t + back_clear_extra) - slide_clear;
y_hi = hs_t + slide_clear;
z_lo = cav_cz - pcb_h / 2 - pcb_clear_extra - slide_clear;
z_hi = cav_cz + pcb_h / 2 + pcb_clear_extra + slide_clear;
cav_w = y_hi - y_lo;
cav_h = z_hi - z_lo;
cav_cy = (y_lo + y_hi) / 2;
x_card = pcb_extra;                     // card end (PCB end)
x_a = -grip;                            // sleeve mouth: slides `grip` mm over the block end (x = 0)
x_stop = stop_gap;                      // the block end face seats on the channel step here
x_pocket = x_card + pcb_end_clear;      // end of the PCB pocket; the PCB never bottoms out, the block takes the stop
// Fan edge flush with one sleeve edge so nothing sticks out on that side; the funnel ducts the other way.
_po = fan_size;
// Y: "hi" = fan edge level with the sleeve outer edge on the fin side (toward the CPU cooler when the fins face down), funnel spreads toward -Y; "lo" is the default (fan grows toward the fin side).
fan_cy = fan_flush_y == "hi" ? (y_hi + wall - _po/2)
       : fan_flush_y == "lo" ? (y_lo - wall + _po/2)
       : cav_cy + fan_off_y;
fan_cz = fan_flush == "bottom" ? (z_lo - wall + _po/2)
       : fan_flush == "top"    ? (z_hi + wall - _po/2)
       : cav_cz + fan_off_z;

x_s = pcb_extra + straight_extra;       // end of the straight sleeve
x_f = x_s + trans_len;                  // funnel end / start of the plenum
x_end = x_f + plenum_len + flange_t;    // shroud mounting face (the module, or the fan in a direct mount, sits on it)
pitch = fan_pitch(fan_size);
chan_y0 = hs_base;   // channel starts above the 6 mm solid base: y = hs_base .. hs_t (the fin passages)
chan_cy = chan_y0 + chan_h / 2;
chan_w  = chan_h;

// Bellmouth: from the fan face a straight 45 degree cone (continuing the fan's own flare), then a circular arc tangent to it
// that turns to straight (axial) at fan_open_d, flare_depth deep from the fan face. Its steepest point is 45 degrees, so it prints.
// The arc gives radial R (1 - cos 45) and axial R sin 45, the cone s radial = s axial; so depth = D + R (sqrt(2) - 1) for a step D.
flare_D     = (fan_flare_d - fan_open_d) / 2;                      // radial step from the bore to the face
flare_R     = (flare_depth - flare_D) / (sqrt(2) - 1);             // arc radius
flare_cone  = flare_D - flare_R * (1 - cos(45));                   // axial (= radial) length of the 45 degree cone at the face
function bell_r(t)  = t <= flare_cone ? fan_flare_d/2 - max(0, t)                                    // bore radius at depth t from the fan face
                    : t >= flare_depth ? fan_open_d/2
                    : fan_open_d/2 + flare_R * (1 - cos(asin((flare_depth - t) / flare_R)));

stator_ns = 6;   // slices per vane (geometry resolution only)
// ---- stack module (between the shroud and the fan), and the optional stator layer between the module and the shroud ----
function mod_t(m) = m == "spacer" ? spacer_t : 0;
module_t = mod_t(stack_module);
// Thickness of the shroud's corner plate (lug). Direct mount: the fan inserts sit in it, so it is the whole flange. Otherwise lug_t.
// lug_t itself is also the sleeve's lug thickness, so the sleeve must keep using lug_t.
fl_lug = stack_module == "none" ? flange_t : lug_t;
layer_t  = stator_layer ? stator_layer_t : 0;           // a fitted stator layer pushes the module and the fan out by its thickness
joint_d  = 2 * bell_r(module_t);                        // bore diameter at the module / shroud joint
stack_hole_depth = screw_len + cs_drop - (lug_t - cb_depth) + 0.5;   // insert hole depth in the module
fan_fx = x_end + layer_t + module_t;                    // the fan's mounting face
stack_total = fan_fx + fan_t;   // card end (X 0) to the fan's back face
echo(str("stack length, card end to fan back face: ", stack_total, " mm (limit stack_max_len ", stack_max_len, "); shroud x_end ", x_end, ", module ", module_t, ", stator layer ", layer_t));
assert(stack_total <= stack_max_len + 0.001, str("stack ", stack_total, " mm longer than stack_max_len ", stack_max_len, " (fan back face at X ", stack_total, ")"));
// Round shell around the plenum: the funnel's 120 mm square ends in a short 45 degree cone onto a cylinder, then the lug plate.
// The cylinder only wraps the bore inside the shroud (at its mounting-face end the bellmouth is bell_r(module_t + lug_t) deep
// in), never the full flare, but never less than the funnel's rounded corners. shroud() trims it to the fan's 120 mm square
// (flat on the four sides, round at the corners; on the flats the wall is the square minus the bore, >= flare_rim).
// shell_d still sets the support bar's height, so the bar and its clips are unchanged by the trim.
shell_d    = 2 * max(bell_r(module_t + fl_lug) + wall, (fan_size/2 - fun_end_r) * sqrt(2) + fun_end_r);
shell_cone = shell_d/2 - fan_size/2 + 0.1;
function gcd(a, b) = b == 0 ? a : gcd(b, a % b);
stack_pts = [for (i = [0:3]) let(a = 45 + stack_ang + 90*i) [fan_cy + stack_r*cos(a), fan_cz + stack_r*sin(a)]];
fan_pts   = [for (sy = [-1, 1], sz = [-1, 1]) [fan_cy + sy*pitch/2, fan_cz + sz*pitch/2]];
rg_i = fan_open_d/2 + tg_wall;                           // groove inner radius
rg_o = rg_i + tg_w + 2*tg_clear;                         // groove outer radius

// ---- build-time sanity checks (a failed assert makes the export fail) ----
assert(!release || params_confirmed, "Release build refused: params_confirmed is false (placeholders in use).");
assert(!is_undef(pitch), "fan_size has no known hole pitch; add it to fan_pitch() in params.scad");
assert(fan_flush == "bottom" || fan_flush == "top" || fan_flush == "none", "fan_flush must be \"bottom\", \"top\" or \"none\"");
assert(fan_flush_y == "hi" || fan_flush_y == "lo" || fan_flush_y == "none", "fan_flush_y must be \"hi\", \"lo\" or \"none\"");
assert(fan_stack == 1 || fan_stack == 2, "fan_stack must be 1 or 2");
assert(fan_open_d <= fan_size - 2, "fan_open_d too large for fan_size");
assert(stack_module == "spacer" || stack_module == "none", "stack_module must be \"spacer\" or \"none\" (the stator is now stator_layer, see params.scad)");
assert(fan_flare_d >= fan_open_d, "fan_flare_d must be >= fan_open_d");
assert(flare_depth >= flare_D - 0.001, "flare_depth shallower than a pure 45 degree chamfer (needs >= (fan_flare_d - fan_open_d)/2)");
assert(flare_depth <= flare_D * sin(45) / (1 - cos(45)) + 0.001, "flare_depth deeper than a pure arc (needs <= 2.414 x (fan_flare_d - fan_open_d)/2)");
assert(flare_depth <= flange_t + plenum_len, "fan flare deeper than the flange + plenum");
assert(lug_t > cb_depth + 1.5, "lug_t too thin for the counterbore");
assert(fl_lug <= flange_t, "lug_t cannot exceed flange_t");
// Funnel slope: every wall may move at most trans_len over trans_len (45 degrees) so it prints
// without support when the fan end is on the bed.
function _dev() = [
    abs((chan_y0 + chan_h + wall) - (fan_cy + fan_size/2)),
    abs((chan_y0 - wall) - (fan_cy - fan_size/2)),
    abs((cav_cz + chan_hz/2 + wall) - (fan_cz + fan_size/2)),
    abs((cav_cz - chan_hz/2 - wall) - (fan_cz - fan_size/2)),
    abs((chan_y0 + chan_h) - (fan_cy + fan_open_d/2)),
    abs((chan_y0) - (fan_cy - fan_open_d/2)),
    abs((cav_cz + chan_hz/2) - (fan_cz + fan_open_d/2)),
    abs((cav_cz - chan_hz/2) - (fan_cz - fan_open_d/2))
];
// Contraction profile: "linear" (straight-line walls) or "poly5" (5th-order smoothstep, zero slope at both ends).
// The steepest point of poly5 is 1.875x the average slope, so the 45 degree limit needs trans_len >= 1.875 * max wall shift.
_slope_f = contr_poly5 ? 1.875 : 1;
_ovh_dev = atan(max(_dev()) * _slope_f / trans_len);   // steepest wall, degrees from the axis (45 = prints with no support)
assert(_ovh_dev <= max_overhang_deg + 0.001,
       str("Funnel too steep: max wall shift ", max(_dev()), " mm (x slope factor ", _slope_f, ") over trans_len ", trans_len,
           " mm = ", _ovh_dev, " deg > max_overhang_deg ", max_overhang_deg, ". Increase trans_len or max_overhang_deg."));
// The same limit in every direction (the rounded corners move along the diagonal): support function of a rounded rectangle
// in direction th, which is linear in its parameters, so the funnel's wall shift in that direction is the difference of the ends.
function _hsup(w, h, r, cy, cz, th) = (w/2 - r)*abs(cos(th)) + (h/2 - r)*abs(sin(th)) + r + cy*cos(th) + cz*sin(th);
function _shift(w0, h0, r0, cy0, cz0, w1, h1, r1, cy1, cz1) =
    max([for (th = [0:359]) abs(_hsup(w1, h1, r1, cy1, cz1, th) - _hsup(w0, h0, r0, cy0, cz0, th))]);
_sh_out = _shift(chan_w + 2*wall, chan_hz + 2*wall, chan_r + wall, chan_cy, cav_cz, fan_size, fan_size, fun_end_r, fan_cy, fan_cz);
_sh_in  = _shift(chan_w, chan_hz, chan_r, chan_cy, cav_cz, fan_open_d, fan_open_d, fan_open_d/2 - 0.01, fan_cy, fan_cz);
_ovh_dir = atan(max(_sh_out, _sh_in) * _slope_f / trans_len);
assert(_ovh_dir <= max_overhang_deg + 0.001,
       str("Funnel too steep in some direction (corner radius fun_end_r?): outer ", _sh_out, " inner ", _sh_in, " mm over trans_len ", trans_len, " = ", _ovh_dir, " deg"));
echo(str("funnel overhang: steepest wall ", max(_ovh_dev, _ovh_dir), " deg from the axis (limit ", max_overhang_deg, "); ",
         max(_ovh_dev, _ovh_dir) > 45 ? "over 45: needs the overhang allowance, printed fan face down it is the INSIDE face of the narrowing wall" : "support-free"));
assert((fan_size/2 - fun_end_r) * sqrt(2) + fun_end_r <= shell_d/2, "funnel corners poke out of the round shell; raise fun_end_r");
assert(shell_d/2 - fan_size/2 <= shell_cone, "shell cone steeper than 45 degrees");

// Stack module checks.
_sp_max = max([for (p = stack_pts) max(abs(p[0] - fan_cy), abs(p[1] - fan_cz))]);
assert(stack_module == "none" || _sp_max + insert_od/2 + 1 <= fan_size/2, "stack screw inserts too close to the module's edge");
assert(_sp_max + cb_d/2 + 0.9 <= fan_size/2, "stack counterbores too close to the plate's edge");
assert(stack_r - cb_d/2 >= shell_d/2 + 0.5, "stack counterbore cuts into the round shell");
// the inserts sit in the module from its shroud side, stack_hole_depth deep; the bore there is widest at the shallow end
assert(stack_module == "none" || stack_r - insert_od/2 - bell_r(max(0, module_t - stack_hole_depth)) >= 1.5, "stack inserts too close to the bellmouth");
assert(norm([stack_pts[0][0] - fan_cy - (fan_pts[3][0] - fan_cy), stack_pts[0][1] - fan_cz - (fan_pts[3][1] - fan_cz)]) >= 0, "unreachable");
_dsf = min([for (p = stack_pts) for (q = fan_pts) norm([p[0] - q[0], p[1] - q[1]])]);
assert(_dsf >= cb_d + 1.5, str("stack screws too close to the fan screws: ", _dsf, " mm"));
assert(stack_module == "none" || module_t >= stack_hole_depth + 1.5, "module too thin for the stack screws");
assert(stack_module == "none" || module_t >= insert_len + 2, "module too thin for the heat-set inserts");
// ---- screw joints ----
// Insert joints: the screw's reach past everything it clamps (the lug floor lug_t - cb_depth, plus any plate or gap in between)
// goes into the insert hole. Thread engagement = min(reach, insert_len) must be >= min_thread of real thread, and the hole must be
// >= reach + 0.5 deep so the screw never bottoms. Echoed: the shortest of screw_lengths that passes both, per joint.
min_thread = 3;
function _reach(L, clamp) = L + cs_drop - clamp;   // cs_drop: a countersunk head seats cs_drop below the floor the clamps are measured from
function _engage(L, clamp) = min(_reach(L, clamp), insert_len);
function _screw_ok(L, clamp, hole) = _engage(L, clamp) >= min_thread - 0.001 && hole >= _reach(L, clamp) + 0.5 - 0.001;
function _shortest(clamp, hole) = let(ok = [for (L = screw_lengths) if (_screw_ok(L, clamp, hole)) L]) len(ok) > 0 ? min(ok) : "none";
lug_floor = lug_t - cb_depth;                                  // under the head in every counterbored lug (2.3 mm)
// The cone seat must leave a cylindrical land of the clearance hole: floor >= cone depth + cs_land.
cs_land = 0.8;   // [ASSUMED] least floor left under the cone seat
assert(lug_floor >= cs_depth + cs_land - 0.001, str("lug floor ", lug_floor, " mm too thin for the countersink (", cs_depth, " + ", cs_land, "): thicken lug_t or cb_depth smaller"));
assert(cs_head_d + cs_clear < cb_d, "countersink seat wider than the counterbore");
// Fan -> spacer (insert joint, screw from the fan side): the head sits on the flat fan tab, so it clamps the tab (+ gasket)
// and, worst case, its whole cone (cs_head_h) stands proud. The hole takes the deepest reach (head fully sunk) + 0.5.
_fan_clamp = fan_tab_t + (fan_gasket ? seal_t : 0) + cs_head_h;
fan_hole_depth = screw_len - _fan_clamp + cs_head_h + 0.5;   // insert hole in the spacer, opening toward +X (the fan face)
assert(_screw_ok(screw_len, _fan_clamp, fan_hole_depth),
       str("fan joint: the screws engage only ", _engage(screw_len, _fan_clamp), " mm of the spacer's inserts (need >= ", min_thread, ")"));
assert(stack_module == "none" ? fl_lug >= fan_hole_depth + 1.5 : spacer_t >= fan_hole_depth + 1.5, "spacer / flange too thin for the fan inserts");
// insert to bellmouth: the flare is widest at the fan face, where the inserts start
assert(min([for (p = fan_pts) norm([p[0] - fan_cy, p[1] - fan_cz])]) - insert_od/2 - fan_flare_d/2 >= 1.5, "fan inserts too close to the bellmouth");
// Module -> shroud (stack screws into the spacer's inserts); with the stator layer its plate is clamped too.
_st_clamp = lug_floor;
_sl_clamp = lug_floor + stator_layer_t;
assert(!stator_layer || stack_module == "spacer", "stator_layer needs stack_module = \"spacer\" (the layer sits between the spacer and the shroud)");
assert(stack_module == "none" || _screw_ok(screw_len, _st_clamp, stack_hole_depth),
       str("stack screws: engagement ", _engage(screw_len, _st_clamp), " mm (need >= ", min_thread, "), insert hole ", stack_hole_depth, " mm for a reach of ", _reach(screw_len, _st_clamp)));
assert(!stator_layer || _screw_ok(screw_len, _sl_clamp, stack_hole_depth),
       str("stator layer: the stack screws engage only ", _engage(screw_len, _sl_clamp), " mm of the inserts (need >= ", min_thread, "); thinner stator_layer_t or longer screws"));
// Sleeve -> shroud: lug floor + joint_gap clamped, into the insert in the funnel's boss.
_jt_clamp = lug_floor + joint_gap;
joint_hole_depth = _reach(screw_len, _jt_clamp) + 0.5;      // insert hole in the boss, opening toward -X
assert(_screw_ok(screw_len, _jt_clamp, joint_hole_depth), str("sleeve joint: engagement ", _engage(screw_len, _jt_clamp), " mm (need >= ", min_thread, ")"));
echo(str("screw joints (M3 x ", screw_len, " everywhere; engagement mm / shortest of ", screw_lengths, " that works): ",
         "fan -> ", str(stack_module == "none" ? "shroud flange" : "module", " (from the fan side) ", _engage(screw_len, _fan_clamp), " / ", _shortest(_fan_clamp, fan_hole_depth)),
         "; module -> shroud ", stack_module == "none" ? "n/a" : str(_engage(screw_len, _st_clamp), " / ", _shortest(_st_clamp, stack_hole_depth)),
         "; with stator layer ", stack_module == "none" ? "n/a" : str(_engage(screw_len, _sl_clamp), " / ", _shortest(_sl_clamp, stack_hole_depth)),
         "; sleeve -> shroud ", _engage(screw_len, _jt_clamp), " / ", _shortest(_jt_clamp, joint_hole_depth)));
assert(!stator_layer || (vanes_y == 0 && vanes_z == 0), "stator layer: its vanes, hub and tail cone reach into the shroud's bore, where the splitter vanes would be");
assert(stack_module != "spacer" || spacer_t + fan_blade_to_face >= stator_gap, "stator layer: vane leading edges (at the spacer's shroud side) closer than stator_gap to the fan blades");
assert(stator_layer_t - tg_h >= 1.2 - 0.001, "stator layer too thin for its key groove");
assert(stator_chord > stator_layer_t, "stator_chord must be longer than stator_layer_t");
assert(gcd(stator_n, fan_blades) == 1, "stator_n shares a factor with fan_blades");
assert(stator_vane == "flat" || stator_vane == "cambered", "stator_vane must be \"flat\" or \"cambered\"");
assert(stator_vane != "flat" || stator_in_deg <= 45, "flat stator vanes steeper than 45 degrees (they print without supports only up to 45; use stator_vane = \"cambered\")");
assert(stator_vane == "flat" || (stator_in_hub < 90 && stator_in_tip < 90 && stator_out_deg >= 0), "stator inlet angles must be below 90 degrees");
assert(stator_chord - stator_layer_t <= plenum_len + flange_t - 1, "stator_chord reaches past the straight bore into the funnel");
assert(stack_module == "none" || rg_i - bell_r(max(0, module_t - tg_h)) >= 1.0 - 0.001, "tongue-and-groove too close to the bore");
assert(fan_size/2 - rg_o >= 1.2 - 0.001, "tongue-and-groove too close to the outer edge");
assert(stack_module == "none" || rg_i - bell_r(max(0, module_t + tg_h)) >= 1.0 - 0.001, "tongue-and-groove too close to the shroud bore");

// ---- 2D/3D helpers ----
module rrect(w, h, r) { offset(r) square([w - 2*r, h - 2*r], center = true); }

// Extrusion along X of a rounded rectangle (w along Y, h along Z) centred at (cy, cz).
module prism(x0, x1, cy, cz, w, h, r) {
    translate([x0, cy, cz]) rotate([90, 0, 90]) linear_extrude(x1 - x0) rrect(w, h, r);
}
module slab(x, cy, cz, w, h, r) { prism(x, x + eps, cy, cz, w, h, r); }
module cslab(x, cy, cz, d) {
    translate([x, cy, cz]) rotate([90, 0, 90]) linear_extrude(eps) circle(d = d);
}
// Cylinder / ring / 2D profile along X (the profile's x is world Y, its y is world Z).
module cyl_x(x0, x1, cy, cz, d) { translate([x0, cy, cz]) rotate([0, 90, 0]) cylinder(d = d, h = x1 - x0); }
module ring_x(x0, x1, cy, cz, ri, ro) { difference() { cyl_x(x0, x1, cy, cz, 2*ro); cyl_x(x0 - 1, x1 + 1, cy, cz, 2*ri); } }
// Screw head pocket along X, opening toward -X: counterbore from x0 to the floor xf, then the 90 degree cone seat (wide at xf,
// narrowing toward +X to the clearance hole, so it opens upward in every print orientation here), then the clearance hole to x1.
module head_pocket(x0, xf, x1, cy, cz) {
    cyl_x(x0, xf, cy, cz, cb_d);
    if (screw_head == "countersunk")
        translate([xf - eps, cy, cz]) rotate([0, 90, 0]) cylinder(d1 = cs_head_d + cs_clear + 2*eps*tan(cs_angle/2), d2 = screw_clear_d, h = cs_depth + eps);
    cyl_x(x0, x1, cy, cz, screw_clear_d);
}
module ext_x(x0, x1, cy, cz) { translate([x0, cy, cz]) rotate([90, 0, 90]) linear_extrude(x1 - x0) children(); }

module box(b) { translate([b[0], b[2], b[4]]) cube([b[1]-b[0], b[3]-b[2], b[5]-b[4]]); }

// ---- fan end ----
// Air opening ending at the fan mounting face (x = xf), from x0: fan_open_d, opening in a bellmouth to
// fan_flare_d at the face to sit against the fan frame's own flare. Where the flare would cut through
// the sides of the plate it is clipped, leaving flare_rim, so the flange stays one piece.
module fan_opening(x0, xf, cy, cz) {
    r0 = fan_open_d / 2;
    rf = fan_flare_d / 2;
    // profile in (radius, depth from the face): arc from straight to 45 deg, then the 45 deg cone to the face and on past it
    arc = [for (a = [0 : 3 : 45]) [r0 + flare_R * (1 - cos(a)), -flare_depth + flare_R * sin(a)]];
    translate([x0, cy, cz]) rotate([0, 90, 0]) cylinder(d = fan_open_d, h = xf - x0 + 1);
    if (flare_depth > 0) intersection() {
        translate([xf, cy, cz]) rotate([0, 90, 0]) rotate_extrude($fn = 128)
            polygon(concat([[0, -flare_depth - eps]], arc, flare_cone > 0.001 ? [[rf, 0]] : [], [[rf + 1, 1], [0, 1]]));
        translate([xf - flare_depth - 1, cy - fan_size/2 + flare_rim, cz - fan_size/2 + flare_rim])
            cube([flare_depth + 2, fan_size - 2*flare_rim, fan_size - 2*flare_rim]);
    }
}

// ---- sleeve + funnel ----
// The outer outline is a plain rounded rectangle, the cavity's bounding box grown by wall, corner radius sleeve_r: the same shape
// family as the socket's outside, so the shoulder below is an exact loft between the two (no creases, ridges or slivers).
// Sides as [y0, y1, z0, z1, r].
_mouth_o = [y_lo - wall, y_hi + wall, z_lo - wall, z_hi + wall, sleeve_r];
// Blend of two such outlines: fraction f for every side and the radius, f1 for the +Y side.
function _rr_lerp(a, b, f, f1) = [for (i = [0:4]) _lerp(a[i], b[i], i == 1 ? f1 : f)];
module rr_slab(x, s) { slab(x, (s[0] + s[1])/2, (s[2] + s[3])/2, s[1] - s[0], s[3] - s[2], s[4]); }
module sleeve_outer2d() { translate([(_mouth_o[0] + _mouth_o[1])/2, (_mouth_o[2] + _mouth_o[3])/2]) rrect(_mouth_o[1] - _mouth_o[0], _mouth_o[3] - _mouth_o[2], sleeve_r); }
module sleeve_outer(x0, x1) { ext_x(x0, x1, 0, 0) sleeve_outer2d(); }
module sleeve_cavity(x0, x1) { ext_x(x0, x1, 0, 0) card2d(slide_clear, cav = true); }

// Inlet channel past the card end: the fin passage (chan_h tall over the PCB face, chan_hz wide, centred on the card), so all the air goes into the fins. Its start face is the stop that catches the PCB end.
module channel(x0, x1) { prism(x0, x1, chan_cy, cav_cz, chan_w, chan_hz, chan_r); }
module channel_outer(x0, x1) { prism(x0, x1, chan_cy, cav_cz, chan_w + 2*wall, chan_hz + 2*wall, chan_r + wall); }
// The 45 degree outer shoulder (below) starts chan_step0 past the stop face, so the wall at the cavity's inner corner
// stays a full wall thick, measured square to the 45 degree face.
// The sleeve body, shared by the sleeve part and the fit-check print so both always match: a straight, full-size mouth from
// x0 that slides over the block end (square rim, it seats straight onto the card) up to x_stop, where the block end face
// and the flush back cover seat on a flat inner step and the fins open straight into the inlet channel (up to x_s). A pocket
// takes the bare PCB that sticks out past the block, pcb_end_clear deeper than the PCB end. The step and the
// pocket floor face up when printing; the outside follows the channel with a 45 degree shoulder, so none needs support.
module sleeve_body(x0) {
    xc = x_pocket;
    assert(pcb_extra >= 0, "pcb_extra < 0 (block past the PCB end) is not modelled");
    assert(x0 < x_stop, "sleeve mouth does not reach over the block end");
    assert(xc + chan_step0 + chan_step <= jt_x_c + jt_sock - wall*sqrt(2) + 0.001,   // the 45 degree shoulder stays a full wall (normal) outside the socket's 45 degree cone floor
           str("straight_extra too short for the PCB pocket + 45 degree outer shoulder over the socket cone: shoulder ends at ", xc + chan_step0 + chan_step, ", limit ", jt_x_c + jt_sock - wall*sqrt(2)));
    assert(chan_y0 + chan_h < y_hi && cav_cz - chan_hz/2 > z_lo && cav_cz + chan_hz/2 < z_hi && chan_hz > 0, "inlet channel larger than the entry");
    assert(chan_h < hs_t && chan_hz < hs_w_tip, "the inlet channel must be smaller than the block end face, or there is no stop face");
    assert(chan_y0 > slide_clear + 1, "no wall between the PCB pocket and the inlet channel");
    assert(jt_x_o > xc + chan_step0, "joint socket starts before the outer shoulder: lengthen straight_extra");
    difference() {
        union() {
            sleeve_outer(x0, xc + chan_step0);
            // Shoulder: a loft from the mouth's rounded rectangle to the socket's, each side and the corner radius moving linearly.
            // Sides where the socket is smaller close in by xe (45 degrees at the steepest); a side where it is bigger (the fin side)
            // is full size by jt_x_o, so the socket's full-wall section never sticks out of the shoulder as a wedge. The hull of two
            // rounded rectangles in parallel planes is exactly that linear blend, so one hull per segment (break at jt_x_o) is exact.
            xa = xc + chan_step0;
            xe = xa + chan_step;
            so = [chan_y0 - jt_sock, chan_y0 + chan_h + jt_sock, cav_cz - chan_hz/2 - jt_sock, cav_cz + chan_hz/2 + jt_sock, chan_r + jt_sock];
            xm = min(jt_x_o, xe);
            fm = (xm - xa) / max(xe - xa, eps);
            // the fin side (+Y, index 1) follows the others where it shrinks, else it is full size by xm
            g1 = so[1] < _mouth_o[1] ? fm : 1;
            hull() { rr_slab(xa - eps, _mouth_o); rr_slab(xm, _rr_lerp(_mouth_o, so, fm, g1)); }
            hull() { rr_slab(xm, _rr_lerp(_mouth_o, so, fm, g1)); rr_slab(xe, so); }
            socket_bore(xc + chan_step0 + chan_step, x_s, jt_sock);
        }
        sleeve_cavity(x0 - 1, x_stop);
        ext_x(x0 - 1, xc, 0, 0) pcb2d(slide_clear);
        channel(x_stop - eps, x_s + eps);
    }
}

// ---- sleeve / shroud joint (one M3 along +X, insert in the shroud) ----
jt_x_t  = x_s - joint_overlap;                // spigot tip (the shroud's -X end)
jt_x_k  = jt_x_t - joint_gap;                 // socket floor: end of the straight bore
jt_bore = wall + joint_clear;                 // bore over the channel, per side
jt_x_c  = jt_x_k - jt_bore;                   // the floor is a 45 degree cone down to the channel (prints without a flat roof)
jt_x_o  = jt_x_c - wall;                      // socket outside starts here (a full wall past the cone)
jt_sock = jt_bore + wall;                     // socket outside over the channel, per side
// Outer shoulder: the sleeve's outside tapers (45 degrees at the steepest, so it prints) straight to the socket's outside section
// (channel + jt_sock per side) and stays that size to x_s, where the shroud's funnel starts with the same section: no step at either end.
_sk_ex  = max(y_hi - (chan_y0 + chan_h + jt_sock - wall), chan_y0 - jt_sock + wall - y_lo, (cav_h - chan_hz) / 2 - jt_sock + wall);
chan_step  = max(_sk_ex, 0);
chan_step0 = wall * (sqrt(2) - 1);
assert(joint_side == "bottom" || joint_side == "top", "joint_side must be \"bottom\" or \"top\"");
jt_s    = joint_side == "top" ? 1 : -1;       // Z direction of the joint side
jt_y    = chan_cy;                            // screw axis: centred on the channel in Y, outside the joint side
jt_x_b0 = x_s + joint_gap;                    // boss face (insert hole mouth)
jt_x_b1 = jt_x_b0 + joint_hole_depth + joint_boss_floor;
jt_z_lo = cav_cz + jt_s * chan_hz/2;          // boss foot (inside the funnel wall, cut back by the interior)
// Air path edge on the joint side at the boss's closed end (linear funnel, the most it can have moved out there).
// jt_trans_ref pins the boss/screw position to the funnel length it was designed with (106), so shortening trans_len does not move
// the sleeve's joint lug (the sleeve must stay identical). The air-path check (part=airpath) confirms the boss still clears the shorter funnel.
jt_trans_ref = 106;   // [FIXED] trans_len when the sleeve joint was designed
_jt_air = _lerp(jt_z_lo, fan_cz + jt_s * fan_open_d/2, (jt_x_b1 - x_s) / jt_trans_ref);
// Screw axis offset from the card centre: the counterbore clears the sleeve's outside, and the insert keeps joint_boss_floor
// from the air path (on the "bottom" side the funnel flares out under the boss, so that one usually decides).
jt_off  = max(max(chan_hz/2 + jt_sock, pcb_h/2 + pcb_clear_extra + slide_clear + wall) + cb_d/2 + joint_head_clear,
              jt_s * (_jt_air - cav_cz) + insert_od/2 + joint_boss_floor);
jt_z    = cav_cz + jt_s * jt_off;
jt_cham = jt_off - chan_hz/2 + joint_lug_w/2; // 45 degree chamfer run on the boss's +X face (faces down in shroud_print)
assert(jt_x_o > x_pocket + 1, "joint socket runs into the PCB pocket: shorten joint_overlap or lengthen straight_extra");
assert(entry_r == 0, "entry_r > 0 starts the funnel upstream of x_s, inside the sleeve socket: not supported with the split sleeve");
assert(lug_t <= joint_overlap, "sleeve lug longer than the socket");

module socket_bore(x0, x1, d) { prism(x0, x1, chan_cy, cav_cz, chan_w + 2*d, chan_hz + 2*d, chan_r + d); }
module socket_slab(x, d) { slab(x, chan_cy, cav_cz, chan_w + 2*d, chan_hz + 2*d, chan_r + d); }

// The sleeve part: the body from the mouth to x_s, with the socket (that takes the shroud's spigot) and the screw lug
// on its joint_side at the x_s end. "bottom" (z = 0 side) because the motherboard is on the other side when installed; the funnel
// flares out there, so the boss sits far enough out that the insert keeps joint_boss_floor from the air path (jt_off). Clear of
// the fan side (+Y) and the fin/cooler keepouts (Y); the screw goes in along +X from the sleeve end, reached past the sleeve.
// The sleeve has no insert, only a counterbored clearance hole.
module sleeve() {
    difference() {
        union() {
            sleeve_body(x_a);
            socket_bore(jt_x_o, x_s, jt_sock);
            hull() {   // lug
                cyl_x(x_s - lug_t, x_s, jt_y, jt_z, joint_lug_w);
                translate([x_s - lug_t, jt_y - joint_lug_w/2, cav_cz + jt_s * (chan_hz/2 + jt_sock - wall)]) cube([lug_t, joint_lug_w, eps]);
            }
        }
        channel(x_stop - eps, jt_x_c + eps);   // re-open the channel through the socket shell (added solid above)
        socket_bore(jt_x_k, x_s + 1, jt_bore);
        hull() { socket_slab(jt_x_k, jt_bore); socket_slab(jt_x_c, 0); }   // 45 degree cone floor
        hull() { socket_slab(x_s - joint_lead, jt_bore); socket_slab(x_s + eps, jt_bore + joint_lead + eps); }   // lead-in
        head_pocket(x_s - lug_t - 1, x_s - lug_t + cb_depth, x_s + 1, jt_y, jt_z);
    }
}
// Print orientation: the socket end (x_s) on the bed, the mouth up. The lug's x_s face and the socket end are on the bed; the
// card stop step, the PCB pocket floor, the socket's outer step and the lug's -X face all face up; the outer shoulder and the
// socket's cone floor are 45 degrees; the counterbore opens up. No supports.
module sleeve_print() { translate([0, 0, x_s]) rotate([0, 90, 0]) sleeve(); }
// Quick slide-fit check: just the sleeve mouth's outline (cavity + wall), fitcheck_mouth_len tall, printed flat.
module fitcheck_mouth() { linear_extrude(fitcheck_mouth_len) difference() { sleeve_outer2d(); card2d(slide_clear, cav = true); } }

// The shroud's half of the joint, added to its body: the spigot and the insert boss.
// The spigot ends in a 45 degree nose that follows the socket's cone floor, (joint_gap + joint_clear) / sqrt(2) off it, so no dead
// pocket is left at the floor: a square tip left a ~2.6 mm triangle of open groove around the duct there, open to the air path.
jt_x_n = jt_x_c + joint_gap + joint_nose_tip;   // nose end: the nose wall is joint_nose_tip thick (over the passage) there
module joint_spigot() {
    channel_outer(jt_x_t, x_s + 3*eps);   // runs 3*eps into the funnel start, which begins eps past the sleeve face
    hull() { socket_slab(jt_x_n, joint_nose_tip - joint_clear); socket_slab(jt_x_t, wall); }
}
// The boss starts exactly the lug's outline at the sleeve joint and its sides flare out over boss_fair_len into the funnel wall (a
// filleted gusset, no flat cutoff). The flare sits on the lug's foot level, inside the funnel wall.
_jt_foot = cav_cz + jt_s * (chan_hz/2 + jt_sock - wall);
module joint_boss() {
    hull() {
        cyl_x(jt_x_b0, jt_x_b1, jt_y, jt_z, joint_lug_w);
        translate([jt_x_b0, jt_y - joint_lug_w/2, jt_z_lo]) cube([jt_x_b1 + jt_cham - jt_x_b0, joint_lug_w, eps]);
        translate([jt_x_b0, jt_y - joint_lug_w/2, _jt_foot]) cube([eps, joint_lug_w, eps]);
        translate([jt_x_b0 + boss_fair_len, jt_y - joint_lug_w/2 - boss_fair_w, _jt_foot]) cube([jt_x_b1 + jt_cham - jt_x_b0 - boss_fair_len, joint_lug_w + 2*boss_fair_w, eps]);
    }
}
// Its cuts: the spigot passage (joint_clear per side under the channel at the tip, widening back over joint_taper) and the insert hole.
module joint_cuts() {
    socket_bore(jt_x_n - 1, jt_x_t + eps, -joint_clear);
    hull() { socket_slab(jt_x_t, -joint_clear); socket_slab(jt_x_t + joint_taper, 0); }
    cyl_x(jt_x_b0 - 1, jt_x_b0 + joint_hole_depth, jt_y, jt_z, insert_d);
}

// Funnel stations: fraction of the way across at axial fraction t.
function _sm(t) = contr_poly5 ? t*t*t*(10 - 15*t + 6*t*t) : t;
function _lerp(a, b, f) = a + (b - a) * f;
// Rounded channel entry (entry_r > 0): the funnel wall normally leaves the straight channel at x_s with a kink of up to 45 degrees.
// A circular arc of radius entry_r (in the plane of the steepest wall) replaces the kink: tangent to the channel axis at x_s - entry_t,
// tangent to the funnel line at x_s + entry_u1. All walls use the same blend fraction, so no wall gets steeper than the funnel wall.
_ent_D  = max(_sh_out, _sh_in);                   // largest wall shift of the funnel
_ent_th = atan(_ent_D / trans_len);               // angle of the steepest wall
entry_t = entry_r * tan(_ent_th / 2);             // arc start, upstream of x_s (inside the straight channel)
entry_u1 = entry_r * sin(_ent_th) - entry_t;      // arc end, downstream of x_s
_ent_n  = 8;
function _ent_u(i) = -entry_t + i / _ent_n * (entry_t + entry_u1);
function _ent_f(u)  = (entry_r - sqrt(max(0, entry_r*entry_r - (u + entry_t)*(u + entry_t)))) / _ent_D;
assert(entry_r == 0 || !contr_poly5, "entry_r needs the linear funnel (contr_poly5 = false)");
assert(entry_r == 0 || x_s - entry_t >= x_pocket + 1, str("entry_r too large: the arc would start ", x_s - entry_t, " mm, closer than 1 mm to the PCB pocket end at ", x_pocket));
// Outer funnel section (w, h, r) at x (linear funnel from the socket outside section at x_s to fan_size at x_f).
function _fun_at(x) = let(f = _sm((x - x_s) / trans_len))
    [_lerp(chan_w + 2*jt_sock, fan_size, f), _lerp(chan_hz + 2*jt_sock, fan_size, f), _lerp(chan_r + jt_sock, fun_end_r, f),
     _lerp(chan_cy, fan_cy, f), _lerp(cav_cz, fan_cz, f)];
module funnel_hull(w0, h0, r0, w1, h1, r1, cy1, cz1, x1, xs = x_s + eps) {   // rounded rectangle section morphing to another, chained hulls
    if (entry_r > 0) {
        st = concat([for (i = [0 : _ent_n]) [x_s + _ent_u(i), _ent_f(_ent_u(i))]], [[x1, 1]]);
        for (i = [0 : len(st) - 2]) hull() for (j = [i, i + 1]) {
            f = st[j][1];
            slab(st[j][0], _lerp(chan_cy, cy1, f), _lerp(cav_cz, cz1, f), _lerp(w0, w1, f), _lerp(h0, h1, f), _lerp(r0, r1, f));
        }
    } else {
    n = contr_poly5 ? contr_n : 1;
    for (i = [0 : n - 1]) hull() for (j = [i, i + 1]) {
        f = _sm(j / n);
        slab(j == n ? x1 : _lerp(xs, x1, j / n), _lerp(chan_cy, cy1, f), _lerp(cav_cz, cz1, f),
             _lerp(w0, w1, f), _lerp(h0, h1, f), _lerp(r0, r1, f));
    }
    }
}
// Everything the air passes through, from the sleeve end to the fan face (no module). The CFD (cfd/domain.scad) uses this one.
module interior() {
    funnel_hull(chan_w, chan_hz, chan_r, fan_open_d, fan_open_d, fan_open_d/2 - 0.01, fan_cy, fan_cz, x_f);
    fan_opening(x_f - eps, x_end, fan_cy, fan_cz);
}
// The same with the stack module in place: the bellmouth sits at the module's fan face.
module interior_stack() {
    funnel_hull(chan_w, chan_hz, chan_r, fan_open_d, fan_open_d, fan_open_d/2 - 0.01, fan_cy, fan_cz, x_f);
    fan_opening(x_f - 0.5, fan_fx, fan_cy, fan_cz);   // starts inside the funnel end (no coincident faces)
}

// Splitter vanes: each follows the funnel (same fractional position across the opening at both ends)
// and runs straight through the plenum and flange, so it stands on the bed when printed fan-face down.
// They start knife-thin at the inlet channel so they do not choke it, and reach vane_t at the plenum.
module vanes() {
    if (vanes_y > 0 || vanes_z > 0) intersection() {
        union() {
            for (i = [1 : vanes_y]) {
                f = i / (vanes_y + 1);
                ys = chan_y0 + f * chan_w;
                yf = fan_cy - fan_open_d/2 + f * fan_open_d;
                hull() {
                    translate([x_s - eps, ys - eps/2, z_lo - 1]) cube([eps, eps, cav_h + 2]);
                    translate([x_f, yf - vane_t/2, fan_cz - fan_size/2]) cube([eps, vane_t, fan_size]);
                }
                translate([x_f, yf - vane_t/2, fan_cz - fan_size/2]) cube([x_end - x_f, vane_t, fan_size]);
            }
            for (i = [1 : vanes_z]) {
                f = i / (vanes_z + 1);
                zs = cav_cz - chan_hz/2 + f * chan_hz;
                zf = fan_cz - fan_open_d/2 + f * fan_open_d;
                hull() {
                    translate([x_s - eps, y_lo - 1, zs - eps/2]) cube([eps, cav_w + 2, eps]);
                    translate([x_f, fan_cy - fan_size/2, zf - vane_t/2]) cube([eps, fan_size, vane_t]);
                }
                translate([x_f, fan_cy - fan_size/2, zf - vane_t/2]) cube([x_end - x_f, fan_size, vane_t]);
            }
        }
        interior();
    }
}

// ---- snap-on support bar on the shroud (standing tower: gravity along +Y, the bar is on the +Y side) ----
bar_y = fan_cy + shell_d/2 + bar_drop + bar_af/2;        // bar axis (Y); Z is the fan axis height
module hex2d(af, off = 0) { offset(delta = off) rotate(90) circle(d = af / cos(30), $fn = 6); }   // flats face +-a (Y), vertices at +-b (Z)
module support_bar() {
    ext_x(x_end - bar_len, x_end, bar_y, fan_cz) hex2d(bar_af);
    translate([x_end - bar_len, fan_cy, fan_cz - web_t/2]) cube([bar_len, bar_y - fan_cy, web_t]);   // web, cut back to the shell by the interior cuts
}

// ---- joints ----
// Groove ring in a joint face; the loose seal_ring key sits in the two facing grooves.
module groove_ring(x0, x1) { ring_x(x0, x1, fan_cy, fan_cz, rg_i, rg_o); }
// Heat-set insert holes for the fan screws, in the module's fan face (xface); the screws come from the fan side.
module fan_insert_holes(xface) {
    for (p = fan_pts) cyl_x(xface - fan_hole_depth, xface + 1, p[0], p[1], insert_d);
}

module shroud() {
    difference() {
        union() {
            // outer: starts flush with the sleeve's socket outside at x_s (same section), so there is no step at the joint
            funnel_hull(chan_w + 2*jt_sock, chan_hz + 2*jt_sock, chan_r + jt_sock, fan_size, fan_size, fun_end_r, fan_cy, fan_cz, x_f);
            intersection() {   // the round shell, trimmed flush to the fan's square outline: nothing sticks out past the fan's sides
                union() {
                    hull() {   // flares out to the round shell over shell_fair_len, so no ring shows where the funnel meets it
                        slab(x_f - shell_fair_len, _fun_at(x_f - shell_fair_len)[3], _fun_at(x_f - shell_fair_len)[4],
                             _fun_at(x_f - shell_fair_len)[0], _fun_at(x_f - shell_fair_len)[1], _fun_at(x_f - shell_fair_len)[2]);
                        slab(x_f - 3*eps, fan_cy, fan_cz, fan_size, fan_size, fun_end_r);
                        cslab(x_f + shell_cone, fan_cy, fan_cz, shell_d);
                    }
                    cyl_x(x_f + shell_cone, x_end - fl_lug + eps, fan_cy, fan_cz, shell_d);
                }
                prism(x_f - shell_fair_len - 1, x_end, fan_cy, fan_cz, fan_size, fan_size, flange_r);
            }
            prism(x_end - fl_lug, x_end, fan_cy, fan_cz, fan_size, fan_size, flange_r);   // lug plate
            support_bar();
            joint_spigot();
            joint_boss();
        }
        joint_cuts();
        interior_stack();
        if (stack_module == "none") {
            fan_insert_holes(x_end);   // direct mount: heat-set inserts in the flange's fan face, screws from the fan side through its tab
        } else {
            for (p = stack_pts) {
                head_pocket(x_end - lug_t - 1, x_end - lug_t + cb_depth, x_end + 1, p[0], p[1]);
            }
            groove_ring(x_end - tg_h, x_end + eps);
        }
    }
    vanes();
}

// Print orientation: shroud face on the bed, spigot pointing up. The insert boss's open face points up and its +X face
// is a 45 degree chamfer, so it needs no support.
module shroud_print() { translate([0, 0, x_end]) rotate([0, 90, 0]) shroud(); }

// ---- stack module (spacer) ----
// Prints shroud-face down. The bore carries the bellmouth at the fan face.
module spacer() {
    difference() {
        prism(x_end, x_end + spacer_t, fan_cy, fan_cz, fan_size, fan_size, flange_r);
        fan_opening(x_end - 1, x_end + spacer_t, fan_cy, fan_cz);
        groove_ring(x_end - eps, x_end + tg_h);
        fan_insert_holes(x_end + spacer_t);
        for (p = stack_pts) cyl_x(x_end - 1, x_end + stack_hole_depth, p[0], p[1], insert_d);
    }
}
module module_part() { if (stack_module == "spacer") spacer(); }
// Print: shroud face (x_end) on the bed.
module module_print(t) { translate([0, 0, -x_end]) rotate([0, -90, 0]) children(); }

// ---- stator layer (swirl-recovery vanes), modelled where it sits when fitted: x_end .. sl_x ----
// A stator_layer_t plate between the spacer and the shroud's lug. The vanes and the hub stick out of it toward the shroud,
// into the shroud's bore; the tail cone continues from the hub. The plate keys into the shroud with an integral tongue and
// into the spacer with the seal ring. The loose nose puck (stator_nose) fills the spacer's bore between the hub and the fan hub.
sl_x    = x_end + stator_layer_t;   // the layer's spacer-side face: vane leading edges and the hub's fan-side face
x_tail0 = sl_x - stator_chord;      // vane trailing edges and the hub's shroud-side end, where the tail cone starts
function _vd(k) = k == 0 ? 0 : _vd(k - 1) + tan(stator_in_deg * (k - 0.5) / stator_ns) * stator_chord / stator_ns;
// Old flat vanes (stator_vane = "flat", kept for A/B): leading edge at stator_in_deg from axial, trailing edge axial; angle referenced at rt
module stator_vanes_flat() {
    rh = fan_hub_d/2 - 1;
    rt = fan_open_d/2 + 1;
    for (i = [0 : stator_n - 1]) rotate([360 * i / stator_n, 0, 0])
        for (j = [0 : stator_ns - 1]) hull() for (k = [j, j + 1]) {
            al = stator_in_deg * k / stator_ns;
            translate([x_tail0 + stator_chord * k / stator_ns, 0, 0]) rotate([stator_hand * 180 / PI * _vd(k) / rt, 0, 0])
                translate([0, rh, -vane_t / cos(al) / 2]) cube([eps, rt - rh, vane_t / cos(al)]);
        }
}
// Cambered, twisted vanes (stator_vane = "cambered"): one lofted polyhedron per vane. Seen unrolled (x along the axis, y = r * angle) the camber
// line leaves the trailing edge (u = 0) at stator_out_deg from axial and turns linearly with the chord to the local inlet angle at the leading
// edge (u = 1), a circular arc. The inlet angle runs linearly in radius from stator_in_hub to stator_in_tip (a solid-body swirl has tan(angle)
// proportional to r, so the hub wants a shallower angle than the tip). Thickness vane_t, elliptical rounded leading edge over the first
// stator_le_frac of the chord, taper to stator_te_t at the trailing edge over stator_te_frac. stator_nr stations in radius, stator_np per side.
stator_nr = 6; stator_np = 12;
_v_rh = fan_hub_d/2 - 1;      // vane root, buried in the hub
_v_rt = fan_open_d/2 + 1;     // vane tip, trimmed to the bore (minus vane_tip_clear) by stator_layer()
function _v_in(r) = stator_in_hub + (stator_in_tip - stator_in_hub) * (r - _v_rh) / (_v_rt - _v_rh);
function _v_phi(r, u) = stator_out_deg + (_v_in(r) - stator_out_deg) * u;   // camber angle from axial at chord fraction u (0 = trailing edge)
function _v_sum(r, u, n, i = 0) = i >= n ? 0 : tan(_v_phi(r, u * (i + 0.5) / n)) + _v_sum(r, u, n, i + 1);
function _v_y(r, u) = stator_chord * u / 20 * _v_sum(r, u, 20);               // unrolled lateral offset of the camber line (midpoint rule)
function _v_h(u) = u > 1 - stator_le_frac ? max(0.05, vane_t / 2 * sqrt(max(0, 1 - pow((u - (1 - stator_le_frac)) / stator_le_frac, 2))))
                 : u < stator_te_frac ? stator_te_t / 2 + (vane_t - stator_te_t) / 2 * u / stator_te_frac
                 : vane_t / 2;
// point on one side (sg = +1 / -1) of the vane at radius r, chord fraction u: offset normal to the camber line in the unrolled plane
function _v_pt(r, u, sg) = let(ph = _v_phi(r, u), h = _v_h(u),
        x = stator_chord * u - sg * h * sin(ph), y = _v_y(r, u) + sg * h * cos(ph), th = stator_hand * 180 / PI * y / r)
    [x_tail0 + x, r * cos(th), r * sin(th)];
function _v_loop(r) = concat([for (i = [0 : stator_np]) _v_pt(r, i / stator_np, 1)], [for (i = [stator_np - 1 : -1 : 0]) _v_pt(r, i / stator_np, -1)]);
module stator_vane_one() {
    P = 2 * stator_np + 1;
    pts = [for (s = [0 : stator_nr]) each _v_loop(_v_rh + (_v_rt - _v_rh) * s / stator_nr)];
    sides = [for (s = [0 : stator_nr - 1], i = [0 : P - 1], t = [0, 1]) let(i2 = (i + 1) % P)
        t == 0 ? [s * P + i, (s + 1) * P + i, (s + 1) * P + i2] : [s * P + i, (s + 1) * P + i2, s * P + i2]];
    polyhedron(pts, concat(sides, [[for (i = [0 : P - 1]) i], [for (i = [P - 1 : -1 : 0]) stator_nr * P + i]]), convexity = 6);
}
module stator_vanes_cambered() {
    for (i = [0 : stator_n - 1]) rotate([360 * i / stator_n, 0, 0]) stator_vane_one();
}
module stator_vanes() { if (stator_vane == "flat") stator_vanes_flat(); else stator_vanes_cambered(); }
module stator_layer() {
    difference() {
        union() {
            prism(x_end, sl_x, fan_cy, fan_cz, fan_size, fan_size, flange_r);
            ring_x(x_end - (tg_h - 0.1), x_end + eps, fan_cy, fan_cz, rg_i + tg_clear, rg_i + tg_clear + tg_w);   // tongue into the shroud's groove (seal_ring section)
        }
        cyl_x(x_end - tg_h, sl_x + 1, fan_cy, fan_cz, fan_open_d);
        groove_ring(sl_x - tg_h, sl_x + eps);                                             // seal_ring groove, facing the spacer's
        for (p = stack_pts) cyl_x(x_end - 1, sl_x + 1, p[0], p[1], screw_clear_d);        // stack screws pass through
    }
    translate([0, fan_cy, fan_cz]) difference() {
        union() {
            cyl_x(x_tail0, sl_x, 0, 0, fan_hub_d);   // hub over the chord
            // tail cone: from the hub's shroud-side end into the plenum/funnel (-X), half-angle tail_ang, tip flat if tail_len ends before a point
            if (tail_eff > 0) translate([x_tail0 + eps, 0, 0]) rotate([0, -90, 0])
                cylinder(d1 = fan_hub_d, d2 = 2 * tail_r(tail_eff), h = tail_eff + eps);
            intersection() {   // vane tips merge into the plate, and clear the shroud's bore past it by vane_tip_clear
                stator_vanes();
                union() {
                    cyl_x(x_tail0 - 1, x_end + eps, 0, 0, fan_open_d - 2 * vane_tip_clear);
                    cyl_x(x_end, sl_x, 0, 0, fan_open_d + 1);
                }
            }
        }
        cyl_x(sl_x - nose_peg_len - 0.5, sl_x + 1, 0, 0, nose_peg_d + 2 * nose_peg_clear);   // socket for the nose puck's peg
    }
}
// Print: spacer-side face (sl_x) on the bed, vanes, hub and tail cone up. Overhangs: the cambered vanes lean stator_in_hub..stator_in_tip
// degrees from the axis near the plate, so their underside needs removable supports (reachable between the vanes; "flat" vanes: 45 degrees, none),
// the tail cone tail_ang (18) degrees from vertical; the groove and the peg socket open at the bed, the tongue is on top.
module stator_layer_print() { translate([0, 0, sl_x]) rotate([0, 90, 0]) translate([0, -fan_cy, -fan_cz]) stator_layer(); }
// Nose puck: continues the fan hub through the spacer's bore to the stator hub, held by its peg in the hub's socket.
// Model = print: flat fan-side face on the bed, peg up.
module stator_nose() {
    h = spacer_t - nose_gap;
    cylinder(d = fan_hub_d, h = h);
    translate([0, 0, h - eps]) cylinder(d = nose_peg_d, h = nose_peg_len + eps);
}
// ---- hub tail cone: radius, and clearance to the air-path walls it points into ----
function tail_r(L) = max(0, fan_hub_d/2 - L * tan(tail_ang));
function _sdf_rr(dy, dz, w, h, r) = let(q0 = abs(dy) - (w/2 - r), q1 = abs(dz) - (h/2 - r))
    norm([max(q0, 0), max(q1, 0)]) + min(max(q0, q1), 0) - r;      // signed distance to a rounded rectangle (negative inside)
// free distance from the axis to the wall at L mm upstream of the hub's shroud-side end (plenum bore, then the funnel section there)
function tail_wall(L) = let(x = x_tail0 - L, f = (x - x_s) / trans_len)
    x >= x_f ? fan_open_d/2
  : f < 0 ? -1
  : -_sdf_rr(fan_cy - _lerp(chan_cy, fan_cy, f), fan_cz - _lerp(cav_cz, fan_cz, f),
             _lerp(chan_w, fan_open_d, f), _lerp(chan_hz, fan_open_d, f), _lerp(chan_r, fan_open_d/2 - 0.01, f));
tail_gap = 2;   // mm kept between the cone and the walls
function tail_ok(L) = tail_wall(L) - tail_r(L) >= tail_gap;
function tail_fit(L = 0) = L >= 200 || !tail_ok(L + 1) ? L : tail_fit(L + 1);   // longest tail (whole mm) that clears the walls

echo(str("hub tail cone: tail_len ", tail_len, ", longest that fits ", tail_fit(), " mm"));
tail_eff = min(tail_len, tail_fit());   // auto-limited: the shorter funnel leaves less room, so the cone is cut to what fits
if (tail_eff < tail_len) echo(str("NOTE: tail_len ", tail_len, " cut to ", tail_eff, " mm so the cone clears the funnel walls (min gap ", tail_gap, " mm)"));

// Loose key ring between the module and the shroud: a ring that sits in both grooves (TPU recommended, prints flat).
module seal_ring() {
    difference() {
        cylinder(r = rg_i + tg_clear + tg_w, h = 2*tg_h - 0.2);
        translate([0, 0, -1]) cylinder(r = rg_i + tg_clear, h = 2*tg_h + 2);
    }
}

// Interface coupon: the shroud's corner plate (fl_lug thick) with the bore and the real screw holes, to try the inserts and
// screws before the big parts. Direct mount: the fan insert holes, so the fan screws onto it as onto the shroud. Spacer: the
// groove and the stack screw wells. Printed mounting face down, like the shroud.
module fitcheck_interface() {
    rotate([0, 90, 0]) translate([-fl_lug, 0, 0]) difference() {
        prism(0, fl_lug, 0, 0, fan_size, fan_size, flange_r);
        cyl_x(-1, fl_lug + 1, 0, 0, joint_d);
        if (stack_module == "none") {
            translate([0, -fan_cy, -fan_cz]) fan_insert_holes(fl_lug);
        } else {
            for (p = stack_pts) {
                head_pocket(-1, cb_depth, lug_t + 1, p[0] - fan_cy, p[1] - fan_cz);
            }
            ring_x(lug_t - tg_h, lug_t + 1, 0, 0, rg_i, rg_o);
        }
    }
}

// Fan-face coupon: only the first fitcheck_face_t mm of the part the fan screws to (the flare opening, the flare_rim
// clipping and the fan screw holes), to lay on the real fan and compare the bellmouth with its frame flare. Fan face on the bed.
// fitcheck_mark = 1..3 drills that many 2 mm index holes just outside the corner screw holes, to tell the flare variants apart.
module fitcheck_fanface() {
    rotate([0, 90, 0]) translate([-fan_fx, -fan_cy, -fan_cz]) difference() {
        prism(fan_fx - fitcheck_face_t, fan_fx, fan_cy, fan_cz, fan_size, fan_size, flange_r);
        fan_opening(fan_fx - fitcheck_face_t - 1, fan_fx, fan_cy, fan_cz);
        for (p = fan_pts) cyl_x(fan_fx - fitcheck_face_t - 1, fan_fx + 1, p[0], p[1], screw_clear_d);
        for (i = [0 : fitcheck_mark - 1])
            cyl_x(fan_fx - fitcheck_face_t - 1, fan_fx + 1, fan_pts[i][0] + sign(fan_pts[i][0] - fan_cy)*3, fan_pts[i][1] + sign(fan_pts[i][1] - fan_cz)*3, 2);
    }
}

// ---- snap-on supports ----
// 2D profiles are in (a = world Y, b = world Z); a points toward the leg (down in the tower).
_R   = bar_af / sqrt(3);                                  // hex circumradius (vertices at +-b)
_bv  = _R + bar_clear / cos(30);                          // cavity vertex half-width
function clip_a_lip(si)  = -(_bv - (_R - si)) * sqrt(3);  // lip tip position: the cavity's upper slant (da/db 1.73) at the throat half-width R - si
function clip_a_root(si) = clip_a_lip(si) + clip_slit_d;
function clip_a_bot(si)  = clip_a_root(si) + clip_base_t;
_block = support_style == "block";
assert(_block || support_style == "leg", "support_style must be \"block\" or \"leg\"");
// "block": the base reaches the case floor, less the pad (support_len is measured from the bar's bottom flat)
block_base_t = support_len - (clip_a_root(snap_interf) - bar_af/2) - foot_pad_t;
assert(!_block || block_base_t >= 3, str("support_len too short for the clip: base only ", block_base_t, " mm (the snap arms alone hang ",
       clip_a_root(snap_interf) - bar_af/2, " mm below the bar)"));
_w_seat = _bv + 2;
_w_out  = _w_seat + clip_slit + clip_arm_t;
_tn_s   = ((leg_tn_w - leg_neck_w) / 2) / leg_tn_h;       // dovetail flank slope
assert(atan(_tn_s) <= 45, "dovetail flank steeper than 45 degrees");
assert(1.5 * clip_arm_t * snap_interf / (clip_slit_d * clip_slit_d) * 100 <= snap_strain_max,
       str("snap arm strain too high: ", 1.5 * clip_arm_t * snap_interf / (clip_slit_d * clip_slit_d) * 100, " %"));
assert(clip_a_bot(snap_interf) - leg_tn_h - (bar_af/2 + bar_clear) >= 1.5, "dovetail slot too close to the bar seat");
assert(clip_a_bot(snap_interf) - leg_tn_h - clip_a_root(snap_interf) >= 1.5, "dovetail slot too close to the slits");
assert(leg_col_d >= leg_tn_w + 2, "leg column too thin for the tenon");
assert(foot_depth * PI / foot_pitch <= 1, "foot thread flank steeper than 45 degrees");
assert(foot_len - foot_out - foot_travel >= 2 * foot_pitch, "foot stud too short for its travel");
assert(2*_w_out >= leg_tn_w + 6, "clip base too narrow for the dovetail");

module clip2d(si, base_t = clip_base_t, slot = true) {
    a_lip = clip_a_lip(si);
    a_root = clip_a_root(si);
    a_bot = a_root + base_t;
    a_top = a_lip - 1.5;
    b_ai = _w_seat + clip_slit;
    hn = (leg_neck_w + slot_fit) / 2;
    difference() {
        union() {
            translate([0, -_w_seat]) square([a_root + eps, 2*_w_seat]);   // seat
            translate([a_root, -_w_out]) square([base_t, 2*_w_out]);   // base
        }
        hex2d(bar_af, bar_clear);
        // dovetail slot (opens at a_bot, widens away from it)
        if (slot) polygon([[a_bot + 1, hn - _tn_s], [a_bot + 1, -(hn - _tn_s)], [a_bot - leg_tn_h, -(hn + _tn_s * leg_tn_h)], [a_bot - leg_tn_h, hn + _tn_s * leg_tn_h]]);
    }
    for (s = [-1, 1]) scale([1, s]) {
        translate([a_top, b_ai]) square([a_root + eps - a_top, clip_arm_t]);   // arm, free above the slit
        polygon([[a_top, b_ai + eps], [a_top, _R - si], [a_lip, _R - si], [-0.5, _bv - 0.5 / sqrt(3)], [-0.5, b_ai + eps]]);   // lip: underside follows the cavity's upper slant, then flat
    }
}
// "block": the clip is the whole support, its base stands on the case floor through the pad; "leg": the base holds the leg's dovetail.
module support_clip_2d() { if (_block) clip2d(snap_interf, block_base_t, false); else clip2d(snap_interf); }
module support_clip() { linear_extrude(clip_w) support_clip_2d(); }

// Leg (model frame): y = 0 at the clip's bottom face, the column runs to +y (down), the tenon to -y.
leg_body_len = support_len - (clip_a_bot(snap_interf) - bar_af/2) - foot_out - foot_disc_t - foot_pad_t;
sock_d = foot_major + 2 * thread_clear;
assert(_block || leg_body_len >= foot_len + sock_d/2 + 3, str("support_len too short: leg column only ", leg_body_len, " mm (use support_style = \"block\")"));
assert(!_block || (part != "support_leg" && part != "support_foot"), "support_style is \"block\": there is no leg or foot, the clip reaches the floor");
module thread_rod(major, len, clear = 0) {   // eccentric circle twisted along z: the flank slope is depth*pi/pitch <= 1
    linear_extrude(height = len, twist = -360 * len / foot_pitch, slices = ceil(12 * len / foot_pitch), convexity = 6)
        translate([foot_depth / 2, 0]) circle(r = (major - foot_depth) / 2 + clear, $fn = 40);
}
module leg_model() {
    difference() {
        union() {
            rotate([-90, 0, 0]) cylinder(d = leg_col_d, h = leg_body_len);
            translate([-clip_w/2, 0, 0]) rotate([90, 0, 90]) linear_extrude(clip_w)
                polygon([[0.5, -leg_neck_w/2], [0.5, leg_neck_w/2], [-leg_tn_h, leg_tn_w/2], [-leg_tn_h, -leg_tn_w/2]]);
        }
        translate([0, leg_body_len + eps, 0]) rotate([90, 0, 0]) thread_rod(foot_major, foot_len, thread_clear);
        translate([0, leg_body_len - foot_len, 0]) rotate([90, 0, 0]) cylinder(d1 = sock_d, d2 = 0, h = sock_d/2);
    }
}
module support_leg() { translate([0, 0, leg_body_len]) rotate([-90, 0, 0]) leg_model(); }   // column on the bed, tenon up

module foot_model() {   // y = 0 at the disc's top face; the stud goes to -y, the disc to +y
    rotate([-90, 0, 0]) cylinder(d = foot_disc_d, h = foot_disc_t);
    rotate([90, 0, 0]) translate([0, 0, -eps]) thread_rod(foot_major, foot_len + eps);
}
module support_foot() { translate([0, 0, foot_disc_t]) rotate([-90, 0, 0]) foot_model(); }   // disc on the bed

// Tolerance comb: a short bar and one clip per interference value, to find the snap that works on your printer (X vertical).
module snap_comb() {
    linear_extrude(comb_w + 4) hex2d(bar_af);
    for (k = [0 : len(comb_si) - 1]) translate([26 * (k + 1), 0, 0]) difference() {
        linear_extrude(comb_w) clip2d(comb_si[k]);
        for (m = [0 : k]) translate([clip_a_root(comb_si[k]) + 1, (m - k/2) * 2.4, comb_w - 0.8]) cylinder(d = 1.0, h = 1, $fn = 16);   // tally dimples = index + 1
    }
}

// ---- assembly view (never exported to the CFD; no fan) ----
support_xc = x_end - bar_len / 2;
// Both printed duct parts, assembled.
module duct() { shroud(); sleeve(); }
module support_assy() {
    duct();
    if (stator_layer) {
        stator_layer();
        translate([fan_fx - nose_gap, fan_cy, fan_cz]) rotate([0, -90, 0]) stator_nose();
    }
    translate([layer_t, 0, 0]) module_part();
    ext_x(support_xc - clip_w/2, support_xc + clip_w/2, bar_y, fan_cz) support_clip_2d();
    if (!_block) {
        a_bot = clip_a_bot(snap_interf);
        translate([support_xc, bar_y + a_bot, fan_cz]) leg_model();
        translate([support_xc, bar_y + a_bot + leg_body_len + foot_out, fan_cz]) foot_model();
    }
}

// ---- reference solids (only used by the interference check, never exported or shown) ----
module card_solid() {
    translate([pcb_extra - pcb_len, -pcb_t, 0]) cube([pcb_len, pcb_t, pcb_h]);
    translate([pcb_extra - pcb_len, -(pcb_t + back_t), cav_cz - back_w/2]) cube([pcb_len - pcb_extra, back_t, back_w]);   // back cover, ends flush with the block [MEASURED]
    ext_x(-hs_len, 0, 0, 0) polygon([[0, cav_cz - hs_w/2], [hs_t, cav_cz - hs_w_tip/2], [hs_t, cav_cz + hs_w_tip/2], [0, cav_cz + hs_w/2]]);   // the real 14 mm block
}
module fan_solid() {
    prism(fan_fx, fan_fx + fan_stack * fan_t, fan_cy, fan_cz, fan_size, fan_size, 6);
}
function keepouts() = concat([
    [-500, pcb_extra, hs_t + clear_above_fins, 500, -500, 500],      // lower neighbour / case separator on the fin side (from the block's far face) (fins face down), alongside the card only: the fan may extend downward past the card end [ASSUMED, measure the room below]
    [-500, pcb_extra, -500, -(pcb_t + back_t) - clear_behind_pcb, -500, 500],   // CPU cooler / obstacle behind the back cover (up when the fins face down)
    // Installed, the motherboard is on the z = pcb_h side (fan_flush "top": the fan edge is level with it, the funnel grows away from it).
    [-500, pcb_extra + board_front_x, -500, 500, pcb_h + board_below, 500], // motherboard, only up to its front edge (board_front_x past the card end, PLACEHOLDER)
    [-500, 500, -500, 500, -500, -clear_z_above],                    // side panel, on the z = 0 side
    [clear_x_beyond, 500, -500, 500, -500, 500]                      // obstacle beyond the far end
], extra_keepouts);

// Exports empty geometry when nothing collides.
module interference() {
    intersection() { duct(); card_solid(); }
    intersection() { shroud(); sleeve(); }
    for (k = keepouts()) intersection() {
        union() { duct(); fan_solid(); if (module_t > 0) prism(x_end, fan_fx, fan_cy, fan_cz, fan_size, fan_size, flange_r); }
        box(k);
    }
}

// The air path through the sleeve, funnel and spacer, shrunk by airpath_margin per side: from the card stop (x_stop) through the
// inlet channel and the funnel to the fan face. The stator layer is left out (its vanes and hub sit in the air on purpose).
module air_core() {
    m = airpath_margin;
    channel_core = [chan_w - 2*m, chan_hz - 2*m, max(chan_r - m, 0.01)];
    prism(x_stop + m, x_s + eps, chan_cy, cav_cz, channel_core[0], channel_core[1], channel_core[2]);
    funnel_hull(channel_core[0], channel_core[1], channel_core[2], fan_open_d - 2*m, fan_open_d - 2*m, fan_open_d/2 - m - 0.01, fan_cy, fan_cz, x_f);
    cyl_x(x_f - eps, x_end + module_t - m, fan_cy, fan_cz, fan_open_d - 2*m);
}
// Exports empty geometry when the air path is clear (a wall left across the channel, a boss or screw hole breaking in, etc. show up here).
module airpath() {
    assert(airpath_margin > joint_clear, "airpath_margin must be larger than joint_clear, or the intended spigot narrowing reads as a blockage");
    intersection() {
        union() { sleeve(); shroud(); module_part(); }
        difference() { air_core(); vanes(); }   // splitter vanes (vanes_y / vanes_z, default 0) are meant to be there
    }
}

if (part == "sleeve") sleeve();
else if (part == "sleeve_print") sleeve_print();
else if (part == "shroud") shroud();
else if (part == "shroud_print") shroud_print();
else if (part == "spacer") spacer();
else if (part == "spacer_print") module_print(spacer_t) spacer();
else if (part == "stator_vane_one") stator_vane_one();
else if (part == "stator_layer") stator_layer();
else if (part == "stator_layer_print") stator_layer_print();
else if (part == "stator_nose") stator_nose();
else if (part == "seal_ring") seal_ring();
else if (part == "fitcheck_mouth") fitcheck_mouth();
else if (part == "fitcheck_interface") fitcheck_interface();
else if (part == "fitcheck_fanface") fitcheck_fanface();
else if (part == "support_clip") support_clip();
else if (part == "support_leg") support_leg();
else if (part == "support_foot") support_foot();
else if (part == "snap_comb") snap_comb();
else if (part == "support_assy") support_assy();
else if (part == "interference") interference();
else if (part == "airpath") airpath();
else if (part == "none") {}   // used by cfd/domain.scad, which includes this file
else assert(false, str("unknown part: ", part));
