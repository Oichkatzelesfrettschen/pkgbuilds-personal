"""Summarize fio-sched-ab.sh output: median (min-max) per scheduler, deltas vs baseline."""

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

WORKLOADS = ["rr4k_qd1", "rr4k_hi", "sr128k", "mix4k", "rw4k_hi"]


def load(path: Path) -> dict:
    job = json.loads(path.read_text())["jobs"][0]
    out = {}
    for side in ("read", "write"):
        d = job[side]
        pct = d["clat_ns"].get("percentile", {})
        out[side] = {
            "iops": d["iops"],
            "bw_mib": d["bw_bytes"] / 2**20,
            "p50_us": pct.get("50.000000", 0) / 1000,
            "p99_us": pct.get("99.000000", 0) / 1000,
            "p999_us": pct.get("99.900000", 0) / 1000,
        }
    return out


def main(outdir: Path) -> None:
    baseline = dict(
        line.split() for line in (outdir / "schedulers.orig").read_text().splitlines()
    )
    runs = defaultdict(list)  # (target, wl, sched) -> [metrics]
    for p in sorted(outdir.glob("*.json")):
        target, sched, _rep, wl = p.stem.split(".", 3)
        try:
            runs[(target, wl, sched)].append(load(p))
        except (ValueError, KeyError, IndexError):
            print(
                f"skipped unreadable result {p.name} (job still running or failed)",
                file=sys.stderr,
            )

    targets = sorted({k[0] for k in runs})
    for target in targets:
        print(f"\n## {target} (baseline scheduler: {baseline.get(target, '?')})\n")
        for wl in WORKLOADS:
            scheds = sorted({k[2] for k in runs if k[0] == target and k[1] == wl})
            if not scheds:
                continue
            mixed = wl == "mix4k"
            print(f"### {wl}\n")
            hdr = "| scheduler | reps | read IOPS med (min-max) | read MiB/s | read p99 us | "
            hdr += "write IOPS med (min-max) | write p99 us |"
            print(hdr)
            print("|---|---|---|---|---|---|---|")
            base = baseline.get(target)
            ref = None
            if base in scheds:
                ref = {
                    "r": statistics.median(
                        m["read"]["iops"] for m in runs[(target, wl, base)]
                    ),
                    "w": statistics.median(
                        m["write"]["iops"] for m in runs[(target, wl, base)]
                    ),
                }
            for s in scheds:
                ms = runs[(target, wl, s)]
                row = [s, str(len(ms))]
                for side in ("read", "write"):
                    iops = [m[side]["iops"] for m in ms]
                    med = statistics.median(iops)
                    cell = f"{med:,.0f} ({min(iops):,.0f}-{max(iops):,.0f})"
                    if ref and s != base and ref["r" if side == "read" else "w"] > 0:
                        pct = 100 * (med / ref["r" if side == "read" else "w"] - 1)
                        base_iops = [m[side]["iops"] for m in runs[(target, wl, base)]]
                        sep = min(iops) > max(base_iops) or max(iops) < min(base_iops)
                        cell += f" {pct:+.1f}%{'*' if sep else ''}"
                    row.append(cell)
                    if side == "read":
                        row.append(
                            f"{statistics.median(m['read']['bw_mib'] for m in ms):,.0f}"
                        )
                    p99 = statistics.median(m[side]["p99_us"] for m in ms)
                    row.append(
                        f"{p99:,.0f}"
                        if (side == "read" or mixed or wl == "rw4k_hi")
                        else "-"
                    )
                print("| " + " | ".join(row) + " |")
            print()
    print("\n`*` = min-max range does not overlap the baseline scheduler's range.")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
