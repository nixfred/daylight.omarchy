#!/usr/bin/env bash
# Checks the ephemeris against USNO for Atlanta on 2026-09-27 (EDT):
# sunrise 07:29, sunset 19:27, civil 07:04/19:52, moonrise 19:51, moonset 08:25.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v python3 >/dev/null || { echo "FAIL: python3 missing"; exit 1; }
TZ=America/New_York python3 bin/daylight.py --lat 33.749 --lon -84.388 --at 1790488000 | TZ=America/New_York python3 -c '
import json, sys, time
d = json.load(sys.stdin)
assert d["ok"], d
hm = lambda t: time.strftime("%H:%M", time.localtime(t))
ref = {"sunrise": "07:29", "sunset": "19:27", "civilDawn": "07:04", "civilDusk": "19:52"}
bad = 0
def chk(name, got, want):
    global bad
    g = int(got[:2]) * 60 + int(got[3:]); w = int(want[:2]) * 60 + int(want[3:])
    ok = abs(g - w) <= 2
    bad += not ok
    print(("PASS" if ok else "FAIL"), name, got, "vs USNO", want)
for k, v in ref.items(): chk(k, hm(d["today"][k]), v)
chk("moonrise", hm(d["moon"]["rise"]), "19:51")
chk("moonset", hm(d["moon"]["set"]), "08:25")
sys.exit(1 if bad else 0)
'
