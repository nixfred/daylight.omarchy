#!/usr/bin/env python3
"""Daylight ephemeris: sun and moon for one place, computed locally.

Python 3 stdlib only, no network. Prints one JSON object on stdout.

Sun: NOAA solar calculator equations (Meeus-based, the same maths as the
NOAA spreadsheet), with the standard -0.833 deg horizon for rise/set.
Moon: Meeus ch. 47 low-precision position (for altitude and rise/set),
Meeus ch. 48 illuminated fraction, Meeus ch. 49 true phase times.

Usage: daylight.py [--lat 33.749] [--lon -84.388] [--place Atlanta]
                   [--config FILE] [--at EPOCH]
Location precedence: CLI args > config file > Atlanta default.
"""
import argparse
import datetime as dt
import json
import math
import os
import sys

DEFAULT = {"lat": 33.749, "lon": -84.388, "place": "Atlanta, GA"}
CONFIG = os.path.expanduser("~/.config/daylight/location.json")

RAD = math.pi / 180.0
DEG = 180.0 / math.pi


# ----------------------------------------------------------------- time
def jd_from_epoch(t):
    return t / 86400.0 + 2440587.5


def epoch_from_jd(jd):
    return (jd - 2440587.5) * 86400.0


# ----------------------------------------------------------------- sun (NOAA)
def sun_position(t, lat, lon):
    """Return (elevation_deg_refracted, azimuth_deg, declination_deg, eqtime_min)."""
    jc = (jd_from_epoch(t) - 2451545.0) / 36525.0
    l0 = (280.46646 + jc * (36000.76983 + jc * 0.0003032)) % 360.0
    m = 357.52911 + jc * (35999.05029 - 0.0001537 * jc)
    e = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
    c = (math.sin(m * RAD) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
         + math.sin(2 * m * RAD) * (0.019993 - 0.000101 * jc)
         + math.sin(3 * m * RAD) * 0.000289)
    true_long = l0 + c
    omega = 125.04 - 1934.136 * jc
    app_long = true_long - 0.00569 - 0.00478 * math.sin(omega * RAD)
    eps0 = 23 + (26 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60) / 60
    eps = eps0 + 0.00256 * math.cos(omega * RAD)
    decl = math.asin(math.sin(eps * RAD) * math.sin(app_long * RAD)) * DEG
    y = math.tan(eps / 2 * RAD) ** 2
    eqt = 4 * DEG * (y * math.sin(2 * l0 * RAD) - 2 * e * math.sin(m * RAD)
                     + 4 * e * y * math.sin(m * RAD) * math.cos(2 * l0 * RAD)
                     - 0.5 * y * y * math.sin(4 * l0 * RAD)
                     - 1.25 * e * e * math.sin(2 * m * RAD))
    utc_min = (t % 86400.0) / 60.0
    tst = (utc_min + eqt + 4 * lon) % 1440.0
    ha = tst / 4 - 180 if tst / 4 >= 0 else tst / 4 + 180
    zen = math.acos(max(-1.0, min(1.0,
        math.sin(lat * RAD) * math.sin(decl * RAD)
        + math.cos(lat * RAD) * math.cos(decl * RAD) * math.cos(ha * RAD)))) * DEG
    elev = 90 - zen
    # NOAA refraction approximation
    if elev > 85:
        refr = 0.0
    elif elev > 5:
        te = math.tan(elev * RAD)
        refr = 58.1 / te - 0.07 / te ** 3 + 0.000086 / te ** 5
    elif elev > -0.575:
        refr = 1735 + elev * (-518.2 + elev * (103.4 + elev * (-12.79 + elev * 0.711)))
    else:
        refr = -20.772 / math.tan(elev * RAD)
    elev_r = elev + refr / 3600.0
    az_den = math.cos(lat * RAD) * math.sin(zen * RAD)
    if abs(az_den) > 1e-9:
        v = ((math.sin(lat * RAD) * math.cos(zen * RAD)) - math.sin(decl * RAD)) / az_den
        v = max(-1.0, min(1.0, v))
        az = math.acos(v) * DEG
        az = (az + 180) % 360 if ha > 0 else (540 - az) % 360
    else:
        az = 180.0 if lat > 0 else 0.0
    return elev, elev_r, az, decl, eqt


def sun_geo_elev(t, lat, lon):
    return sun_position(t, lat, lon)[0]


