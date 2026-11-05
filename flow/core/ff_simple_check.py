#!/usr/bin/env python3
"""Evidence for the SIMPLE RVT FF Liberty anomaly (spec/pdk-bringup.md section 5).

Reads the extracted RVT FF/TT/SS Liberty files of the five asap7sc7p5t_28
groups (AO, OA, INVBUF, SEQ, SIMPLE) and writes a JSON record that

  1. quotes nom_voltage / nom_temperature / operating_conditions of every file;
  2. compares SIMPLE FF delay tables with SIMPLE TT and SS, and compares the
     FF/TT and SS/TT delay ratios of the correctly labelled INVBUF and AO groups;
  3. states which explanation the numbers support.

Run it through flow/core/ff_simple_check.sh, which checks the pin, extracts the
.7z archives and picks the record directory. ASAP7 is a predictive PDK; every
number here is a ratio of predicted table values, not a measurement.

usage: ff_simple_check.py <dir-with-extracted-libs> <out.json>
"""
import json
import re
import statistics
import sys
from pathlib import Path

GROUPS = ["AO", "OA", "INVBUF", "SEQ", "SIMPLE"]
CORNERS = ["FF", "TT", "SS"]
REF_GROUPS = ["INVBUF", "AO"]  # headers are correct (0.77 V / 0 C for FF)
# Fixed SIMPLE cells reported in detail.
SIMPLE_CELLS = ["NAND2xp5", "NOR2xp33", "AND2x2", "XOR2xp5", "MAJx2"]
# (slew index, load index) points compared by position; grids are checked equal.
POINTS = [(1, 1), (3, 3), (5, 5)]

# Verdict thresholds (absolute, on the median FF/TT delay ratio).
TT_LIKE_BAND = 0.02   # |r_simple - 1| <= this: tables are TT-like
FF_LIKE_BAND = 0.05   # |r_simple - r_ref| <= this: tables follow the FF/TT ratio of the ref groups
MIN_REF_GAP = 0.05    # the reference FF/TT ratio must sit at least this far below 1


def parse(path):
    text = Path(path).read_text()
    hdr = {}
    for key in ("nom_voltage", "nom_temperature", "default_operating_conditions"):
        m = re.search(rf"^\s*{key}\s*:\s*([^;]+);", text, re.M)
        hdr[key] = m.group(1).strip() if m else None
    m = re.search(r"operating_conditions\s*\(\s*(\w+)\s*\)\s*\{(.*?)\}", text, re.S)
    if m:
        hdr["operating_conditions"] = m.group(1)
        for key in ("voltage", "temperature"):
            mm = re.search(rf"{key}\s*:\s*([^;]+);", m.group(2))
            hdr["oc_" + key] = mm.group(1).strip() if mm else None
    # cells -> ordered list of (kind, idx1, idx2, matrix)
    cells = {}
    for cm in re.finditer(r"^\s*cell\s*\(\s*(\w+)\s*\)\s*\{", text, re.M):
        cells[cm.group(1)] = cm.start()
    names = list(cells)
    starts = [cells[n] for n in names] + [len(text)]
    tabs = {}
    for i, n in enumerate(names):
        body = text[starts[i]:starts[i + 1]]
        out = []
        for tm in re.finditer(r"\b(cell_rise|cell_fall)\s*\(\s*\w+\s*\)\s*\{(.*?)\}", body, re.S):
            t = tm.group(2)
            i1 = [float(x) for x in re.search(r'index_1\s*\(\s*"([^"]*)"', t).group(1).split(",")]
            i2 = [float(x) for x in re.search(r'index_2\s*\(\s*"([^"]*)"', t).group(1).split(",")]
            vm = re.search(r"values\s*\((.*?)\)\s*;", t, re.S).group(1)
            rows = [[float(x) for x in r.split(",")] for r in re.findall(r'"([^"]*)"', vm)]
            out.append((tm.group(1), i1, i2, rows))
        tabs[n] = out
    return hdr, tabs


def ratios(num, den, cells=None):
    """Delay ratios num/den at POINTS over every matching table; also grid check."""
    rs, grid_ok, missing, n_tables = [], True, [], 0
    for c, dt in den.items():
        if cells is not None and c not in cells:
            continue
        nt = num.get(c)
        if nt is None or len(nt) != len(dt):
            missing.append(c)
            continue
        for (k1, a1, a2, r1), (k2, b1, b2, r2) in zip(nt, dt):
            if k1 != k2:
                missing.append(c)
                break
            if (a1, a2) != (b1, b2):
                grid_ok = False
            n_tables += 1
            for (i, j) in POINTS:
                if r2[i][j] > 0:
                    rs.append(r1[i][j] / r2[i][j])
    return {
        "median": round(statistics.median(rs), 4) if rs else None,
        "min": round(min(rs), 4) if rs else None,
        "max": round(max(rs), 4) if rs else None,
        "n_samples": len(rs),
        "n_tables": n_tables,
        "grids_identical": grid_ok,
        "cells_missing_or_mismatched": sorted(set(missing)),
    }


