# CFD notes: Tesla P4 shroud with a Noctua NF-F12 iPPC-3000 PWM

Comparative CFD only. Nothing here validates cooling of the real card. Numbers rank designs against each other on one model; absolute airflow is uncertain by about 15 % or more (see sensitivities).

## 1. Method

- OpenFOAM v2512 in Docker: snappyHexMesh + porousSimpleFoam, steady RANS (kOmegaSST by default; laminar and SST agree within a few % in the fin calibration). Scripts: `scripts/cfd.sh`, `cfd_batch.sh`, `cfd_post.sh/.py`, `cfd_opcurve.py`. Geometry comes from the same `cad/` files (`cfd/domain.scad`).
- **The fin block is NOT resolved in 3D.** It is a calibrated Darcy-Forchheimer porous zone. The coefficients (`cfd/fins/calibration.json`) come from a resolved unit-cell run (one fin gap, 0.3 mm fin, 10 fins). Reason: resolving 10 fins of 0.3 mm over 170 mm would need orders of magnitude more cells. Check against Shah & London at 5 m/s: hand 28.4 Pa vs CFD 29.2 Pa. Consequence: the model gives pressure drop and flow split into the fin block, but no flow detail inside the gaps and no heat transfer.
- **Fan**: `fanPressure` boundary on a fan-face extension with the hub blocked and a solid-body swirl (about 6.4 m/s at 3000 rpm). Fan curve `cfd/fans/nf-f12-ippc-3000.csv` is [ASSUMED]: only the two datasheet points are published (74.8 Pa max static pressure, 186.7 m3/h = 0.0519 m3/s max flow, 3000 rpm, 3.6 W). The shape between is a stall-shaped guess; a straight line between the two points is the upper-bound bracket. It is not digitised from a measured curve. Fan laws: Q ~ n, dp ~ n^2.
- Datasheet finding: it gives no minimum rpm and no PWM-to-rpm relation, so the rpm table below is by rpm, not by PWM duty. Source: https://3d.nice-cdn.com/upload/file/noctua_nf_f12_industrialPCC_3000_pwm_datasheet_en_web_1.pdf
- Static pressure measured at the fan face is 12-20 Pa lower than the applied fan pressure because of the swirl and axial dynamic head. This is a modelling effect, not a loss; `cfd_opcurve.py` uses the applied pressure.
- Q is flow through the fin block (q_fins). Temperature rise dT is air-side only: dT = P / (rho cp Q), rho 1.2, cp 1006, at 50 and 75 W. It is not a card temperature.

## 2. Orientation and keepouts

Default is `fan_flush_y = "lo"` (standing tower, fins down; fan grows toward +Y). "hi" was run on the same mesh for comparison (section 6). In "lo" the fin-side keepout is limited to x <= pcb_extra, leaving room below the card; that room is an unmeasured [ASSUMED] choice, measure it. The fan sits at +X, which is the left of the `cfd_plane_z` pictures; the fin outlet is at x = -170.

## 3. Mesh, convergence, mass balance

Cell 4 is the working mesh, cell 3 the finer confirmation. Cell 6 was invalid for this geometry (discarded). Failing mass balance (> 1 %) fails the run.

| run | cells | iters | mass mismatch | note |
|---|---|---|---|---|
| lo_ref_c4 (old design) | 387671 | 1500 | 0.051 % | ok |
| lo_novanes_c4 (final) | 141394 | 1500 | 0.017 % | ok |
| final_c4 | 141394 | 3000 | 0.046 % | ok |
| final_c3 | 282707 | 3000 | 0.017 % | ok |
| hi_final_c4 | 136030 | 1500 | 0.134 % | ok |
| flare132_c4 | 142376 | 3000 | 0.113 % | ok (not converged to residualControl, like the other 3000-iteration runs) |
| flip_c4 | 142371 | 3000 | 0.189 % | ok (same note) |
| old_lo_c4 | - | 3000 | 1.146 % | FAILED, directory deleted; old-design numbers use lo_ref_c4 |
| s_plen30 | - | - | > 1 % | FAILED, discarded |

