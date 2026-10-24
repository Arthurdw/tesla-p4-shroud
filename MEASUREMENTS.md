# Measurement checklist & assumptions

No geometry is modelled until the **Required** items are filled in.
Every unknown becomes an explicit parameter in `cad/params.scad` (no silent defaults).

## Known from published sources (not measured on your hardware)
| Item | Value | Source |
|---|---|---|
| P4 board outline (nominal) | 167.64 x 68.58 mm | NVIDIA Tesla P4 product brief, "Board Dimensions" |
| Airflow | bidirectional, passive, needs system airflow | same |
| Bracket | low-profile or ATX supplied | same |

The heatsink, its height above the PCB, and the bracket on *your* card are not in
the brief and must be measured (Dell/HP/OEM cards differ).

## Observed in your photos (no scale reference, so no numbers taken)
- Board: ASUS PRIME B250M-PLUS (mATX). Case is lying on its side in the photos; in use it is a standing tower.
- P4 has a full-height (ATX) bracket and sits in a PCIe slot with a second card
  (green add-in card with a finned heatsink) very close on the bracket-side neighbour slot.
- Cooler Master tower cooler (horizontal fan) sits right beside the P4's other face;
  the gap looks like only a few mm to ~1-2 cm. This is the main clearance risk.
- Beyond the P4's far end: ASUS M.2 heatsink, SATA ports, and DIMMs further right.
  The 24-pin ATX cable runs along the board front edge.
- Case front has 3 fans at the bottom of the photo; a large free area exists in front of the board.
- The P4 heatsink fins are copper-coloured and visible on the CPU-cooler-facing side.

