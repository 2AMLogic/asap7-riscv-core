# spec

ASAP7 is a predictive PDK; this block is layout, DRC and timing only and is never fabricated.

- [`core.md`](core.md) — the ratified target specification (rows ratified or deferred)
- [`core.rows.json`](core.rows.json) — machine-readable listing of the `core.md` target table (adds no row)
- [`statistical-rows.json`](statistical-rows.json) — hash-bound statement that no ratified row is statistical (T1 item 6)
- [`pdk-bringup.md`](pdk-bringup.md) — pins, what resolves under `klt`, DRC deck and LVS coverage, Liberty corner headers
- [`decisions/`](decisions/) — one record per decision (0001–0008)