Mesh independence of the final design: Q 4.177 CFM (c4) vs 4.135 CFM (c3), -1.0 %; CoV 0.204 vs 0.194; near-base 0.248 vs 0.284. Noise between repeat/iteration counts is about 0.3 %, so I use 1 % as the regression threshold. Earlier overlapping cell-4/cell-6 batches were killed and resolved; no `s_*` directory mixes meshes. Leak and bypass cases first ran as no-ops (wrong tunnel axis order in `cfd/domain.scad`); fixed and rerun.

## 4. Results (lo orientation, cell 4, 1500 iterations unless noted; Q at iPPC 3000 rpm)

Q column is q_fins. 1 CFM = 4.71947e-4 m3/s. "Out" is the pressure drop outside the fins (funnel, plenum, fan-face losses). CoV is of the fin-entry velocity; near-base is the share of fin-entry flow in the layer next to the base plate (y near 0); 0.248 is close to the area share.

| case | Q CFM | Q m3/s | dp fins Pa | dp outside Pa | CoV | near-base | dT 50/75 W K |
|---|---|---|---|---|---|---|---|
| OLD design (vanes 3/2, trans 106) lo_ref_c4 | 3.510 | 1.656e-3 | 26.14 | 25.23 | 0.479 | 0.318 | 25.0/37.5 |
| FINAL (no vanes) lo_novanes_c4 | 4.175 | 1.970e-3 | 37.15 | 16.27 | 0.204 | 0.248 | 21.0/31.5 |
| FINAL, 3000 it final_c4 | 4.177 | 1.971e-3 | 36.87 | 16.59 | 0.204 | 0.248 | 21.0/31.5 |
| FINAL, finer mesh final_c3 | 4.135 | 1.951e-3 | 37.55 | 15.96 | 0.194 | 0.284 | - |
| FLARE 132 (history: final_c4 above, flare 122) flare132_c4 | 4.14 | 1.954e-3 | 36.9 | 15.6 | 0.167 | 0.241 | 21.2/31.8 |
| FLARE 132, mouth flipped (fan_flush top) flip_c4 | 4.18 | 1.971e-3 | 37.3 | 15.1 | 0.165 | 0.253 | 21.0/31.5 |
| GEOMETRY CORRECTION (not an optimisation): new stepped sleeve, channel moved to the fin tips y 6..14, mouth flipped; NEW BASELINE flipD_c4 (5000 it, mismatch 0.204 %) | 4.18 | 1.975e-3 | 37.2 | 15.3 | 0.155 | 0.248 | 21.0/31.5 |
| FINAL, "hi" hi_final_c4 | 4.224 | 1.993e-3 | 38.05 | 15.42 | 0.166 | 0.188 | 20.8/31.2 |
| FINAL, linear fan curve final_linear_c4 | 4.331 | 2.044e-3 | 39.14 | - | 0.203 | - | - |
| old design, linear curve old_linear_c4 | 3.680 | 1.737e-3 | 27.73 | - | 0.489 | - | - |
| old hi (old_baseline, 3000 it) | 3.81 | 1.80e-3 | - | - | 0.305 | 0.134 | 23.0/34.5 |

Net change at iPPC 3000 rpm: +19 % flow (3.51 to 4.18 CFM), CoV 0.48 to 0.20, near-base 0.318 to 0.248 (it falls toward the area-fair share, not worse in the sense of starving the base). Regression gate (Q not down, CoV and near-base not worse, 1 % threshold) passed. Caveat: the vanes were removed in a steady RANS model; their stiffness and print role is not modelled.

### rpm table (final design; `output/cfd/rpm_table.csv`)

Crossings of a fitted system curve with the [ASSUMED] fan curve scaled by the fan laws. Fit, final: p = 15967 Q + 9.46e6 Q^2 (Q in m3/s, residual 0.5 %); old: p = 19023 Q + 1.31e7 Q^2 (0.7 %).

