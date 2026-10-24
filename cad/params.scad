// SPDX-License-Identifier: CERN-OHL-P-2.0
// Copyright 2026 Arthurdw. See LICENSE and NOTICE.
// Tesla P4 shroud - parameters.
//
// Every value carries a status tag:
//   [PUBLISHED]  from a datasheet / vendor spec
//   [STANDARD]   industry-standard value (e.g. fan hole pitch), still verify on your part
//   [ASSUMED]    placeholder chosen from photos or typical values - NOT measured, edit me
//   [REQUIRED]   must be measured on your hardware before a release print (see MEASUREMENTS.md)
//
// Coordinate system ("card coordinates", mm):
//   X: along the flow axis. x = 0 is the far end of the heatsink fin block.
//      The card extends toward -X. The fan sits toward +X.
//   Y: card thickness. y = 0 is the PCB face that carries the heatsink; fins go to +Y.
//      The PCB back face is at y = -pcb_t.
//   Z: card height. z = 0 is the card's bottom (edge-connector) edge, z = pcb_h the top edge.
//      In your case (motherboard flat) +Z points away from the motherboard.

// ---- what to build (override from the CLI with -D 'part="..."') ----
// sleeve | sleeve_print | shroud | shroud_print | spacer | spacer_print | stator_layer | stator_layer_print | stator_nose | seal_ring |
// fitcheck_mouth | fitcheck_interface | fitcheck_fanface | support_clip | support_leg | support_foot | snap_comb | support_assy | interference | airpath
// "sleeve" (the mouthpiece) slides over the card, x = -grip .. x_s, and carries the socket and the screw lug; "shroud" is the funnel
// (with the spigot and the insert boss) + fan flange, x = x_s - joint_overlap .. x_end. One M3 joins them (see the joint below).
part = "shroud";

// A release build refuses to run while placeholders are still in use.
params_confirmed = false;   // set true only after every [REQUIRED]/[ASSUMED] value is measured
release          = false;   // exported by scripts/export.sh --release

$fn = 64;                   // fixed, so output is deterministic

// ---- card ----
pcb_len = 167.64;  // [PUBLISHED] NVIDIA product brief
// Card END cross-section, measured by the user (y = 0 is the PCB face that carries the heatsink, +Y toward the fin tips):
//   back cover / backplate: y from -(pcb_t + back_t) to -pcb_t;  PCB: y from -pcb_t to 0;  cooling block: y from 0 to hs_t.
pcb_h   = 56;      // [MEASURED] PCB width (Z)
pcb_t   = 1;       // [MEASURED] PCB thickness
back_t  = 2;       // [MEASURED] back cover / backplate thickness (Y)
back_w  = 54;      // [MEASURED] back cover width (Z)
hs_t    = 14;      // [MEASURED] cooling block thickness (Y), the whole heatsink body: the black cover over the 8 mm fins
hs_w    = 54;      // [MEASURED] cooling block width (Z) at the PCB side
hs_w_tip = 53;     // [MEASURED] cooling block width (Z) at the far (fin-tip) face: the block tapers from hs_w to this (rounded corners not modelled)
// Back cover and cooling block are centred on the PCB in Z: [MEASURED] (user visual check). pcb_h/2 is the card centre.
hs_h    = 8;       // [MEASURED] fin height above the PCB face (user, side photo IMG_6394); the air channel is this tall. The block (hs_t) is taller than the fins.
hs_len  = 170;    // [MEASURED, approx] cooling element length (user: about 170 mm)
pcb_extra = 1;     // [MEASURED] the bare PCB extends this far beyond the block end face (user); the back cover ends flush with the block [MEASURED]
// Fins are assumed to run along X (airflow along the card length).   [ASSUMED]