## Fan: Noctua NF-F12 industrialPPC-3000 PWM (chosen by user)
Per the [Noctua datasheet](https://3d.nice-cdn.com/upload/file/noctua_nf_f12_industrialPCC_3000_pwm_datasheet_en_web_1.pdf):
120 x 120 x 25 mm, hole spacing 105 x 105 mm, 3000 rpm, 186.7 m3/h, 7.63 mmH2O (74.8 Pa), 4-pin PWM.
The datasheet gives no minimum rpm and no PWM-to-rpm relation.
Static pressure is the lever (the duct plus the fins is high resistance), hence the iPPC.
History: the first fan was an NF-P12 redux-1700 (2.83 mmH2O); an earlier note that "120 mm likely does not fit, 80 mm is realistic" was superseded by the 120 mm design. `fan_size` = 80 remains the fallback if clearances fail.

## Setup (from you)
- Standing tower case. The P4 fins face DOWN (+Y) toward a metal PSU-shroud separator; the PCB back faces up toward the CPU cooler. `fan_flush_y = "lo"`.
- Screws: only M3x10 (`screw_len`). Countersunk heads (user, 2026-10-24): 6.5 x 3.2 mm pockets with a 90 degree countersink at the floor; head diameter `cs_head_d` 6.0 is the DIN 7991 nominal, not measured. M3 heat-set inserts, `insert_len` 4 mm (user); `insert_d` 4.0 is a typical maker hole, not measured.
- `support_len` ([REQUIRED]): distance from the bottom of the hex bar to the separator below. Placeholder 80 mm in `cad/params.scad`.

## Measured by you
- Card END cross-section (you measured it; Y = 0 is the PCB face that carries the heatsink, +Y points to the fin tips): back cover 2 mm thick x 54 mm wide (`back_t`, `back_w`); PCB 1 mm thick x 56 mm wide (`pcb_t`, `pcb_h`); cooling block 14 mm thick (`hs_t`), 54 mm wide at the PCB side tapering to 53 mm at the far face (`hs_w`, `hs_w_tip`), rounded corners (not modelled). The block is a 6 mm solid base (`hs_base` = `hs_t` - `hs_h`) plus 8 mm of fins, and the inlet channel sits at the fin-tip side, y 6..14 ([MEASURED], user). The back cover and the block are centred on the PCB across its width (checked by eye, [MEASURED]). Along the card, the bare PCB sticks out 1 mm past the block end face (`pcb_extra`), and the back cover ends flush with the block ([MEASURED], user).
- The sleeve cavity is these three layers each grown by `slide_clear` = 0.65 mm per side ([MEASURED] by fit test 2026-10-24: 0.4 was the assumed start, the v4 `fitcheck_mouth` was too hard to push on, v5 at 0.9 had far too much play, so v6 is 0.65, and the v6 fit test fits well; the back cover, PCB ends and PCB faces get 0.25 more each (0.9 total, slot 2.8 wide); replaces the old `entry_w`, `entry_h`, `back_clear`, `cav_r`). Print `sleeve_print` first and slide it onto the card; if it binds or wobbles, change `slide_clear`.
- The 8 mm inlet channel is 51.6 mm wide (`chan_hz`), centred on the card, 1.7 mm narrower than the 53 to 54 mm block at each end because a gap was visible on both sides. It is decoupled from the block width; the exact width of the finned part is not measured.
- Fin block: 8 mm tall above the PCB face (`hs_h`), about 170 mm long (`hs_len`).
- Fin count: 10 fins across the block (`fin_n`). `fin_pitch` is derived as finned width / 10 = 5.16 mm, taking the finned width as the channel width (51.6 mm); the finned width itself is unmeasured. The passages are therefore about 4.9 x 8 mm rectangular ducts, not thin parallel plates.

## Still open (needed before the shroud print)
- [REQUIRED, PLACEHOLDER, NOT MEASURED] `board_front_x`: how far the motherboard extends past the card end (mm, along the flow axis). It is set to 25 as a guess. With `fan_flush = "top"` the fan is level with the sleeve on the board side and the funnel grows away from the board, so the shroud does not depend on it; it only bounds the board in the interference check. Measure it from the card end to the front edge of the board, at the slot.
- Fan hub diameter (`fan_hub_d`): [MEASURED] 40 mm (user, 2026-10-24). It sizes the stator hub, the nose puck and the optional tail cone (`tail_len`), and is the blocked hub in the CFD fan-face extension. Nothing left to do here.
- Fin pitch and thickness: only the count (10) is known. Measure the finned width (the pitch follows) and the fin thickness (`fin_t`, 0.3 mm is a guess); both feed the CFD pressure drop (`scripts/cfd.sh`).
- What fills the black cover above the 8 mm fins (it looks about 13 mm tall in the photo)? If it is hollow, air bypasses the fins over the top, and the sealed-duct CFD overstates the fin pressure drop.
- Does anything on the fin side (black fin cover, clips) reach past the block end face? The block seats on the channel step 0.3 mm (`stop_gap`) past it.
- `fan_tab_t` ([ASSUMED] 4 mm): thickness of the fan's corner tab where the screw goes through. It sets the insert hole depth (`fan_hole_depth`, 6.5 mm) in the shroud flange (direct mount, default) or the spacer; the flange is 8 mm thick for this, so a thicker tab than 4 mm leaves less thread: MEASURE it. The stack length budget (148 mm, `stack_max_len` [ASSUMED]) also needs the real distance from the card end to the nearest obstacle (A9 below).
- Open corner: the fan screws now go in from the fan side (head on the tab, into inserts in the shroud flange or the spacer), so the fan can be swapped without taking the stack apart. Check that a countersunk M3 head (6 mm) and a 2 mm hex key fit between the fan's two corner flanges.
- Fan blade count (assumed 7; sets the stator vane count, 9 shares no factor with 7).
- Optional: do the P4 bracket vents matter, and what is the distance from the fin end to the bracket? Only needed if you want a seal or a flow path there.
- Fan, on the face that touches the flange: the diameter of the flared opening at the frame face (`fan_flare_d`, now 132, [MEASURED]: user-confirmed with the d132 fitcheck coupon (`fitcheck_fanface` _d132)) and where the flare ends at the blades (`fan_open_d`, assumed to be 112).
- Heat-set inserts: M3 (confirmed by you). Your inserts are 4 mm long (`insert_len`, from you). The hole is 4.0 mm, the usual maker spec for M3 inserts (smaller than the ~4.6 mm knurl, so the melted plastic fills the knurls); it is not measured. Check your insert's datasheet and test it in `fitcheck_interface`.

## Required measurements (calipers or ruler beside the part)
Please give mm, and photos with the ruler visible.

**A. P4 card (remove from case or measure in place)**
1. Heatsink fin block: length, width (card thickness, PCB face to fin tips), height (above PCB top edge to fin top).
2. Fin direction: along the card length or across? Fin pitch/count (photo from above, ruler in frame).
3. Heatsink offset from the PCB end and from the bracket end (length direction).
4. PCB thickness, and any parts taller than the fins (caps, backplate, screws).
5. Bracket type and the screw/mounting hole positions on the card (is the heatsink screwed from the back? Which fasteners are free to reuse?).
6. Is there any exposed card-edge area or bracket tab where the shroud could lightly clip?

**B. Clearances inside the case (card installed)**
7. Gap between P4 heatsink face and the CPU cooler (narrowest point), and cooler height above the board.
8. Gap between P4 and the neighbouring green card (and that card's component height).
9. Distance from the P4 far end to the nearest obstacle (M.2 heatsink / SATA / front cables), measured along the card length.
10. Distance from the board surface to the case side panel (total free height above the P4 top edge).
11. Distance from the P4 top edge to the cooler's fan blades/frame.
12. Which PCIe slot number is the P4 in (counting from the CPU)? Could it move to another slot?

**C. Case / mounting**
13. Case model. Is the side panel solid or vented? Are there free screw holes (PCI bracket slot, motherboard standoffs) near the P4?
14. Does the PCIe retention hardware matter (tool-less lock on the slot, bracket hold-down)?

**D. Fan**
15. Fan: NF-F12 iPPC-3000, 120 x 25 mm (decided). Still to confirm: hole diameter (`fan_hole_d`), corner radius, tab thickness, open corner (head and hex-key room for screws from the fan side), blade count.
16. Drop from the shroud's hex bar to the separator below (`support_len`).

## Assumptions (to be confirmed, none are baked into geometry)
1. The fan can sit at the far (non-bracket) end and push air along the fin direction.
   Valid only if fins run along the card length and A9 leaves room.
2. The 120 mm fan fits in the standing-tower layout (fins down, free space beside the PSU shroud). Verify with the B measurements and the interference check; `fan_size` = 80 is the fallback.
3. Shroud is retained by gripping the card/bracket or a case screw point, never by loading the PCB or fins.
4. Print material PETG/ASA, 0.2 mm nominal print tolerance per side, 0.4 mm nozzle. Tune after fit-check print.
5. P4 at 50-75 W; real cooling performance is NOT validated by CAD. Check temps under load (`nvidia-smi`).

## Prior art reviewed
No open-source P4/T4 shroud with usable CAD turned up. Found only commercial prints, e.g. a
[60 mm fan adapter for P4/M4/T4/L4/A2/A4 (Jawa listing)](https://www.jawa.gg/product/66795/nvidia-tesla-p4-m4-t4-a2-a4-l4-home-ai-cooling-fan-adapter)
and [STKN 3D Prints' 40/80 mm adapters for A100/CMP (Tindie)](https://tindie.com/products/stkn-3d-prints/nvidia-tesla-a100-cmp-170hx-fan-shroud).
Take-away: commercial P4/T4 designs use small (60 mm) fans, consistent with tight neighbours; none are used as dimension sources.