| rpm | Q CFM | Q m3/s | dp fins Pa | dT air 50/75 W K | old design Q CFM (dT 50/75) | final, linear curve CFM |
|---|---|---|---|---|---|---|
| 1500 | 1.56 | 7.35e-4 | 10.7 | 56.3/84.5 | 1.31 (67.1/100.7) | 1.65 |
| 2000 | 2.40 | 1.13e-3 | 18.1 | 36.6/54.9 | 2.01 (43.6/65.4) | 2.50 |
| 2500 | 3.28 | 1.55e-3 | 26.9 | 26.7/40.1 | 2.76 (31.8/47.7) | 3.40 |
| 3000 | 4.19 | 1.98e-3 | 37.2 | 21.0/31.4 | 3.52 (24.9/37.4) | 4.32 |

Direct CFD at reduced rpm agrees: final_rpm1500_c4 1.5645 CFM (dp fins 10.80, CoV 0.251, near-base 0.229); final_rpm2000_c4 2.3971 (18.08, 0.226, 0.239); old_rpm1500_c4 1.3153 (8.52, CoV 0.422); old_rpm2000_c4 2.0119 (13.70, 0.448). Air-side dT of 56-85 K at 1500 rpm shows the fan cannot be run that low at 50-75 W without the card overheating; this is a flag, not a prediction. Plot: `output/cfd/operating_point.png`.

## 5. Optimisation: every concept tried

Upside bound first: the dynamic head at the fin exit is about 9-14 Pa against about 16 Pa of outside loss, so the funnel/fan side can give at most roughly 10-25 % more flow. An ideal exit diffuser (not in CAD) gave +6.3 %.

| concept | Q CFM | vs 4.175 (final) | CoV | near-base | verdict |
|---|---|---|---|---|---|
| old: vanes 3/2, linear funnel | 3.510 | -16 % | 0.479 | 0.318 | replaced |
| vanes_y 3, vanes_z 0 (lo_vz0_c4) | 3.742 | -10 % | 0.486 | 0.319 | rejected |
| no vanes, linear funnel trans 106 | 4.175 | 0 | 0.204 | 0.248 | ADOPTED |
| no vanes, trans 140 (+34 mm) | 4.224 | +1.2 % | 0.180 | 0.241 | rejected, marginal for the envelope |
| smooth poly5 funnel, vaned, trans 198 | 3.277 | -22 % | 0.694 | 0.416 | rejected, +92 mm envelope (poly5 at the 45 deg limit needs 198 vs 106) |
| no vanes, wider opening (open116) | 4.154 | -0.5 % | - | - | rejected |

Tested later at cell 4, 3000 iterations, same mesh settings, all mass imbalance < 0.1 % (none discarded). Gate against final_c4 (4.177 CFM, CoV 0.204, near-base 0.248, 1 % threshold on Q, CoV and near-base):

| case | Q CFM | vs final | CoV | near-base | mass imb. | verdict |
|---|---|---|---|---|---|---|
| rounded channel entry, entry_r 12 mm (entry_r12_c4) | 4.232 | +1.3 % | 0.115 | 0.233 | 0.010 % | fails gate: near-base -6 % relative |
| rounded channel entry, entry_r 25 mm = max printable (entry_r25_c4) | 4.253 | +1.8 % | 0.100 | 0.232 | 0.075 % | fails gate: near-base -6 % relative |
| hub 30, no fairing (hub30_c4, reference) | 4.316 | +3.3 % | 0.167 | 0.246 | 0.061 % | reference |
| hub 30 + 60 mm fairing (hub30f_c4) | 4.387 | +5.0 % (+1.6 % vs hub30) | 0.168 | 0.246 | 0.048 % | |
| hub 40 + 60 mm fairing (hub40f_c4) | 4.234 | +1.4 % | 0.168 | 0.244 | 0.045 % | near-base -1.6 % relative, marginal |
| hub 50, no fairing (hub50_c4, reference) | 4.029 | -3.5 % | 0.171 | 0.238 | 0.040 % | reference |
| hub 50 + 60 mm fairing (hub50f_c4) | 4.048 | -3.1 % (+0.5 % vs hub50) | 0.170 | 0.240 | 0.025 % | |