// ---- fit / print tolerances ----
// The sleeve cavity is stepped: the union of the back cover, the PCB and the cooling block outlines, each grown by slide_clear on every side.
// (This replaces the old single 19 x 57 rectangle entry_w / entry_h / back_clear.)
back_clear_extra = 0.25; // [MEASURED, fit test 2026-10-24] extra cavity room above the back cover (-Y, up when installed), on top of slide_clear. The third fitcheck_mouth (v3) was 0.5 mm too tight there; v6 keeps the v4 total of 0.9 (0.65 + 0.25)
pcb_clear_extra = 0.25; // [MEASURED, fit test 2026-10-24] extra room at each Z end of the PCB slot (the PCB edges that stick out past the back cover and block), on top of slide_clear; v2 found it 1 mm too tight per side, v3 (at 1) slightly too loose, v5 (1.4 total) far too loose; v6 is back to the v4 total of 0.9
pcb_slot_extra_y = 0.25; // [MEASURED, fit test 2026-10-24] extra room on each face of the PCB slot (Y, card thickness), on top of slide_clear: the second fitcheck_mouth still did not slide; v5 (slot 3.8 wide) far too loose, so v6 is back to the v4 slot of 2.8 (0.9 per face). pcb_t is 1 [MEASURED], but PCIe add-in boards are 1.57 mm at the edge fingers [STANDARD], so re-measure the board edge
fitcheck_mouth_len = 3; // fitcheck_mouth: height of the mouth-outline ring (was 5; 3 = 15 layers at 0.2, still stiff enough to feel the slide, less time and filament per iteration)
slide_clear = 0.65; // [MEASURED, fit test 2026-10-24] slide-fit clearance per side between the card and the sleeve cavity. Started at 0.4 [ASSUMED]; v4 (0.4) slid but was too hard to push on, v5 (0.9) had far too much play, so v6 splits the difference. Raise if it binds, lower if it rattles.

// ---- walls ----
wall       = 2.4;  // 6 perimeters at 0.4 mm
sleeve_r   = 4;    // corner radius of the sleeve mouth's outside (a plain rounded rectangle around the cavity, wall past its bounding box). Checked in 2D: up to 4 the wall stays >= 2.4 everywhere; 4.5 gives 2.398, 5 gives 2.33, 5.5 gives 2.21
r_in       = 3;    // fan-end corner radius (outer = r_in + rim)
// Inlet channel between the card end and the funnel: same section as the fin block, so the air can only go through the fins.
hs_base    = hs_t - hs_h; // [MEASURED, derived] solid base of the cooling block next to the PCB (6 mm); the 8 mm of fins sit on top of it, y = hs_base .. hs_t
chan_h     = hs_h; // inner height (Y) = fin height. The channel sits at the far (fin-tip) face of the block, y = hs_base .. hs_t, NOT against the PCB [MEASURED, user]
chan_hz    = 51.6; // [MEASURED, derived from the visible gap at both short sides] channel width (Z), centred on the card; absolute, no longer tied to hs_w
chan_r     = 0.5;  // channel corner radius
// Fin geometry: only used by the CFD (scripts/cfd.sh), which models the fin block as a porous zone.
fin_n     = 10;    // [MEASURED, fin count] user counted 10 fins across the block end
fin_pitch = chan_hz / fin_n;  // [MEASURED, fin count] user counted 10 fins; pitch = finned width / 10 (finned width taken as the channel width 51.6, pitch 5.16 mm)
fin_t     = 0.3;   // [ASSUMED] fin thickness (typical copper fin)
fin_k     = 1.0;   // [ASSUMED] fin-block entry + developing-flow loss in gap-velocity heads: Hagenbach K(inf) ~0.8 (Shah & London, aspect ~0.6) + ~0.2 entry contraction
fitcheck_mark   = 0;    // fitcheck_fanface: 0..3 index holes at the corners (set by scripts/export.sh for the _d127 / _d132 / _d137 variants)
fitcheck_face_t = 1;    // fitcheck_fanface: thickness of the fan-contact layer (the first fitcheck_face_t mm of the bellmouth)

