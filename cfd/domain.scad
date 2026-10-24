// CFD-only air volume (NOT a part output; the fan and card never appear in cad/ outputs).
// Build: openscad -D 'part="none"' ... is implied; see scripts/cfd.sh.
include <../cad/shroud.scad>

fair_len = 0;  // mm, [ASSUMED] CFD-only hub fairing: cone from the blocked hub (fan_hub_d, itself [ASSUMED]) pointing downstream (-X) into the plenum/funnel, tip ~0. 0 = none
cfd_ext = 5;   // extension past the fan mounting face (fan-face disc)

// CFD-only stack + stator switches (2026-10-24). cfd_stack moves the fan face from x_end to x_end + cfd_stack, at real CAD positions:
// 12 = spacer only (spacer_t), 15 = spacer + stator layer (spacer_t + stator_layer_t). 0 = the old collapsed domain (flipD_c4 baseline).
// stator_cfd = 1 puts the fitted stator layer's solids (hub over x_tail0..face, 9 vanes, tail cone) in the air, from the CAD's own modules.
cfd_stack   = 0;      // mm
stator_cfd  = 0;      // 0/1
cfd_tail_len  = 60;   // mm, hub tail length (stator_cfd only); radius from tail_r() with tail_ang. 0 = none
cfd_tail_lean = 0;    // deg, [ASSUMED] design variant: tail axis tilted from -X by this angle, toward cfd_tail_dir
cfd_tail_dir  = 0;    // deg about +X from +Y (0 = toward +Y, the fins; 90 = toward +Z)
cfd_vanes = 1;        // 0 = stator hub + tail only (no vanes), to separate the vane effect from the hub extension
cfd_tip_clear = vane_tip_clear;   // mm radial gap between the vane tips and the shroud bore (negative = overlap = closed)
_face = x_end + cfd_stack;

// UNMEASURED leak / bypass sensitivity paths (CFD only, default off; scripts/cfd.sh --leak / --bypass).
leak_a   = 0;  // mm2, [ASSUMED] lumped open window at the sleeve mouth (x ~ 2..10) venting to ambient: 75 = 0.5 mm margin, 150 = 1 mm margin around the card. Upper bound: modelled as an orifice-like tunnel, not a 0.5 mm slot
bypass_h = 0;  // mm, [ASSUMED] open slab over the fin tips under the cover, from the funnel to the exit (the cover may be hollow)
// UNMEASURED exit-diffuser sensitivity (CFD only, default off): planar diffuser behind the fin exit (x = -hs_len), expands in Y only
// from chan_h to diff_h2 over diff_len, same Z width. diff_gap = straight 8 mm section between the fins and the diffuser. Ideal upper bound; no bracket/case modelled.
diff_len = 0;   // mm, [ASSUMED] user may fit at most 50 mm
diff_gap = 0;   // mm
diff_h2  = 16;  // mm, [ASSUMED]
_dx0 = -hs_len - diff_gap;
module diffuser() {
    hull() {
        slab(_dx0 - eps, chan_cy, cav_cz, chan_w, chan_hz, chan_r);
        slab(_dx0 - diff_len, chan_y0 + diff_h2/2, cav_cz, diff_h2, chan_hz, chan_r);
    }
    if (diff_gap > 0) channel(_dx0, -hs_len + 1);
}
_top = chan_cy + chan_h/2;
module leak_tunnel() {   // square tunnel beside the channel (solid wall between) from a stub at the mouth to the outlet plane
    s = sqrt(leak_a);
    translate([-hs_len - 5, _top + 3, cav_cz - s/2]) cube([hs_len + 5 + 2 + s, s, s]);   // (x, y, z): y is the card thickness, z the height
    translate([2, _top - 1, cav_cz - s/2]) cube([s, 3 + s + 1, s]);
}
module bypass_slab() {
    translate([-hs_len - 5, cav_cz - chan_hz/2, _top - 0.01]) cube([hs_len + 5 + x_s, chan_hz, bypass_h + 0.01]);
}

// Fan-face extension: the flare opening at the face (disc of fan_flare_d) clipped to the square the flange keeps (the fan frame
// minus flare_rim on each side), minus the hub. Same clip as fan_opening() in the CAD, so the inlet never reaches past the 120 mm frame
// even when fan_flare_d is wider than fan_size; nothing flows in from outside it.
module fan_ext() {
    difference() {
        intersection() {
            translate([_face - eps, fan_cy, fan_cz]) rotate([0, 90, 0]) cylinder(d = fan_flare_d, h = cfd_ext + eps);
            translate([_face - eps, fan_cy - fan_size/2 + flare_rim, fan_cz - fan_size/2 + flare_rim])
                cube([cfd_ext + eps, fan_size - 2*flare_rim, fan_size - 2*flare_rim]);
        }
        translate([_face - 1, fan_cy, fan_cz]) rotate([0, 90, 0]) cylinder(d = fan_hub_d, h = cfd_ext + 2);
    }
}