# ----------------------------------------------------------------- moon (Meeus 47, truncated)
def moon_ecliptic(t):
    T = (jd_from_epoch(t) - 2451545.0) / 36525.0
    Lp = 218.3164477 + 481267.88123421 * T
    D = 297.8501921 + 445267.1114034 * T
    M = 357.5291092 + 35999.0502909 * T
    Mp = 134.9633964 + 477198.8675055 * T
    F = 93.2720950 + 483202.0175233 * T
    r = lambda a: math.sin(a * RAD)
    lon = (Lp + 6.288774 * r(Mp) + 1.274027 * r(2 * D - Mp) + 0.658314 * r(2 * D)
           + 0.213618 * r(2 * Mp) - 0.185116 * r(M) - 0.114332 * r(2 * F)
           + 0.058793 * r(2 * D - 2 * Mp) + 0.057066 * r(2 * D - M - Mp)
           + 0.053322 * r(2 * D + Mp) + 0.045758 * r(2 * D - M)
           - 0.040923 * r(M - Mp) - 0.034720 * r(D) - 0.030383 * r(M + Mp))
    lat = (5.128122 * r(F) + 0.280602 * r(Mp + F) + 0.277693 * r(Mp - F)
           + 0.173237 * r(2 * D - F) + 0.055413 * r(2 * D - Mp + F)
           + 0.046271 * r(2 * D - Mp - F))
    dist = (385000.56 - 20905.355 * math.cos(Mp * RAD) - 3699.111 * math.cos((2 * D - Mp) * RAD)
            - 2955.968 * math.cos(2 * D * RAD) - 569.925 * math.cos(2 * Mp * RAD))
    return lon % 360.0, lat, dist, T


def moon_alt(t, lat, lon):
    lam, beta, dist, T = moon_ecliptic(t)
    eps = 23.439291 - 0.0130042 * T
    ra = math.atan2(math.sin(lam * RAD) * math.cos(eps * RAD) - math.tan(beta * RAD) * math.sin(eps * RAD),
                    math.cos(lam * RAD))
    dec = math.asin(math.sin(beta * RAD) * math.cos(eps * RAD)
                    + math.cos(beta * RAD) * math.sin(eps * RAD) * math.sin(lam * RAD))
    jd = jd_from_epoch(t)
    gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0)) % 360.0
    H = (gmst + lon) * RAD - ra
    alt = math.asin(math.sin(lat * RAD) * math.sin(dec) + math.cos(lat * RAD) * math.cos(dec) * math.cos(H))
    return alt * DEG, dist


def moon_illum(t):
    """Illuminated fraction and phase angle age (0..1 of synodic, waxing < 0.5)."""
    lam, beta, dist, T = moon_ecliptic(t)
    # Sun apparent longitude (NOAA)
    jc = T
    l0 = (280.46646 + jc * 36000.76983) % 360.0
    m = 357.52911 + jc * 35999.05029
    c = 1.914602 * math.sin(m * RAD) + 0.019993 * math.sin(2 * m * RAD)
    slon = (l0 + c) % 360.0
    elong = math.acos(math.cos(beta * RAD) * math.cos((lam - slon) * RAD))
    R = 149598000.0
    i = math.atan2(R * math.sin(elong), dist - R * math.cos(elong))
    k = (1 + math.cos(i)) / 2
    age = ((lam - slon) % 360.0) / 360.0
    return k, age


# ----------------------------------------------------------------- moon phases (Meeus 49)
def true_phase_jde(k):
    T = k / 1236.85
    jde = (2451550.09766 + 29.530588861 * k + 0.00015437 * T * T
           - 0.000000150 * T ** 3 + 0.00000000073 * T ** 4)
    E = 1 - 0.002516 * T - 0.0000074 * T * T
    M = (2.5534 + 29.10535670 * k - 0.0000014 * T * T) * RAD
    Mp = (201.5643 + 385.81693528 * k + 0.0107582 * T * T) * RAD
    F = (160.7108 + 390.67050284 * k - 0.0016118 * T * T) * RAD
    Om = (124.7746 - 1.56375588 * k + 0.0020672 * T * T) * RAD
    s = math.sin
    frac = round((k - math.floor(k)) * 4) / 4.0
    if frac == 0.0:  # new
        corr = (-0.40720 * s(Mp) + 0.17241 * E * s(M) + 0.01608 * s(2 * Mp) + 0.01039 * s(2 * F)
                + 0.00739 * E * s(Mp - M) - 0.00514 * E * s(Mp + M) + 0.00208 * E * E * s(2 * M)
                - 0.00111 * s(Mp - 2 * F) - 0.00057 * s(Mp + 2 * F) + 0.00056 * E * s(2 * Mp + M)
                - 0.00042 * s(3 * Mp) + 0.00042 * E * s(M + 2 * F) + 0.00038 * E * s(M - 2 * F)
                - 0.00024 * E * s(2 * Mp - M) - 0.00017 * s(Om))
    else:  # full
        corr = (-0.40614 * s(Mp) + 0.17302 * E * s(M) + 0.01614 * s(2 * Mp) + 0.01043 * s(2 * F)
                + 0.00734 * E * s(Mp - M) - 0.00515 * E * s(Mp + M) + 0.00209 * E * E * s(2 * M)
                - 0.00111 * s(Mp - 2 * F) - 0.00057 * s(Mp + 2 * F) + 0.00056 * E * s(2 * Mp + M)
                - 0.00042 * s(3 * Mp) + 0.00042 * E * s(M + 2 * F) + 0.00038 * E * s(M - 2 * F)
                - 0.00024 * E * s(2 * Mp - M) - 0.00017 * s(Om))
    return jde + corr