stop_gap   = 0.3;  // free travel between the block end face and the channel's step face (the stop)
pcb_end_clear = 1.0; // [ASSUMED] the PCB pocket goes this much deeper than the PCB end, so the block (not the PCB edge) takes the stop and an error in pcb_extra does not bind

// ---- shroud layout along X ----
grip           = 10;   // sleeve slides this far over the block end (it starts at x = -grip); the PCB stub sits in its own pocket past the stop
straight_extra = 21;   // inlet channel past the PCB end, before the funnel starts (holds the 45 deg outer shoulder, ~9.2 mm). 21 with pcb_extra = 1 keeps x_s = 22, the value the CFD was run at (was 12 with the old pcb_extra = 10 placeholder)
// Length budget and overhang allowance (new).
stack_max_len   = 160;  // [MEASURED 180 mm card end to the next obstacle (the 3 front 120 mm intake fans), user 2026-10-24; minus 20 mm [ASSUMED rule of thumb: an axial fan inlet starves when the intake is closer than ~15-20 mm to a wall or another fan]] was 148 ("~150 from the brief"). shroud + module + fan must end by here (X from the card end); shroud.scad echoes the total and asserts it
max_overhang_deg = 52;  // [ASSUMED] steepest funnel wall allowed, degrees from the axis, printed fan face down. Over 45 the inside face of the narrowing wall overhangs. PETG/ASA generally print ~50 deg overhangs without supports, rougher on the inside of the duct: slow, max cooling. Not measured on this printer
trans_len      = 89;   // [CHANGED, DERIVED from the length budget] was 106. Stack = x_s 22 + trans_len + plenum_len 4 + flange_t 8 + spacer_t 12 + 25 mm fan <= stack_max_len 160, so trans_len = 160-22-12-12-25 = 89 (exactly the limit, 0 mm slack). Direct mount (stack_module "none") then totals 148. The steepest wall comes out at 47.7 deg from the axis (shroud.scad echoes it; under the atan(105.1/89) = 49.8 deg bound because the 105.1 mm max shift is the outer-shell value): steeper than 45, needs the overhang allowance max_overhang_deg (see above). Old note: 106 was the smallest round value passing the 45 deg assert. Per-side shrink must stay <= trans_len

contr_poly5     = false;    // funnel wall profile: false = straight-line walls, true = 5th-order smoothstep (zero slope at both ends; steepest point 1.875x the average, so the 45 deg limit needs trans_len >= 1.875 x the wall shift)
entry_r        = 0;         // rounded channel entry: radius (mm) of the arc that blends the funnel wall into the straight inlet channel (the 45 deg kink at x_s). 0 = sharp (default). The arc starts upstream of the funnel inside the straight channel and is never steeper than the funnel wall, so it prints; bounded by the stop face (assert in shroud.scad)
contr_n        = 12;        // stations of the poly5 profile (geometry resolution only)

