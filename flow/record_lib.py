"""Record plumbing shared by the flow scripts (flow/smoke/run.sh, flow/core/synth.sh).

Invoked by path, like flow/merge_lib.py; `python3 -I` does not put the script's
directory on sys.path, so this file is a command, never an import.

ASAP7 is a predictive PDK; nothing here is fabricated or measured.

usage: record_lib.py usable <json-file>
           Exit 0 when <json-file> is a JSON object with no top-level "error",
           1 otherwise (including unreadable or non-JSON). Prints nothing.
           This is what "the klt run worked" means for these flows: drc, lvs,
           erc and sta exit non-zero for violations or not_checked and still
           report.

       record_lib.py write <dest> <subs-file>
           Read one assembled record as JSON on stdin, replace every host path
           named in <subs-file>, and write <dest> (indent=2, sorted keys,
           trailing newline). This is the only place a record file is written,
           so no record can reach flow/*/records/ without being redacted.

<subs-file> is a JSON array of "<host-path>=<tag>" strings, applied in order:
a path that is a prefix of another must come first. Write it with record_subs()
from flow/lib.sh, which is the one place the convention is spelled out.
"""
import json
import sys


def scrub(obj, subs):
    """obj with every (host path, tag) in subs replaced throughout its strings."""
    if isinstance(obj, str):
        for path, tag in subs:
            obj = obj.replace(path, tag)
        return obj
    if isinstance(obj, list):
        return [scrub(x, subs) for x in obj]
    if isinstance(obj, dict):
        return {k: scrub(v, subs) for k, v in obj.items()}
    return obj


def read_subs(path):
    return [tuple(p.split("=", 1)) for p in json.load(open(path, encoding="utf-8"))]


def usable(path):
    try:
        d = json.load(open(path, encoding="utf-8"))
    except Exception:
        return 1
    return 0 if isinstance(d, dict) and "error" not in d else 1


def write(dest, subs_file):
    rec = scrub(json.load(sys.stdin), read_subs(subs_file))
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(rec, f, indent=2, sort_keys=True)
        f.write("\n")
    return 0


def main(argv):
    if len(argv) == 3 and argv[1] == "usable":
        return usable(argv[2])
    if len(argv) == 4 and argv[1] == "write":
        return write(argv[2], argv[3])
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