Rounded entry (`entry_r`, default 0 in `cad/params.scad`, not adopted): a circular arc of radius entry_r replaces the 45 deg kink where the funnel leaves the 8 mm channel at x_s = 22. It starts upstream, inside the straight channel (tangent to the channel axis at x_s - 0.41 R), so trans_len and the envelope do not change, and it is never steeper than the funnel wall, so it prints support-free. Maximum printable radius is about 25 mm; 26 fails the assert that keeps the arc 1 mm clear of the flat stop (x = 10.3). The geometry change is tiny (fluid volume +0.01 % at R 12, +0.06 % at R 25) and cell 4 puts only about 2 cells across the 8 mm channel, so the result is at the edge of what this mesh resolves. It evens out the fin-entry velocity (CoV 0.204 to 0.115 and 0.100) and gains +1.3 to +1.8 % Q, but it moves flow away from the base plate (near-base 0.248 to 0.23), so it fails the near-base part of the gate. Not adopted, therefore not re-run on cell 3 and the CAD default is unchanged. A firmer statement would need a finer mesh or measurement. The [ASSUMED] fan curve and swirl apply as everywhere.

Wider bellmouth, flare 132 mm (`fan_flare_d = fan_open_d + 20`, was 122; flare132_c4, new baseline): the CFD inlet used to be a plain 120 mm face, so the CAD flare was clipped by the inlet and the CFD never saw it. The inlet face is now built from the same bell parameters as the CAD (45 deg cone plus tangent arc, `flare_depth` 12), so CAD and CFD agree. Gate against final_c4: Q 4.14 against 4.177 CFM (-0.9 %, inside the 1 % threshold), CoV 0.167 against 0.204 (better), near-base 0.241 against 0.248 (-0.007 absolute, -2.7 % relative, inside the threshold). Verdict: passes, marginally on Q and near-base; adopted as the new baseline because the CAD bell is the geometry that is built and the flow is more even. final_c4 stays in the tables as history (flare 122, clipped inlet).

Funnel mouth flipped, `fan_flush = "top"` (flip_c4, now the installed orientation; reference flare132_c4): the fan swirl does not mirror, so the flipped funnel was run to see. Gate against flare132_c4: Q 4.177 against 4.141 CFM (+0.9 %), CoV 0.165 against 0.167, near-base 0.253 against 0.241 (+0.012). Verdict: passes (nothing worse; the gains are inside the 1 % threshold, so read it as "no change"). Mass mismatch 0.189 %. The flip is chosen by where the card and motherboard leave room, not by flow.

Hub fairing (CFD only, `fair_len` in `cfd/domain.scad`, a 60 mm cone behind the blocked hub, tip toward the funnel): +1.4 % at hub 40, +1.6 % at hub 30, +0.5 % at hub 50 against the same hub without fairing; CoV 0.168 at hub 30 and 40 and 0.170 at hub 50, near-base within 0.004. The sign is consistent but only the 30 and 40 mm gains exceed the 1 % threshold, and the hub size itself moves Q by 3 to 4 % per 10 mm, so the result depends on the assumed hub size (40 mm, [ASSUMED]) and swirl (6.4 m/s, [ASSUMED]). Built, as part of the optional stator layer (`stator_layer` in the CAD, see README): a 60 mm cone, half angle 18 deg (at most 45 deg so it prints without supports), on the downstream face of the stator hub, pointing into the funnel. It is carried by the hub and the 9 vanes, clears the funnel walls by at least 2 mm (69 mm would still fit), and the layer prints with its spacer-side face on the bed, cone up. The plain spacer plate has no hub, so it is not a home for it. Whether it helps on the real fan (hub of about 40 mm or less) still needs a print-and-measure A/B.

