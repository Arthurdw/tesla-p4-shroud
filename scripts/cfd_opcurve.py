#!/usr/bin/env python3
"""Operating-point plot and rpm table from CFD runs.

Usage: uv run --python 3.12 --with numpy --with matplotlib python scripts/cfd_opcurve.py
         --final NAME [NAME ...] --old NAME [NAME ...]

Each named run (output/cfd/NAME/results.json) is one CFD point (Q, fan-face static pressure, pressure across the fins).
The system curve p = a*Q + b*Q^2 is least-squares fitted to those points (no constant term), for the whole duct (fan-face pressure)
and for the fins alone. Operating points at each rpm are the crossings of the fitted system curve with the fan curve scaled by the
fan laws (Q ~ n, p ~ n^2). The fan curve is the ASSUMED stall-shaped one from cfd/fans/nf-f12-ippc-3000.csv (linear one drawn too).
"""
import argparse, csv, json
from pathlib import Path
import numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
CFM = 1 / 4.71947e-4
RHO, CP = 1.2, 1006.0
PMAX, QMAX = 74.8, 186.7 / 3600
RPMS = [1500, 2000, 2500, 3000]

ap = argparse.ArgumentParser()
ap.add_argument("--final", nargs="+", required=True)
ap.add_argument("--old", nargs="+", default=[])
ap.add_argument("--out", default=str(ROOT / "output" / "cfd"))
a = ap.parse_args()

rows = list(csv.reader(l for l in open(ROOT / "cfd/fans/nf-f12-ippc-3000.csv") if not l.startswith("#")))
tab = np.array([[float(x) for x in r] for r in rows[1:]])
qf, p_stall, p_lin = tab[:, 0], tab[:, 1], tab[:, 2]


def fan(q, rpm, col):
    s = rpm / 3000.0
    return np.interp(q / (QMAX * s), qf, col, right=0.0) * PMAX * s * s


def load(names):
    pts = []
    for n in names:
        r = json.load(open(ROOT / "output/cfd" / n / "results.json"))
        # Fan pressure the model actually applied at this run's own Q, rpm and curve (model.txt). The static pressure
        # measured at the fan face (dp_fan_Pa) is lower by the swirl/axial dynamic head, so the crossings use the applied one.
        m = (ROOT / "output/cfd" / n / "model.txt").read_text()
        col = p_lin if "linear curve" in m else p_stall
        rpm = float(m.split("swirl_rpm=")[1].split()[0])
        pts.append((r["q_fins_m3s"], float(fan(r["q_in_m3s"], rpm, col)), r["dp_fins_Pa"], n))
    return pts


def fit(Q, P):
    M = np.c_[Q, Q * Q]
    return np.linalg.lstsq(M, P, rcond=None)[0]


def analyse(names):
    pts = load(names)
    Q = np.array([p[0] for p in pts]); Pf = np.array([p[1] for p in pts]); Pn = np.array([p[2] for p in pts])
    sys_all = fit(Q, Pf); sys_fin = fit(Q, Pn)
    res = {"points": pts, "sys": sys_all, "sysfin": sys_fin, "resid": float(np.max(np.abs(np.c_[Q, Q * Q] @ sys_all - Pf) / Pf) * 100)}
    qq = np.linspace(1e-6, QMAX * 0.6, 20000)
    ops = {}
    for col, nm in ((p_stall, "stall"), (p_lin, "linear")):
        for rpm in RPMS:
            diff = fan(qq, rpm, col) - (sys_all[0] * qq + sys_all[1] * qq ** 2)
            i = np.where(np.sign(diff[:-1]) != np.sign(diff[1:]))[0]
            q0 = qq[i[0]] if len(i) else float("nan")
            ops[(nm, rpm)] = (q0, sys_all[0] * q0 + sys_all[1] * q0 ** 2, sys_fin[0] * q0 + sys_fin[1] * q0 ** 2)
    res["ops"] = ops
    return res


fin = analyse(a.final)
old = analyse(a.old) if a.old else None