// ---- sleeve / shroud joint at x_s (flipped spigot and socket, one M3 x screw_len along +X) ----
// Air flows toward -X (fan -> funnel -> sleeve), so the upstream part goes inside: the funnel ends at x_s in a spigot (channel
// outer section, wall thick) that slides joint_overlap mm toward -X into a socket on the sleeve (bore = spigot + joint_clear per
// side, wall around it); past the socket floor the sleeve's inlet channel goes on at its measured section. The spigot's passage is
// joint_clear per side smaller than the channel at its tip, so even a misaligned joint only shows the flow a downstream-facing step.
// One M3 runs along +X, outside the air path: head in a counterbored lug on the sleeve's outside at the socket mouth (+Z, the
// side-panel side), through it into a heat-set insert in a boss on the funnel's outside. The insert stays in the funnel; the
// sleeve (on the hot heatsink, the part you reprint) only has a plain hole. The lug uses lug_t / cb_d / cb_depth (2.3 mm floor).
joint_overlap    = 9;    // [ASSUMED] design choice: spigot length inside the socket
joint_clear      = 0.2;  // [ASSUMED] slip clearance per side, spigot to socket bore (and the spigot passage's narrowing at its tip); raise if it does not slide, lower if it rattles
joint_gap        = 0.1;  // [ASSUMED] design choice: nominal gap lug-to-boss and spigot tip-to-socket floor (the screw pulls the lug onto the boss, the spigot never bottoms)
joint_lug_w      = 10;   // [ASSUMED] design choice: lug and boss width (Y), also their outer diameter around the screw axis
joint_boss_floor = 1.2;  // [ASSUMED] design choice: boss material past the closed end of the insert hole, and the least material between the insert and the air path
boss_fair_w      = 3;    // [ASSUMED] design choice: per side, how much wider than joint_lug_w the insert boss flares into the funnel wall (its sides fillet into the wall instead of ending flat)
boss_fair_len    = 12;   // [ASSUMED] design choice: length along X over which that flare grows from the lug width (at the sleeve joint) to full
shell_fair_len   = 24;   // [ASSUMED] design choice: length along X, upstream of the funnel end, over which the funnel's outer faces flare out to the round shell, so no ring shows where they meet
joint_taper      = 10;   // [ASSUMED] design choice: the spigot passage widens from joint_clear per side under the channel (tip) back to the plain section over this length
joint_head_clear = 0.5;  // [ASSUMED] design choice: the counterbore's edge sits this far outside the sleeve's +Z face, so the screw head and the key pass the sleeve along X
joint_side       = "bottom";   // Z side of the joint's lug and boss. "bottom" (default): the z = 0 side, where the funnel grows, away from the motherboard (user, installed). "top": the motherboard side, collides with the board
joint_lead       = 0.8;  // [ASSUMED] design choice: 45 degree lead-in chamfer at the socket mouth (also keeps the socket's end face off the funnel's 45 degree outside)
joint_nose_tip   = 0.6;  // [ASSUMED] design choice: the spigot's 45 degree nose (it fills the socket's cone floor) ends in a flat this wide instead of a knife edge