Not implemented, with reasons: area-ruled/biased vanes (after removing the vanes the remaining headroom is inside the model uncertainty); adjoint (not set up). Stator behind the fan: print-and-measure A/B only (blade angle <= 45 deg from axial with the flange on the bed, leading edges at least 10 mm from the fan blades; the fan frame already has angled struts), not simulated. Stack-2 and orientation "none" were not rerun.

CAD changes (`cad/params.scad`, MEASURED values untouched): vanes_y = vanes_z = 0, fan_flush_y = "lo", trans_len 106 (the linear funnel for "lo" needs >= 106 to pass the 45 deg assert; max wall shift 105.1 mm), contr_poly5 = false. The envelope is not enlarged. No fan or GPU in the outputs; no supports required.

## 6. Sensitivities and uncertainty (against final 4.175 CFM)

| change | Q CFM | change | note |
|---|---|---|---|
| swirl off | 4.795 | +15 % | dp fan 68.3, CoV 0.212 |
| hub blockage off | 4.664 | +12 % | CoV 0.212 |
| fin thickness 0.8 mm (was 0.3 [ASSUMED]) | 3.694 | -11.5 % | dp fins 40.7 |
| kOmegaSST vs default | 4.227 | +1.2 % | CoV 0.204 |
| leak 150 mm2 (flagged, unmeasured) | 4.152 | -0.55 % | q_in 5.057, about 0.9 CFM escapes; CoV 0.238 |
| bypass slab 2 mm over fins (flagged, unmeasured) | 4.4995 | +8 % | q_in 4.721, dp fins 29.15, CoV 0.281; q_fins probably includes the slab flow, so this is not a gain |
| exit diffuser 50 mm + 10 mm gap | 4.439 | +6.3 % | ideal upper bound, not in CAD; dp out 12.78, CoV 0.174, near-base 0.244, dT 19.8/29.7 K |
| fan curve: linear bracket | 4.331 | +3.7 % | |
| orientation "hi" (same mesh) | 4.224 | +1.2 % | about the noise; CoV 0.166 better, near-base 0.188 worse |

"lo" is the default because near-base share at the base plate is better (0.248 vs 0.188) and flow is equal within noise. The dominant uncertainty is the assumed swirl and hub behaviour of the real fan (+12 to +15 %) and the assumed fin thickness; the porous model carries a few % more. Absolute Q is therefore not a prediction; the ranking of designs is more robust because all share these assumptions.

## 7. Images (opened and checked one by one)

Kept for four cases only (final_c4, lo_ref_c4 = old design, hi_final_c4, sens_diff50_c4) to save disk (output/cfd is about 3.9 GB); every other case keeps `results.json` and `model.txt`. Each case folder has:
- `cfd_plane_z.png`: velocity on the channel-centre plane z = 27.5 mm; fan at the left, +X points left.
- `cfd_plane_y.png`: velocity on y = 4 mm, the channel mid-plane.
- `cfd_fin_entry.png`: velocity over the fin entry (x = -1 mm), looking toward the fan.
- `cfd_funnel_zfan.png`: velocity on the fan-centre plane z = 56.6 mm.
- `cfd_pressure_x.png`: cross-section average static pressure along the duct; the fin block is the linear ramp.
- `output/cfd/operating_point.png`: fan curves at 1500-3000 rpm against the system curves, old and final.
What the images show: final_c4 and lo_ref_c4 were checked earlier; the old design has vane wakes and uneven fin entry; the final design has a smooth core with slow edges (low-velocity pocket in the funnel centre, edge lag at the side walls). The "hi" case has a more even entry but less near-base flow. The diffuser case shows velocity falling in the added exit section and static pressure at the fin exit of -4.8 Pa.

## 8. Limits