out = Path(a.out)
with open(out / "rpm_table.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["rpm", "Q_cfm", "Q_m3s", "dp_fins_Pa", "dTair_50W_K", "dTair_75W_K"])
    for rpm in RPMS:
        q, pa, pn = fin["ops"][("stall", rpm)]
        w.writerow([rpm, f"{q * CFM:.2f}", f"{q:.4e}", f"{pn:.1f}", f"{50 / (RHO * CP * q):.1f}", f"{75 / (RHO * CP * q):.1f}"])
if old:
    with open(out / "rpm_table_old_design.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["rpm", "Q_cfm", "Q_m3s", "dp_fins_Pa", "dTair_50W_K", "dTair_75W_K"])
        for rpm in RPMS:
            q, pa, pn = old["ops"][("stall", rpm)]
            w.writerow([rpm, f"{q * CFM:.2f}", f"{q:.4e}", f"{pn:.1f}", f"{50 / (RHO * CP * q):.1f}", f"{75 / (RHO * CP * q):.1f}"])
with open(out / "rpm_table_linear_curve.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["rpm", "Q_cfm", "Q_m3s", "dp_fins_Pa", "dTair_50W_K", "dTair_75W_K", "note"])
    for rpm in RPMS:
        q, pa, pn = fin["ops"][("linear", rpm)]
        w.writerow([rpm, f"{q * CFM:.2f}", f"{q:.4e}", f"{pn:.1f}", f"{50 / (RHO * CP * q):.1f}", f"{75 / (RHO * CP * q):.1f}", "final design, linear (upper-bound) fan curve"])

# ---- plot
fig, ax = plt.subplots(figsize=(10, 6), dpi=130)
cols = {1500: "#4c78a8", 2000: "#59a14f", 2500: "#f28e2b", 3000: "#e15759"}
qq = np.linspace(0, QMAX, 400)
for rpm in RPMS:
    s = rpm / 3000
    ax.plot(qq * CFM, fan(qq, rpm, p_stall), color=cols[rpm], lw=2, label=f"fan {rpm} rpm (assumed shape, fan laws)")
    ax.plot(qq * CFM, fan(qq, rpm, p_lin), color=cols[rpm], lw=1, ls=":", alpha=0.7)
qs = np.linspace(0, 0.045 * 1.0, 300)
ax.plot(qs * CFM, fin["sys"][0] * qs + fin["sys"][1] * qs ** 2, color="k", lw=2.4, label=f"system, final design: p = {fin['sys'][0]:.0f} Q + {fin['sys'][1]:.2e} Q^2  (Q m3/s)")
if old:
    ax.plot(qs * CFM, old["sys"][0] * qs + old["sys"][1] * qs ** 2, color="k", lw=1.6, ls="--", label="system, old design")
for rpm in RPMS:
    q, pa, _ = fin["ops"][("stall", rpm)]
    ax.plot(q * CFM, pa, "o", color=cols[rpm], mec="k", ms=8, zorder=5)
    ax.annotate(f"{q * CFM:.1f} CFM", (q * CFM, pa), textcoords="offset points", xytext=(6, -14), fontsize=8)
    if old:
        q2, p2, _ = old["ops"][("stall", rpm)]
        ax.plot(q2 * CFM, p2, "s", color=cols[rpm], mec="k", ms=6, mfc="none", zorder=5)
for n, (q, pf, pn, nm) in enumerate(fin["points"]):
    ax.plot(q * CFM, pf, "x", color="k", ms=7, zorder=6, label="CFD runs used for the fit (final design)" if n == 0 else None)
if old:
    for n, (q, pf, pn, nm) in enumerate(old["points"]):
        ax.plot(q * CFM, pf, "+", color="k", ms=7, zorder=6, label="CFD runs used for the fit (old design)" if n == 0 else None)
ax.set_xlim(0, 110); ax.set_ylim(0, 85)
ax.set_xlabel("airflow Q through the fins [CFM]   (top axis: m3/h)"); ax.set_ylabel("static pressure [Pa]   (right axis: mmH2O)")
sec = ax.secondary_xaxis("top", functions=(lambda c: c * 1.699, lambda m: m / 1.699)); sec.tick_params(labelsize=8)
secy = ax.secondary_yaxis("right", functions=(lambda p: p / 9.80665, lambda m: m * 9.80665)); secy.tick_params(labelsize=8)
ax.set_title("Operating points: NF-F12 iPPC-3000 at reduced rpm against the shroud + fin system curve\n"
             "COMPARATIVE CFD, NOT A COOLING VALIDATION. Fan curve shape is ASSUMED (only 74.8 Pa and 186.7 m3/h are published).", fontsize=10)
ax.grid(alpha=0.3); ax.legend(fontsize=8, loc="upper right")
ax.text(0.01, 0.02, "solid fan curve = assumed stall shape, dotted = linear bracket; circles = final design, open squares = old design",
        transform=ax.transAxes, fontsize=7.5, color="#444")
fig.tight_layout(); fig.savefig(out / "operating_point.png"); plt.close(fig)

print("final: system p_fan = %.1f Q + %.3e Q^2, fit max resid %.1f %%" % (fin["sys"][0], fin["sys"][1], fin["resid"]))
for rpm in RPMS:
    print(" ", rpm, "stall %.2f CFM dp_fins %.1f" % (fin["ops"][("stall", rpm)][0] * CFM, fin["ops"][("stall", rpm)][2]),
          "linear %.2f CFM" % (fin["ops"][("linear", rpm)][0] * CFM))
if old:
    print("old: p_fan = %.1f Q + %.3e Q^2, resid %.1f %%" % (old["sys"][0], old["sys"][1], old["resid"]))
    for rpm in RPMS:
        print(" ", rpm, "%.2f CFM" % (old["ops"][("stall", rpm)][0] * CFM))