// ---- fan ----
fan_size   = 120;  // 120 = Noctua NF-F12 industrialPPC-3000 PWM (hole pitch 105); try 92 / 80 / 60
fan_t      = 25;   // [PUBLISHED] NF-F12 thickness (120 x 120 x 25 mm)
fan_stack  = 1;    // 1 or 2 fans in series (interference envelope only; a second fan is a stack module, see README)
fan_clear  = 0.5;  // pocket clearance per side
fan_open_d = fan_size - 8;  // [ASSUMED] airflow opening diameter in the flange (about the blade circle); verify with fitcheck_fanface
// The fan frame's opening flares outward past the blades. The flange opening copies that flare: it is
// fan_flare_d wide at the fan face, runs in on a straight 45 degree cone and then curves into the bore
// with a tangent circular arc (a bellmouth), axial at fan_open_d, flare_depth deep from the fan face.
fan_flare_d = fan_open_d + 20; // [MEASURED] user-confirmed with the d132 fitcheck coupon (fitcheck_fanface _d132). Earlier history: flare diameter at the fan's frame face (user estimate, 2nd round: ~1 cm wider than the first guess of blade circle + 10, so blade circle + 20 = ~132). Measure it with fitcheck_fanface (README)
flare_depth = 12;  // [ASSUMED] design choice: depth of the bellmouth from the fan face. Must lie between (fan_flare_d - fan_open_d)/2 (a pure 45 degree chamfer) and 2.414x that (a pure arc, the old shape). 12 keeps the bore at the module / shroud joint near fan_open_d, so the groove ring fits
fan_hub_d = 40;    // [MEASURED] user 2026-10-24: fan hub diameter; blocked in the CFD fan-face extension, and the diameter of the stator layer's hub and nose puck
flare_rim  = 1.2;  // flange material kept at the middle of each side where the flare would cut through, so the plate stays one piece
insert_d   = 4.0;  // [ASSUMED] hole for an M3 heat-set insert (M3 confirmed by user; insert OD not given yet: 4.0 mm is the typical maker hole for a ~4.6 mm OD M3 insert; check the datasheet)
insert_len = 4.0;  // [MEASURED] insert length (user: exactly 4 mm). Thread engagement of every screw joint is min(reach, insert_len), asserted >= 3 mm in shroud.scad
insert_od  = 4.6;  // [ASSUMED] knurl OD of the insert (typical M3); only used for the wall checks
flange_r  = 6;     // outer corner radius of the fan end (about the fan's own corner radius)
fun_end_r  = 56;   // [ASSUMED] design choice: corner radius of the funnel's outer end (the 120 square rounded off so it sits inside the round shell and the diagonal wall slope stays <= 45 degrees)
flange_t   = 8;    // [CHANGED, REQUIRED] was 11. In the direct mount the fan inserts sit in this flange (corner plate = the whole flange, see shroud.scad fl_lug), so it must be >= fan_hole_depth + 1.5 = 8 mm. Was kept at 11 for the CFD air path; the bore length plenum_len + flange_t is 12 mm (was 21)   // length of the round shell past the plenum up to the mounting face (the corner plate is lug_t of it); kept at 11 so the CFD air path is unchanged
plenum_len = 4;    // [CHANGED, DERIVED] was 10. plenum_len + flange_t = 12 = flare_depth (assert: flare_depth <= flange_t + plenum_len), the least that holds the bellmouth.   // straight settling section between the funnel and the fan flange
// Splitter vanes: thin plates that follow the funnel and spread the flow evenly over the card face.
vanes_y    = 0;    // number of vanes across Y (the long direction of the spread); 0 = none. Default 0 since the CFD optimization (docs/cfd-notes.md): at the same mesh the vaned funnel passed 3.51 CFM and the unvaned one 4.18 CFM (+19 %), with a more even fin entry. [ASSUMED] result of a comparative steady RANS model; the vanes' stiffness/print role is not modelled
vanes_z    = 0;    // number of vanes across Z; 0 = none (see vanes_y; 3 and 2 were the old defaults)
vane_t     = 1.2;  // vane thickness (3 perimeters)
// offset of the fan centre relative to the cavity centre. The default lifts the fan so a
// 120 mm fan clears the motherboard; verify against board_below.
fan_off_y = 0;
fan_flush_y = "lo"; // Orientation (standing tower, ATX, fins DOWN): the fin-tip side (+Y) faces down toward the lower slots / case separator, the PCB back (-Y) faces up toward the CPU cooler. "lo": fan edge level with the PCB-back face, so the fan grows only toward +Y (downward); "hi": fan edge level with the fin-side face, grows toward -Y (up, toward the CPU cooler); "none" uses fan_off_y
fan_flush = "top"; // Z side of the fan. "top" (default, the installed orientation): fan edge level with the sleeve edge on the far side (z = card top edge), so the fan grows toward -Z, away from the motherboard (installed, the motherboard is on the z = pcb_h side; user); the mouth/connector ends up on the RIGHT in the slicer print view. "bottom": fan edge level with the sleeve edge at z=0, duct goes the other way (the old orientation, which the user says would hit the motherboard); "none": use fan_off_z
fan_off_z = 25;    // [ASSUMED]

