#!/usr/bin/env python3
"""Wait profile of the running game, no root needed (ported from Fable-2-Recomp tools/perf/waitprof.py).

Usage: waitprof.py OUT_DIR [SECONDS] [PROCESS_NAME]

For every game thread that uses CPU it records, over the window:
  * user / kernel CPU time (from /proc/<tid>/stat),
  * run-queue wait (time ready but not scheduled, /proc/<tid>/schedstat),
  * voluntary / involuntary context switches,
  * a 100 Hz sample of the thread state: R = running or ready, S = sleeping, D = uninterruptible.
A thread at ~1.0 core with state R ~100% is saturated: anything waiting on it waits on CPU work. High kernel time on
a game thread usually means a syscall spin (sched_yield, futex, short sleeps) or fault handling (SIGSEGV write watch).
The window's wall-clock start/end go to window.txt so fps-summary.py can cut the MangoHud log to the same seconds.
"""
import collections
import os
import subprocess
import sys
import time

out = sys.argv[1]
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
name = sys.argv[3] if len(sys.argv) > 3 else "crackdown"
# The newest matching process: a launcher restart starts a new one and the old one quits.
found = subprocess.run(["pgrep", "-n", "-x", name], capture_output=True, text=True).stdout.split()
if not found:
    sys.exit(f"no running process named {name}")
pid = int(found[0])
tck = os.sysconf("SC_CLK_TCK")


def rd(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def status_field(text, key):
    for line in text.splitlines():
        if line.startswith(key):
            return int(line.split()[1])
    return 0


def snap():
    res = {}
    for tid in os.listdir(f"/proc/{pid}/task"):
        base = f"/proc/{pid}/task/{tid}"
        stat, comm = rd(base + "/stat"), rd(base + "/comm")
        if not stat or not comm:
            continue
        f = stat[stat.rfind(")") + 2:].split()  # fields after the comm (which may hold spaces), state first
        sched = (rd(base + "/schedstat") or "0 0 0").split()
        st = rd(base + "/status") or ""
        res[tid] = dict(comm=comm.strip(), ut=int(f[11]), st=int(f[12]), wait=int(sched[1]),
                        vol=status_field(st, "voluntary_ctxt"), inv=status_field(st, "nonvoluntary_ctxt"))
    return res


a = snap()
wall0 = time.time()
t0 = time.monotonic()
states = collections.defaultdict(collections.Counter)
n = 0
while time.monotonic() - t0 < secs:
    for tid in a:
        s = rd(f"/proc/{pid}/task/{tid}/stat")
        if s:
            states[tid][s[s.rfind(")") + 2]] += 1
    n += 1
    time.sleep(0.01)
el = time.monotonic() - t0
wall1 = time.time()
b = snap()
maps_lines = len((rd(f"/proc/{pid}/maps") or "").splitlines())

rows = []
for tid, x in b.items():
    y = a.get(tid)
    if not y:
        continue
    cpu = (x["ut"] - y["ut"] + x["st"] - y["st"]) / tck / el
    if cpu < 0.03:
        continue
    sc = states[tid]
    tot = sum(sc.values()) or 1
    rows.append((cpu, x["comm"], tid,
                 (x["ut"] - y["ut"]) / tck / el, (x["st"] - y["st"]) / tck / el,
                 (x["wait"] - y["wait"]) / 1e9 / el,
                 (x["vol"] - y["vol"]) / el, (x["inv"] - y["inv"]) / el,
                 100 * sc["R"] / tot, 100 * sc["S"] / tot, 100 * sc["D"] / tot))
rows.sort(reverse=True)
total = sum(r[0] for r in rows)
lines = [f"pid={pid} window={el:.1f}s samples={n} threads>=0.03 cores: {len(rows)} total={total:.2f} cores "
         f"/proc/<pid>/maps lines={maps_lines}",
         f"{'thread':<18}{'tid':>8}{'cores':>7}{'user':>6}{'kern':>6}{'rq-wait':>8}"
         f"{'vol/s':>8}{'invol/s':>8}{'R%':>5}{'S%':>5}{'D%':>4}"]
for r in rows:
    lines.append(f"{r[1]:<18}{r[2]:>8}{r[0]:>7.2f}{r[3]:>6.2f}{r[4]:>6.2f}{r[5]:>8.3f}"
                 f"{r[6]:>8.0f}{r[7]:>8.0f}{r[8]:>5.0f}{r[9]:>5.0f}{r[10]:>4.0f}")
txt = "\n".join(lines) + "\n"
with open(os.path.join(out, "waitprof.txt"), "w") as f:
    f.write(txt)
with open(os.path.join(out, "window.txt"), "w") as f:
    f.write(f"pid={pid}\nstart_epoch={wall0:.3f}\nend_epoch={wall1:.3f}\n")
print(txt)