- No CHT: heat transfer, fin conduction and card temperatures were not modelled (stretch goal, skipped).
- Porous fins, steady RANS, assumed fan curve, swirl and hub; leak and bypass sizes are unmeasured.
- The room below the card for "lo" and the clear_* distances are [ASSUMED]/[REQUIRED] and must be measured (`MEASUREMENTS.md`).
- Never read the dT or Q as proof that the card stays cool.

New baseline flipD_c4 (geometry correction, not an optimisation): the inlet channel was modelled on the wrong side of the 14 mm block (y 0..8). It now sits at the fin tips, y 6..14 (6 mm solid base `hs_base` plus 8 mm of fins), and the sleeve cavity follows the measured card end cross-section. Q 4.18 CFM (same as flip_c4 4.18), CoV 0.155 (flip 0.165), near-base share 24.8 % of the flow in y 6..8 (the old 0.253 was measured at y 0..2 on the old channel, so it is NOT comparable). Earlier rows (flare132_c4, flip_c4 and older) used the old channel position and are history only; compare future changes against flipD_c4. The first 3000-iteration run failed the 1 % inlet/outlet gate (1.157 %) and was discarded; the 5000-iteration rerun passes at 0.204 %. The runs made on the intermediate sleeve (flipC, fliptailC) were discarded. The stator A/B and tail-cone runs on this geometry are on hold.

## 2026-10-24 - stator layer, hub tail cone, vane-tip gap (on the flipD_c4 geometry)