// ---- short-screw stack: fan -> module -> shroud flange (see README) ----
// Every joint is one M3 x screw_len countersunk screw into a heat-set insert; no nuts anywhere.
// Fan -> module: from the fan side through the fan's corner tab (105 mm pattern), see "Fan -> spacer" below.
// Module -> shroud: M3 x screw_len from behind the flange lug into heat-set inserts in the module (stack_pitch pattern).
// Direct mount (stack_module "none", the option): the fan joint goes straight into heat-set inserts in the shroud flange
// (the flange takes the spacer's role).
stack_module = "spacer";  // [CHANGED] was "none". module between fan and flange: "spacer" (default: the fan flange is a separate print, funnel shortened to keep the stack in stack_max_len) | "none" (direct mount, funnel can be longer, see trans_len). The stator is the optional stator_layer below, not a module
screw_len     = 10;   // [MEASURED] user: M3 x 10 (length under the head); the one size used at every joint (user prefers one size)
screw_lengths = [8, 10, 12, 16]; // [MEASURED] M3 lengths the user has; shroud.scad echoes the shortest that works at each joint
screw_clear_d = 3.4;  // [STANDARD] M3 clearance hole
screw_head    = "countersunk"; // [MEASURED] user: M3 countersunk (flat top, 90 degree cone). "countersunk" cuts a cone seat in the floor of every head pocket; "flat" keeps flat-underside heads (socket / pan)
cs_head_d     = 6.0;  // [STANDARD] M3 countersunk head diameter (DIN 7991 / ISO 10642 nominal); MEASURE your heads
cs_angle      = 90;   // [STANDARD] countersunk included angle
cs_clear      = 0.3;  // [ASSUMED] extra diameter on the cone seat so the head sits on the cone, not on the rim (the head then sits cs_clear/2 / tan(cs_angle/2) below the pocket floor)
cb_d          = 6.5;  // [ASSUMED] counterbore diameter: the pocket above the cone seat; clears the countersunk head (6.0) and a driver, and a socket head (5.5) / pan head (~6) with screw_head "flat"
cb_depth      = 3.2;  // [ASSUMED] counterbore depth: the head's flat top sits at the pocket floor (recessed), the driver reaches it; socket head 3.0, pan head ~2.4 with "flat"
fan_tab_t     = 4;    // [ASSUMED] fan corner tab thickness (the flange on the face that touches the spacer), about 4 mm: MEASURE it
// Fan -> spacer: M3 from the fan side, head inside the fan's corner (on the tab), through the tab into a heat-set insert in the
// spacer's fan face, so the fan comes off without taking the stack apart. Needs room for the head and a 2 mm hex key between the
// fan's two corner flanges (open corner): CHECK on your fan.
fan_gasket    = false; // true: foam tape (seal_t) sits between fan and module; it takes seal_t out of the screw budget
seal_t        = 0.8;  // [ASSUMED] foam gasket tape thickness at the fan / module joint (the module / shroud joint uses the seal_ring key instead)
lug_t         = 5.5;  // flange lug (corner plate) thickness: counterbore + floor; ~5 mm as asked
stack_r       = 68;   // [ASSUMED] design choice: radius of the module -> shroud screws (outside the round shell and the bellmouth at the insert depth, inside the 120 mm plate); bounded by asserts in shroud.scad
stack_ang     = 10;   // [ASSUMED] design choice: each stack screw sits this many degrees off the corner diagonal (pinwheel), so it clears the fan screw at the 105 mm corner
spacer_t      = 12;   // plain spacer thickness (user asked ~10; 12 because the wider flare is still wide 8.5 mm deep, and the groove ring needs the bore narrow enough by then: assert in shroud.scad)
tg_w          = 1.0;  // tongue width (tongue-and-groove lip at the module / shroud joint)
tg_h          = 1.5;  // tongue height
tg_clear      = 0.2;  // groove clearance per side
tg_wall       = 1.4;  // tongue starts this far outside the joint bore
fan_blades    = 7;    // [ASSUMED] fan blade count (NF-F12: count them); the stator vane count must share no factor with it
// Optional stator layer (see README): a thin plate between the spacer and the shroud flange, its vanes and hub stick out of it
// toward the shroud (into the shroud's bore); a loose nose puck fills the spacer's bore in front of the hub. Moves the fan out by stator_layer_t.
stator_layer   = false; // true: the stator layer is fitted (moves the fan face, used by the assembly and the interference check)
stator_layer_t = 3;     // [ASSUMED] design choice: plate thickness; it comes out of the spacer-screw engagement (assert in shroud.scad: >= 4 mm left)
vane_tip_clear = 0.4;   // [ASSUMED] radial gap between the vane tips and the shroud's bore past the plate (the vanes slide into the shroud)
nose_peg_d     = 8;     // [ASSUMED] nose puck peg diameter
nose_peg_len   = 4;     // [ASSUMED] nose puck peg length (the socket in the hub is 0.5 mm deeper)
nose_peg_clear = 0.1;   // [ASSUMED] per side, peg to socket: a press fit on a typical FDM printer (holes print small); raise if it does not go in
fan_blade_to_face = 0; // [REQUIRED] distance from the fan's outlet face to its blades' trailing edge (0 = assume blades at the face, conservative); with the spacer's thickness it sets the gap to the stator's leading edge
stator_gap    = 10;   // leading edge at least this far from the fan blades (assert: spacer_t + fan_blade_to_face >= stator_gap)
stator_vane   = "cambered"; // "cambered": twisted, circular-arc cambered vanes with a rounded leading edge (needs removable supports, see README); "flat": the old straight-slab vanes (stator_in_deg, 45 degrees = the support-free print limit), kept for A/B
stator_chord  = 14;   // vane chord (axial length): stator_layer_t inside the plate, the rest sticks into the shroud's bore (at most plenum_len + flange_t - 1 past the plate)
stator_n      = 9;    // vane count (must share no factor with fan_blades)
stator_in_deg = 45;   // "flat" vanes only: inlet angle from axial; 45 is the print limit (vanes end axial)
stator_in_hub = 60;   // "cambered": inlet angle from axial at the hub (the swirl is steepest at the tip: tan(angle) grows with radius)
stator_in_tip = 75;   // "cambered": inlet angle from axial at the tip
stator_out_deg = 0;   // "cambered": outlet angle from axial (0 = straight out along the duct)
stator_le_frac = 0.12; // "cambered": rounded (elliptical) leading edge over this fraction of the chord
stator_te_frac = 0.35; // "cambered": the trailing edge tapers over this fraction of the chord
stator_te_t    = 0.6;  // "cambered": trailing-edge thickness
stator_hand   = 1;    // [REQUIRED] +1 / -1: swirl direction of your fan; flip if the vanes lean the wrong way (check the rotation arrow on the frame)
tail_len      = 60;   // [ASSUMED gain, see docs/cfd-notes.md] hub tail cone from the stator hub's downstream (shroud) end, pointing into the plenum/funnel; 0 = off. Starts at fan_hub_d; the assert in shroud.scad stops it if it would touch the funnel walls, and says the longest length that fits. The CFD gain depends on fan_hub_d (40 is [ASSUMED]): measure the hub
tail_ang      = 18;   // tail cone half-angle in degrees (prints at 18 degrees from vertical in stator_layer_print)
nose_gap      = 0;    // [ASSUMED] the nose puck's flat face stops this far short of the fan face (puck height spacer_t - nose_gap). 0 = flush with the fan's outlet face, continuing the fan hub with no step (assumes the hub on the fan's outlet/strut side is the stationary motor mount and sits no prouder than the frame face: check)