def next_phase(t, offset):
    """offset 0 = new, 0.5 = full. Returns epoch of the next one after t."""
    year = 2000 + (jd_from_epoch(t) - 2451545.0) / 365.25
    k = math.floor((year - 2000) * 12.3685) + offset - 1
    while True:
        e = epoch_from_jd(true_phase_jde(k)) - 69.0  # TT -> UT (dT ~ 69 s)
        if e > t:
            return e
        k += 1


# ----------------------------------------------------------------- event search
def crossings(fn, t0, t1, level, step=300.0):
    """All times in [t0,t1) where fn crosses level; ('up'|'down', t)."""
    out = []
    prev_t = t0
    prev = fn(t0) - level
    t = t0 + step
    while t <= t1:
        cur = fn(t) - level
        if (prev < 0) != (cur < 0):
            a, b, fa = prev_t, t, prev
            for _ in range(30):
                mid = (a + b) / 2
                fm = fn(mid) - level
                if (fa < 0) != (fm < 0):
                    b = mid
                else:
                    a, fa = mid, fm
            out.append(("up" if prev < 0 else "down", (a + b) / 2))
        prev_t, prev = t, cur
        t += step
    return out


def first(lst, kind):
    for k, t in lst:
        if k == kind:
            return t
    return None


def local_midnight(t):
    d = dt.datetime.fromtimestamp(t).astimezone()
    m = d.replace(hour=0, minute=0, second=0, microsecond=0)
    return m.timestamp()


def sun_day(mid, lat, lon):
    end = mid + 86400
    f = lambda x: sun_geo_elev(x, lat, lon)
    def pair(level):
        c = crossings(f, mid, end, level)
        return first(c, "up"), first(c, "down")
    rise, sset = pair(-0.833)
    civ = pair(-6.0)
    nau = pair(-12.0)
    ast = pair(-18.0)
    gold = pair(6.0)
    blue = pair(-4.0)
    # solar noon: max elevation
    best_t, best_e = mid, -99
    t = mid
    while t < end:
        e = f(t)
        if e > best_e:
            best_t, best_e = t, e
        t += 300
    a, b = best_t - 300, best_t + 300
    for _ in range(40):
        m1, m2 = a + (b - a) / 3, b - (b - a) / 3
        if f(m1) < f(m2):
            a = m1
        else:
            b = m2
    noon = (a + b) / 2
    length = (sset - rise) if (rise and sset) else (86400.0 if f(noon) > 0 else 0.0)
    return {
        "sunrise": rise, "sunset": sset, "noon": noon, "noonElev": round(f(noon), 2),
        "civilDawn": civ[0], "civilDusk": civ[1],
        "nauticalDawn": nau[0], "nauticalDusk": nau[1],
        "astroDawn": ast[0], "astroDusk": ast[1],
        # Golden hour: sun between -4 and +6 deg. Blue hour: -6 to -4 deg.
        "goldenAmEnd": gold[0], "goldenPmStart": gold[1],
        "blueAmEnd": blue[0], "bluePmStart": blue[1],
        "dayLength": length,
    }


def rnd(v):
    return None if v is None else int(round(v))