New CFD-only switches in `cfd/domain.scad` (nothing in `cad/` changed): `cfd_stack` (fan face at x_end + N, at the real CAD positions: 12 = spacer, 15 = spacer + stator layer), `stator_cfd` (the CAD's own hub, `stator_vanes()` and tail), `cfd_tail_len`, `cfd_tail_lean` / `cfd_tail_dir` (leaning tail, [ASSUMED] variant), `cfd_tip_clear`, `cfd_vanes`. All runs: cell 4, 5000 iterations (8000 where noted), mass-balance gate 1 %. Metric: q_fins (CFM). Noise: flipD_c4 4.1842 vs repeat base_rep 4.1878 = 0.09 %; earlier figure 0.3 %; threshold 1 %.

| run | what | q_fins CFM | vs control | CoV | note |
|---|---|---|---|---|---|
| flipD_c4 / base_rep | old collapsed domain (face at x_end) | 4.184 / 4.188 | - | 0.155 | spacer-length effect below |
| s_off12 | spacer only, no stator (CONTROL for all stator rows) | 4.222 | +0.9 % vs flipD_c4 | 0.152 | |
| s_on_h-1 | stator hub + 9 vanes + 60 mm tail, hand -1 | 4.329 | +2.5 % | 0.163 | |
| s_on_notail | same, tail_len 0 | 4.329 | +2.5 % (0.0 % vs straight tail) | 0.163 | tail is irrelevant |
| s_on_lean25 | same, tail leaned 25 deg toward the channel (dir 146.5 deg) | 4.330 | +2.6 % (0.0 % vs straight) | 0.163 | lean is irrelevant |
| s_on_h+1_8k | vanes, opposite hand (wrong swirl direction) | 4.260 | +0.9 % (-1.6 % vs matched) | 0.163 | 5000 it failed the gate (2.5 %), re-run at 8000 |
| s_gap_2mm | vane-tip gap 2 mm instead of 0.4 | 4.320 | -0.2 % vs 0.4 mm gap | 0.162 | within noise |
| s_gap_closed(_8k) | tip overlap (closed gap) | invalid | - | - | failed the gate twice (1.24 %, 1.11 %), not used |
| s_hub_only | hub + tail, NO vanes | 4.346 | +3.0 % | 0.153 | the best row |

Reading: the gain (+2.5..3 %) comes from the blocked hub continued upstream (it removes the dead core behind the fan hub), not from the vanes. Without vanes it is even 0.4 % better than with them, and the vanes in the wrong hand lose 1.6 %. The tail length/lean and the tip gap are all inside the noise, so no reason to lean the tail or close the gap (0.4 mm and 1.2 mm vanes are also near the mesh size, so the gap result is weak evidence). Vane twist not tried: the stator does not pay. Not adopted into `cad/` (hand `stator_hand` is [REQUIRED] and unknown, hub diameter is [ASSUMED], the swirl model is assumed). If the hub gain is wanted, the hub/nose puck is the part to try, to be confirmed with nvidia-smi.

## 2026-10-24 - cambered, twisted stator vanes (comparative only)

New vane type `stator_vane = "cambered"` (params `stator_in_hub/tip`, `stator_out_deg`, `stator_le_frac`, `stator_te_frac`, `stator_te_t`); the old slab stays as `"flat"`. `scripts/cfd.sh --swirl-dir 1|-1` flips the assumed swirl (solid-body, 6.38 m/s at r = 40 mm, 3000 rpm, [ASSUMED]); `stator_hand = -1` is matched to the default +X swirl. Cell 4, 5000 iterations, gate 1 %, noise 0.09 %, decision threshold 1 %. The cavity clearances (slide_clear 0.65, the three extras 0.25) were pinned with -D so every row below is on one geometry (earlier attempts on a moving cavity were discarded). Bore past the plate was 21 mm when these ran; the case has since been shortened (12 mm), so use the rankings, not the absolute values.

| run | what | q_fins CFM | vs spacer | note |
|---|---|---|---|---|
| v_off | spacer only (CONTROL) | 4.207 | - | |
| v_hub | hub + tail, no vanes | 4.331 | +2.9 % | |
| v_a | 9 cambered vanes, chord 14, 60/75 deg, matched | 4.484 | +6.6 % | |
| w_hi | inlet 70/82 | 4.478 | +6.5 % | within 0.2 % of v_a |
| w_lo | inlet 50/68 | 4.480 | +6.5 % | within 0.2 % of v_a |
| w_n11 | 11 vanes | 4.490 | +6.7 % | within 0.2 % of v_a |
| w_c20 | chord 20 | invalid | - | gate 2.06 %, not re-run; does not fit the shorter bore |
| v_a_sm | reversed swirl, hand +1 (matched to it) | invalid | - | gate failed (>1 %) at 5000 it, not re-run at 8000 |

Reading: the hub is about +3 %, the cambered vanes add about +3.5 % more (the old flat vanes added nothing over the hub). Angles 50..82 degrees and 9 vs 11 vanes are a plateau inside 0.2 %. Open: spin-reversed and wrong-hand runs for the new vanes did not converge to the gate, so only the earlier flat-vane result (wrong hand -1.6 %) says anything about hand dependence. All of it rests on the assumed swirl model and the assumed fan curve; nothing here is validated cooling. Noctua's blade count and rotation direction: noctua.at returned 429 and no authoritative source was found, so they stay [ASSUMED]/[REQUIRED].

## Short stack check (trans_len 89, plenum 4, flange 8, direct mount, no stator)

Relative only: same fan curve, swirl on (3000 rpm), cell 4, 5000 iterations, no stator, as `base_rep` (trans_len 106, plenum 10, face at x_end). Run `short_t89_5k` (a 3000-iteration run `short_t89` gave the same picture but is not used, mass balance 0.94 %).

| Case | Q fins (CFM) | fan-face p (Pa) | across fins (Pa) | everything else (Pa) |
|---|---|---|---|---|
| base_rep (long) | 4.19 | 52.5 | 37.2 | 15.3 |
| short_t89_5k | 4.15 | 52.5 | 36.7 | 15.8 |

Result: about -0.9 % fin flow for 38 mm less length (the repeat noise is 0.09 %, the decision threshold 1 %). The contraction tolerates the steeper funnel (47.7 degrees). Neither run converged to residualControl; the mass balance is 0.13 % and 0.76 %. Not a cooling validation.
