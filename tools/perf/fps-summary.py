#!/usr/bin/env python3
"""FPS summary of a MangoHud log, for the perf-port Results table.

Usage: fps-summary.py CAPTURE_DIR [--from EPOCH --to EPOCH]

Reads the MangoHud CSV in CAPTURE_DIR (named <process>_YYYY-MM-DD_HH-MM-SS.csv; MangoHud ignores output_file). When
CAPTURE_DIR/window.txt exists (written by waitprof.py) and no --from/--to is given, only the rows inside that window are
used, so the numbers cover the same seconds as the wait profile and not the loading screens. The file name gives the
log's start to the second, which is close enough for a 20 s steady window.

Prints the median and 10th-percentile FPS (p10: 90% of samples were faster) and the median / p90 frame time. MangoHud
samples every log_interval (100 ms in tools/profile-linux.sh), so p10 is a "slow stretches" number, not single-frame
hitches. The mean is not printed on purpose: see docs/linux-performance-investigation.md.
"""
import csv
import datetime
import glob
import os
import statistics
import sys


def pct(values, p):
    s = sorted(values)
    if not s:
        return float("nan")
    k = (len(s) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cap = args[0]
    start = end = None
    if "--from" in args:
        start = float(args[args.index("--from") + 1])
    if "--to" in args:
        end = float(args[args.index("--to") + 1])
    window = os.path.join(cap, "window.txt")
    if start is None and end is None and os.path.exists(window):
        kv = dict(line.strip().split("=", 1) for line in open(window) if "=" in line)
        start, end = float(kv["start_epoch"]), float(kv["end_epoch"])

    logs = [p for p in glob.glob(os.path.join(cap, "*.csv")) if os.path.basename(p) != "gpu.csv"]
    if not logs:
        print(f"no MangoHud CSV in {cap}", file=sys.stderr)
        return 1
    for log in sorted(logs):
        stem = os.path.splitext(os.path.basename(log))[0]
        try:
            log_start = datetime.datetime.strptime(stem[-19:], "%Y-%m-%d_%H-%M-%S").timestamp()
        except ValueError:
            log_start = None
        with open(log, newline="") as f:
            rows = list(csv.reader(f))
        hdr = next((i for i, r in enumerate(rows) if r and r[0] == "fps"), None)
        if hdr is None:
            print(f"{log}: no fps header", file=sys.stderr)
            continue
        cols = rows[hdr]
        i_fps, i_ft, i_el = cols.index("fps"), cols.index("frametime"), cols.index("elapsed")
        fps, ft = [], []
        for r in rows[hdr + 1:]:
            if len(r) < len(cols):
                continue
            t = None if log_start is None else log_start + float(r[i_el]) / 1e9
            if start is not None and (t is None or t < start):
                continue
            if end is not None and (t is None or t > end):
                continue
            fps.append(float(r[i_fps]))
            ft.append(float(r[i_ft]))
        scope = "selected window" if start is not None or end is not None else "whole log"
        print(f"{os.path.basename(log)} ({scope}, {len(fps)} samples)")
        if not fps:
            print("  no samples in the window (was MangoHud logging? is the log's start time right?)")
            continue
        print(f"  FPS median {statistics.median(fps):.1f}   p10 {pct(fps, 10):.1f}   min {min(fps):.1f}")
        print(f"  frame time median {statistics.median(ft):.2f} ms   p90 {pct(ft, 90):.2f} ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