// ---- snap-on supports against sag (standing tower, gravity along +Y; see README) ----
support_len   = 80;   // [REQUIRED] bar bottom face to the case separator (the PSU shroud below). Placeholder; measure and reprint support_leg
bar_af        = 10;   // hex bar across flats (non-round so the joint is not a hinge)
bar_len       = 36;   // bar length along X, ending at the flange (clip slides on it)
web_t         = 2.4;  // web joining the bar to the shroud
clip_w        = 14;   // clip width along the bar
bar_clear     = 0.2;  // clip cavity clearance around the bar
snap_interf   = 1.6;  // snap lip overlap measured against the cavity corner; 1.0-2.2 are tested by snap_comb. The snap only stops lift-off, gravity seats the bar
clip_arm_t    = 2.4;  // snap arm thickness
clip_slit     = 1.0;  // gap between the seat and each arm
clip_slit_d   = 15;   // arm free length below the lip (long arms keep the strain low: 1.5 t d / L^2)
clip_base_t   = 7;    // clip base under the arms (holds the dovetail slot)
bar_drop      = 4;    // gap between the round shell's bottom and the bar's top flat (the web spans it)
comb_w        = 8;    // snap_comb clip width
snap_strain_max = 3.0; // % bending strain limit for the snap arms (rule of thumb for PETG/ASA)
leg_tn_w = 14; leg_tn_h = 5; leg_neck_w = 8; slot_fit = 0.15;   // dovetail tenon of the leg in the clip slot (flank atan(3/5) = 31 degrees, prints tenon-up)
leg_col_d     = 24;   // leg column diameter
foot_major    = 16;   // adjustable foot thread: major diameter
foot_pitch    = 4;    // coarse pitch
foot_depth    = 1.2;  // thread depth (peak to valley): the thread is an eccentric circle twisted along the stud, so the steepest flank is depth*pi/pitch = 0.94 <= 1 (45 degrees), it prints standing
foot_len      = 28;   // threaded stud length
foot_disc_d   = 34;   // foot disc diameter
foot_disc_t   = 4;    // foot disc thickness (a TPU or foam pad goes under it)
foot_pad_t    = 1.0;  // [ASSUMED] thickness of the TPU / foam pad glued under the foot disc (counted in support_len, the disc underside is flat)
foot_out      = 12;   // nominal stud length outside the leg
foot_travel   = 8;    // +/- adjustment of the foot
thread_clear  = 0.3;  // radial thread clearance (socket)
comb_si       = [1.0, 1.3, 1.6, 1.9, 2.2];   // snap_comb interference values