def main(libdir, out):
    libdir = Path(libdir)
    files, data = {}, {}
    for g in GROUPS:
        for c in CORNERS:
            found = sorted(libdir.glob(f"asap7sc7p5t_{g}_RVT_{c}_nldm_*.lib"))
            if len(found) != 1:
                sys.exit(f"ff_simple_check: expected one {g} {c} lib in {libdir}, found {len(found)}")
            hdr, tabs = parse(found[0])
            files[f"{g}_{c}"] = {"file": found[0].name, **hdr, "n_cells": len(tabs)}
            data[(g, c)] = tabs

    cmp = {}
    for g in GROUPS:
        cmp[g] = {
            "FF_over_TT": ratios(data[(g, "FF")], data[(g, "TT")]),
            "SS_over_TT": ratios(data[(g, "SS")], data[(g, "TT")]),
        }
    simple_cells = {}
    for cell in SIMPLE_CELLS:
        name = f"{cell}_ASAP7_75t_R"
        simple_cells[name] = {
            "FF_over_TT": ratios(data[("SIMPLE", "FF")], data[("SIMPLE", "TT")], {name}),
            "SS_over_TT": ratios(data[("SIMPLE", "SS")], data[("SIMPLE", "TT")], {name}),
        }
    # identical-body test: does SIMPLE FF equal SIMPLE TT table-for-table?
    identical = all(
        a[1:] == b[1:]
        for c, dt in data[("SIMPLE", "TT")].items()
        for a, b in zip(data[("SIMPLE", "FF")].get(c, []), dt)
    )

    r_s = cmp["SIMPLE"]["FF_over_TT"]["median"]
    r_ref = statistics.median([cmp[g]["FF_over_TT"]["median"] for g in REF_GROUPS])
    s_s = cmp["SIMPLE"]["SS_over_TT"]["median"]
    s_ref = statistics.median([cmp[g]["SS_over_TT"]["median"] for g in REF_GROUPS])
    if abs(r_s - 1) <= TT_LIKE_BAND and (1 - r_ref) >= MIN_REF_GAP:
        verdict = "TT-like tables"
    elif abs(r_s - r_ref) <= FF_LIKE_BAND and (1 - r_ref) >= MIN_REF_GAP:
        verdict = "FF tables with a wrong header"
    else:
        verdict = "inconclusive"
    rec = {
        "schema_version": 1,
        "note": "predicted (ASAP7 is a predictive PDK); ratios of Liberty NLDM delay-table values, not measurements",
        "points_index_pairs": POINTS,
        "thresholds": {
            "tt_like_band": TT_LIKE_BAND, "ff_like_band": FF_LIKE_BAND, "min_ref_gap": MIN_REF_GAP,
            "rule": "TT-like if |r_simple-1|<=tt_like_band; FF-with-wrong-header if |r_simple-r_ref|<=ff_like_band; both need 1-r_ref>=min_ref_gap; else inconclusive",
        },
        "headers": files,
        "ratios_by_group": cmp,
        "simple_cells": simple_cells,
        "simple_FF_tables_identical_to_TT": identical,
        "summary": {
            "simple_FF_over_TT_median": r_s,
            "reference_FF_over_TT_median": r_ref,
            "reference_groups": REF_GROUPS,
            "simple_SS_over_TT_median": s_s,
            "reference_SS_over_TT_median": s_ref,
            "simple_share_of_reference_ff_speedup": round((1 - r_s) / (1 - r_ref), 3),
            "verdict": verdict,
            "reading": (
                "SIMPLE FF/TT is share_of_reference_ff_speedup of the way from TT (0) to the "
                "reference FF/TT (1). A share near 0 means TT data, near 1 means FF data; a "
                "value between them fits neither stated explanation and is reported as inconclusive "
                "(e.g. FF-process tables run at the TT voltage/temperature in the header would land here)."
            ),
        },
    }
    Path(out).write_text(json.dumps(rec, indent=2, sort_keys=True) + "\n")
    print(f"verdict: {verdict} (SIMPLE FF/TT {r_s}, reference FF/TT {r_ref})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