def load_location(args):
    loc = dict(DEFAULT)
    src = "default"
    path = os.path.expanduser(args.config) if args.config else CONFIG
    try:
        with open(path) as fh:
            d = json.load(fh)
        for k in ("lat", "lon", "place"):
            if k in d:
                loc[k] = d[k]
        src = path
    except FileNotFoundError:
        pass
    except Exception as exc:  # fail loudly but keep going on defaults
        sys.stderr.write("daylight: bad config %s: %s\n" % (path, exc))
        src = "default (config unreadable)"
    if args.lat is not None and args.lon is not None:
        loc["lat"], loc["lon"] = args.lat, args.lon
        src = "settings"
    if args.place:
        loc["place"] = args.place
    loc["lat"], loc["lon"] = float(loc["lat"]), float(loc["lon"])
    if not (-90 <= loc["lat"] <= 90 and -180 <= loc["lon"] <= 180):
        raise SystemExit("daylight: lat/lon out of range")
    loc["source"] = src
    return loc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lat", type=float)
    ap.add_argument("--lon", type=float)
    ap.add_argument("--place")
    ap.add_argument("--config")
    ap.add_argument("--at", type=float, help="epoch seconds (testing)")
    args = ap.parse_args()
    loc = load_location(args)
    lat, lon = loc["lat"], loc["lon"]
    now = args.at if args.at else dt.datetime.now().timestamp()
    mid = local_midnight(now)
    today = sun_day(mid, lat, lon)
    yest = sun_day(local_midnight(mid - 43200), lat, lon)
    tomo = sun_day(local_midnight(mid + 129600), lat, lon)

    _, elev, az, decl, eqt = sun_position(now, lat, lon)

    # next sun event (rise or set) for the bar countdown
    events = []
    for d in (today, tomo):
        if d["sunrise"]:
            events.append(("sunrise", d["sunrise"]))
        if d["sunset"]:
            events.append(("sunset", d["sunset"]))
    nxt = next(((k, t) for k, t in sorted(events, key=lambda e: e[1]) if t > now), (None, None))

    # arc samples: elevation every 10 minutes over the local day
    arc = [round(sun_geo_elev(mid + i * 600, lat, lon), 2) for i in range(145)]

    # moon
    illum, age = moon_illum(now)
    malt, mdist = moon_alt(now, lat, lon)
    mf = lambda x: moon_alt(x, lat, lon)[0] - 0.125  # 0.7275*parallax - 34'
    mc = crossings(mf, mid, mid + 2 * 86400, 0.0, step=600)
    moonrise = next((t for k, t in mc if k == "up" and t > mid), None)
    moonset = next((t for k, t in mc if k == "down" and t > mid), None)
    nr = next((t for k, t in mc if k == "up" and t > now), None)
    ns = next((t for k, t in mc if k == "down" and t > now), None)
    names = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
             "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
    # Principal phases are instants; name them only within ~12 h (matches USNO naming).
    near = 0.5 / 29.530588
    phase_name = None
    for idx, centre in ((0, 0.0), (2, 0.25), (4, 0.5), (6, 0.75)):
        dist = min(abs(age - centre), 1 - abs(age - centre))
        if dist < near:
            phase_name = names[idx]
    if phase_name is None:
        phase_name = names[1 + 2 * int(age * 4)]
    illum_y, _ = moon_illum(now - 86400)

    out = {
        "ok": True,
        "generated": int(now),
        "place": loc["place"], "lat": lat, "lon": lon, "locationSource": loc["source"],
        "tz": dt.datetime.fromtimestamp(now).astimezone().strftime("%Z"),
        "sun": {
            "elevation": round(elev, 2), "azimuth": round(az, 1),
            "declination": round(decl, 2), "eqTimeMin": round(eqt, 2),
            "up": elev > -0.833,
            "next": nxt[0], "nextAt": rnd(nxt[1]),
        },
        "today": {k: (rnd(v) if k not in ("noonElev",) else v) for k, v in today.items()},
        "yesterday": {"sunrise": rnd(yest["sunrise"]), "sunset": rnd(yest["sunset"]),
                      "dayLength": rnd(yest["dayLength"])},
        "tomorrow": {"sunrise": rnd(tomo["sunrise"]), "sunset": rnd(tomo["sunset"]),
                     "dayLength": rnd(tomo["dayLength"])},
        "dayDelta": rnd(today["dayLength"] - yest["dayLength"]),
        "dayDeltaTomorrow": rnd(tomo["dayLength"] - today["dayLength"]),
        "midnight": int(mid),
        "arc": arc,
        "moon": {
            "illumination": round(illum, 4), "illumYesterday": round(illum_y, 4),
            "age": round(age, 4), "ageDays": round(age * 29.530588, 2),
            "phase": phase_name, "waxing": age < 0.5,
            "altitude": round(malt, 2), "distanceKm": int(mdist),
            "rise": rnd(moonrise), "set": rnd(moonset),
            "nextRise": rnd(nr), "nextSet": rnd(ns),
            "nextFull": rnd(next_phase(now, 0.5)), "nextNew": rnd(next_phase(now, 0.0)),
        },
    }
    json.dump(out, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        json.dump({"ok": False, "error": "%s: %s" % (type(exc).__name__, exc)}, sys.stdout)
        sys.stdout.write("\n")
        sys.exit(1)