// Hole pitch for standard fan sizes. [STANDARD] (120 mm: 105 mm, the Noctua spec)
function fan_pitch(s) = s == 120 ? 105 : s == 92 ? 82.5 : s == 80 ? 71.5 : s == 60 ? 50 : s == 40 ? 32 : undef;

// ---- free space around the card (interference check; measure these) ----
clear_above_fins = 10;   // [REQUIRED] from the block's far face (y = hs_t) to the lower neighbour / case separator (fins face down). Obstacle stays at the old unmeasured y = 24 (was 16 from the 8 mm fin tips; now measured from the 14 mm block face). MEASURE
clear_behind_pcb = 6.6;  // [REQUIRED] from the back cover's back face (y = -(pcb_t+back_t)) to the CPU cooler (up, fins down). Obstacle stays at the old unmeasured y = -9.6. MEASURE
board_below      = 11;   // [REQUIRED] card edge on the motherboard side (z = pcb_h when installed, the fan_flush "top" side) to the motherboard surface
board_front_x    = 25;   // [REQUIRED, PLACEHOLDER, NOT MEASURED] how far the motherboard extends past the card end (X, mm beyond the PCB end) before its front edge; the board slab is cut off there. 25 is a guess so the check can run. With fan_flush "top" the fan edge is level with the sleeve on the board side and the funnel grows away from the board, so this only matters if the fan side ever moves toward the board. MEASURE
clear_z_above    = 100;  // [REQUIRED] card edge away from the motherboard (z = 0 when installed) to the side panel
clear_x_beyond   = 200;  // [REQUIRED] placeholder (you said there is plenty of room): free length past the fin block's far end. MEASURE
// Neighbours on the fin / back side only exist alongside the card, up to the PCB end.   [ASSUMED]
// Extra obstacles as [xmin,xmax,ymin,ymax,zmin,zmax] boxes in card coordinates, e.g. the
// CPU cooler or DIMMs once you have measured them.
extra_keepouts = [];

// ---- air-path check (export.sh fails if any printed duct solid reaches into the air path) ----
airpath_margin = 0.5;   // mm per side the checked air core is shrunk by, so the intended joint_clear narrowing at the spigot tip and coincident faces do not count; must stay above joint_clear

// NOTE: no retention/mounting geometry to the card or case is modelled. The sleeve is a friction/slip fit on the
// card until real anchor points (bracket, case screw point) are measured; the shroud is screwed to the sleeve (one M3). See README.