// Stator solids, same modules/numbers as stator_layer() in the CAD (hub, vane chord, tip clearance), plus the optional leaning tail.
module stator_solids() {
    translate([0, fan_cy, fan_cz]) {
        cyl_x(x_tail0, _face + cfd_ext + 1, 0, 0, fan_hub_d);   // hub: stator hub + nose puck + fan hub, one blocked cylinder
        if (cfd_vanes > 0) intersection() {
            stator_vanes();
            union() {
                cyl_x(x_tail0 - 1, x_end + eps, 0, 0, fan_open_d - 2 * cfd_tip_clear);
                cyl_x(x_end, sl_x, 0, 0, fan_open_d + 1);
            }
        }
        if (cfd_tail_len > 0) {
            r2 = tail_r(cfd_tail_len);
            rotate([cfd_tail_dir, 0, 0]) hull() {
                translate([x_tail0 + eps, 0, 0]) rotate([0, -90, 0]) cylinder(d = fan_hub_d, h = eps);
                translate([x_tail0 - cfd_tail_len * cos(cfd_tail_lean), cfd_tail_len * sin(cfd_tail_lean), 0])
                    rotate([0, -90, 0]) cylinder(d = max(2 * r2, 0.2), h = eps);
            }
        }
    }
}

module fluid() {
    difference() {
        union() {
            channel(-hs_len - 5 - (diff_len > 0 ? diff_gap + diff_len : 0), x_s + eps);
            if (cfd_stack > 0) { funnel_hull(chan_w, chan_hz, chan_r, fan_open_d, fan_open_d, fan_open_d/2 - 0.01, fan_cy, fan_cz, x_f); fan_opening(x_f - eps, _face, fan_cy, fan_cz); }
            else interior();
            fan_ext();
            if (diff_len > 0) diffuser();
            if (leak_a > 0) leak_tunnel();
            if (bypass_h > 0) bypass_slab();
        }
        vanes();
        translate([_face - 1, fan_cy, fan_cz]) rotate([0, 90, 0]) cylinder(d = fan_hub_d, h = cfd_ext + 2);
        if (stator_cfd > 0) stator_solids();
        if (fair_len > 0) translate([_face - 1 + eps, fan_cy, fan_cz]) rotate([0, -90, 0]) cylinder(d1 = fan_hub_d, d2 = 0.2, h = fair_len);
    }
}

// Porous (Darcy-Forchheimer) coefficients, SI. The passages are rectangular ducts (gap g x height H), laminar.
// Darcy: dp/L = 2 * fRe_F * mu * u_gap / Dh^2 (fRe_F = Fanning f x Re_Dh), fRe_F(aspect) from Shah & London:
// 24 (1 - 1.3553 a + 1.9467 a^2 - 1.7012 a^3 + 0.9564 a^4 - 0.2537 a^5). a = 0.61 gives ~15.0 (a = 0.5 gives 15.5).
// Forchheimer: fin_k velocity heads of the gap velocity cover entry + developing flow (Hagenbach K(inf)).
// OpenFOAM's U is the superficial velocity, u_gap = U / phi.
fin_g   = fin_pitch - fin_t;
fin_phi = fin_g / fin_pitch;
fin_a   = min(fin_g, chan_h) / max(fin_g, chan_h);
fin_fre = 24 * (1 - 1.3553*fin_a + 1.9467*pow(fin_a,2) - 1.7012*pow(fin_a,3) + 0.9564*pow(fin_a,4) - 0.2537*pow(fin_a,5));
fin_dh  = 2 * fin_g * chan_h / (fin_g + chan_h);          // mm
d_si = 2 * fin_fre / (pow(fin_dh/1000, 2) * fin_phi);     // 1/m^2 (x nu inside OpenFOAM); plates (fRe 24, Dh 2g) give 12/(phi g^2)
f_si = fin_k / ((hs_len/1000) * fin_phi * fin_phi);       // 1/m

_ymin = fan_cy - fan_size/2; _ymax = max(chan_y0 + chan_h, fan_cy + fan_size/2);
_zmin = min(fan_cz - fan_size/2, cav_cz - chan_hz/2); _zmax = max(fan_cz + fan_size/2, cav_cz + chan_hz/2);
echo(str("CFD ymin=", _ymin - 2, " ymax=", _ymax + 2, " zmin=", _zmin - 2, " zmax=", _zmax + 2, " xmin=", -hs_len - 5, " diff_ext=", diff_len > 0 ? diff_gap + diff_len : 0, " diff_len=", diff_len, " xmax=", _face + cfd_ext, " xend=", _face, " xs=", x_s, " xf=", x_f,
    " fan_cy=", fan_cy, " fan_cz=", fan_cz, " chan_cy=", chan_cy, " chan_cz=", cav_cz, " chan_hz=", chan_hz, " chan_h=", chan_h,
    " hs_len=", hs_len, " fan_stack=", fan_stack, " fan_d=", fan_flare_d, " hub_d=", fan_hub_d,
    " loc_x=", -hs_len/2, " loc_y=", chan_cy, " loc_z=", cav_cz,
    " d=", d_si, " f=", f_si, " fin_pitch=", fin_pitch, " fin_t=", fin_t, " fin_k=", fin_k, " leak_a=", leak_a, " bypass_h=", bypass_h, " fin_dh=", fin_dh, " fin_fre=", fin_fre));

fluid();
