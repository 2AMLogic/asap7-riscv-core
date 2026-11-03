"""Merge ASAP7 per-cell-group Liberty files into one library.

usage: merge_lib.py <out.lib> <library-name> <in.lib>...

The header (everything before the first `cell (`) comes from the first input in
sorted order, with its library name replaced; the cells of every input follow.
Sorting happens here so callers need not agree on a shell locale.
"""
import re
import sys

out, name, *files = sys.argv[1:]
header, cells = None, []
for i, f in enumerate(sorted(files)):
    t = open(f, encoding="utf-8").read()
    m = re.search(r"^\s*cell\s*\(", t, re.M)
    if i == 0:
        header = re.sub(r"library\s*\([^)]*\)", "library (%s)" % name, t[: m.start()], count=1)
    body = t[m.start():].rstrip()
    assert body.endswith("}")
    cells.append(body[:-1].rstrip() + "\n")
open(out, "w", encoding="utf-8").write(header + "".join(cells) + "}\n")
