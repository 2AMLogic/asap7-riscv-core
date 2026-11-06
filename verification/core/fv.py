"""Run the riscv-arch-test suite through `klt functional-verification`.

Usage: python fv.py <out-dir> [--negative-control]

Needs verification/core/setup.sh to have run. Converts the pinned CVE2 closure
(shared with runner.py via archtest_common.py), builds tests/signatures with build_tests.py,
then for each program writes verification/core/fv-request.json-shaped request
(<out-dir>/requests/<test>.json) and runs `klt functional-verification` on it.
klt requests carry no plusargs, so the program image and tohost address are
passed to tb_core.v as -D macros (HEX_FILE, TOHOST_HEX). Writes
<out-dir>/report.json: the per-test klt JSON responses plus per-test totals.
Exit 0 iff every test passed (with --negative-control only the first test runs,
one expected signature word is flipped, and the run is expected to fail).
"""

import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # fv.sh runs this with -I, which drops the script dir

from archtest_common import prepare  # noqa: E402
KLT = os.environ.get("KLT_CMD", "klt").split()



def request(name, meta, tests_dir, converted):
    return {
        "sources": [str(converted), str(HERE / "tb_core.v")],
        "hdl_toplevel": "tb_core",
        "engine": "icarus",
        "testbench": {"module": "test_archtest", "search_path": str(HERE)},
        "options": {
            "build_args": ["-g2012"],
            "defines": {"HEX_FILE": str(tests_dir / (name + ".hex")),
                        "TOHOST_HEX": f"{meta['tohost']:x}"},
        },
    }


def main(out: Path, negative: bool) -> int:
    tests_dir, names, converted = prepare(out, negative)
    (out / "requests").mkdir(exist_ok=True)

    results, failed = [], 0
    for n in names:
        meta = json.loads((tests_dir / f"{n}.json").read_text())
        req_path = out / "requests" / f"{n}.json"
        req_path.write_text(json.dumps(request(n, meta, tests_dir, converted), indent=2))
        env = dict(os.environ, ARCHTEST_JSON=str(tests_dir / f"{n}.json"),
                   CORE_NEGATIVE_CONTROL="1" if negative else "0")
        proc = subprocess.run(
            [*KLT, "functional-verification", str(req_path), "-o", str(out / "artifacts" / n),
             "--format", "json"], env=env, capture_output=True, text=True)
        try:
            resp = json.loads(proc.stdout)
        except json.JSONDecodeError:
            resp = {"status": "error", "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-2000:]}
        ok = proc.returncode == 0
        failed += not ok
        print(f"{'PASS' if ok else 'FAIL'} {n}", flush=True)
        results.append({"test": n, "exit_code": proc.returncode, "response": resp})

    report = {"suite": "riscv-arch-test", "negative_control": negative,
              "tests_run": len(names), "tests_failed": failed,
              "excluded": json.loads((HERE / "excluded.json").read_text()),
              "results": results}
    (out / "report.json").write_text(json.dumps(report, indent=2))
    print(f"klt functional-verification: {len(names)} test(s), {failed} failed; {out / 'report.json'}")
    return 1 if failed or not names else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]).resolve(), "--negative-control" in sys.argv[2:]))
