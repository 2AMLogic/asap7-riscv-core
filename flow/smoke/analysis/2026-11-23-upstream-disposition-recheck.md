# Upstream-disposition recheck: the #4508 and #7001 closures vs the pinned 0.9.0 results (issue #245)

`flow/smoke/analysis/2026-11-21-drc.md` attributed the 44 residual DRC
markers of record `flow/smoke/records/2026-11-21/` to upstream issues,
citing klayout-tools #6909 (35 PDN-stack markers), #4508 (3 router
via-pad tips) and #7001 (the `power.preset` refusal behind the explicit
straps). Both #4508 and #7001 closed on 2026-11-22, one to two days after
that addendum was written — its dated text stays as-is (append-only
evidence). This note re-checks, by measurement, what the two closures
change for this repo at the pinned `klt` 0.9.0, and refreshes the
current-state text in `README.md` and `ROADMAP.md`. It changes no earlier
evidence: every record directory is untouched.

**ASAP7 is a predictive PDK; nothing here is fabricated or measured.**
Every number below is a tool result against the pinned deck
(`sha256:14f146f02cd731de3e0b59452eadfdab9c2c947724a219a1002a31b5e0f12d13`,
267 categories) — the same pin as the 2026-11-21 record.

## Upstream state, measured 2026-11-23 (`gh api`)

| Issue | Addendum said | Now | Closed by |
|---|---|---|---|
| #6909 (PDN via stack, 35 markers) | open | **open** | — |
| #4508 (router M1 pad tips, 3 markers) | open | **closed** 2026-11-22T00:57:30Z | PR #7142 "Repair opposing ASAP7 M1 landing pads without reducing cut coverage", merged 2026-11-22T04:50:34Z (`5b02378e`) |
| #7001 (`power.preset` refuses `asap7sc7p5t_28_R`) | open | **closed** 2026-11-22T20:45:54Z | PR #7231 "Accept the ASAP7 RVT descriptor name for PDN and parasitics", merged 2026-11-22T20:45:53Z (`d7751618`) |

The newest klayout-tools release, `v0.9.2` (2026-11-15T20:16Z), **predates
both merges**: no released klt carries either fix. Upstream #6930 tracks
cutting a `v0.9.3` tag. #7012 — the number the earlier settings comment on
#28 cited for the preset refusal — redirects to #7001 in its closing
comment; #7001 is the canonical citation.

All probes below ran locally, single-run, in scratch (`/tmp`), per the
issue's champion note. No grids, no records written.

## Probe 1 — DRC replay at the pin: the measured 0.9.0 baseline stands

The DRC step of `flow/smoke/run.sh`, replayed on the committed counter GDS:

```bash
uvx --from "klayout-tools==0.9.0" klt drc --engine klayout \
  --deck-file asap7.drc --expect-rule-categories 267 --format json \
  flow/smoke/records/2026-11-21/layout/counter.gds
```

Status `violations`, 44 markers, per-rule counts byte-equal to the
committed `drc.json`: `M1.S.4` 1, `M1.S.5` 2, `SDT.ACTIVE.AUX.2` 6,
`V4.M4.EN.1` 28, `V4.M5.EN.2` 7; deck hash equal to the pin. The replay's
uvx environment resolved KLayout 0.30.14 where the 0.9.0 build was tested
against 0.30.12 (the tool warns); the counts reproducing the committed
report exactly is the evidence that the caveat changed nothing here.

**At the pinned klt 0.9.0 nothing changed: all three cited gaps persist.**

## Probe 2 — the preset at the pin: the refusal reproduces

The 2026-11-21 par request verbatim, its explicit PDN recipe replaced by
`power.preset: "asap7sc7p5t"` (everything else — `pdk.cell_library:
"asap7sc7p5t_28_R"`, floorplan, library, straps removed per the preset's
mutual exclusion — unchanged), run at 0.9.0, exits 1 with:

> request.power.preset 'asap7sc7p5t' is a 'asap7sc7p5t_28' recipe
> (OpenROAD-flow-scripts@95ebc50a…:flow/platforms/asap7/openRoad/pdn/
> grid_strategy-M1-M2-M5-M6.tcl (M1/M2 followpins rails verbatim; M5/M6
> deliberately deviate, issue #4494)), but request.pdk.cell_library is
> 'asap7sc7p5t_28_R' -- a preset may only be used with the standard-cell
> library it was transcribed for

So the #28 guidance stands at the pin: the RVT overlay key cannot use the
preset; keying the unflavoured base name is not an option either — the
flavour key is how this flow's LEF/GDS/Liberty overlay resolves. The
explicit on-grid straps remain the pin-era PDN setting.

## Probe 3 — the pad-tip repair at main: it does not clear this counter's markers

The strongest available check for "#4508's closure clears the three
markers": regenerate the GDS with a klt that carries the merged fix, from
the same routed DEF, then re-run the pinned 0.9.0 DRC on it. The full
scratch pipeline (overlay → `klt synthesize` → `klt place-and-route`, the
run.sh requests verbatim, `seed` 1) ran at upstream main
`9b5a4ec71e68930303ab22015da4d8b0ab671429` (`klt 0.9.3.dev3711+g9b5a4ec71e68`,
post-#7142 and post-#7231), against the pinned asap7 checkout (§1 pins
verified below).

- The regenerated routed DEF is **byte-identical** to the committed record's
  (`sha256 88d25e00c51028369e85bc5521f5483c0766a3e9064d775a201e548df80a9f79`
  on both) — the placement and route reproduced, so the DEF is a controlled
  variable and only the DEF→GDS merge version differs.
- The pinned 0.9.0 DRC on the regenerated GDS reports the **same 44 markers
  at the same bboxes**, the three router tips included: `M1.S.4` 1,
  `M1.S.5` 2 at their recorded coordinates.

The markers' geometry (KLayout polygon dump at the three bboxes) explains
why: each sits between a placed `VIA_VIA12` M1 pad (18 nm × 22 nm) whose
facing vertical edge is **flush with its underlying 18 nm V1 cut** —
untrimmable without uncovering the cut — and a **facing non-pad M1 shape**
(a 77 nm-wide merged shape, a minimum-width 18 nm wire, and a 59 nm-wide
shape), at 22–27 nm tip-to-tip gaps. #7142 repairs opposing **pad–pad**
pairs by adding metal along both faces; its own fixture carried seven
`M1.S.4` between two placed pads and zero `M1.S.5` (which the curator
finding had already flagged as leaving the `M1.S.5` effect open). The
pad–wire pairs here are outside its reach, and outside #6992's pad-free
(wire–wire) scope. Per the friction protocol (the ERC-precedent shape:
gap persists at the pin, tracker considers it done), the mixed case is now
tracked by a fresh generic issue: **klayout-tools #7397**.

## Probe 4 — the preset at main: the fix works, and the pin bump is what brings it

The same preset request as probe 2, run at main
`0.9.3.dev3711+g9b5a4ec71e68`: **accepted** — `par` status `ok`,
`power.preset: "asap7sc7p5t"` recorded, `power.pdn: true` (#7231 adds
`asap7sc7p5t_28_R` to the preset's `also_cell_libraries`). That is a
verified later-version fix for #7001, so it routes to pin-bump tracking,
not to a fresh upstream issue: **#246** tracks the bump (upstream #6930
tracks the `v0.9.3` tag that would first carry it).

Measured footnote, not a recommendation: the preset-built GDS is itself
not deck-clean — the pinned 0.9.0 DRC on it reports 33 markers in seven
rules (`M1.S.4` 3, `M1.S.5` 1, `M3.S.2` 1, `M5.AUX.1` 8,
`SDT.ACTIVE.AUX.2` 6, `V4.M4.EN.1` 11, `V4.M5.EN.2` 3) — the preset's own
documented via-stack residuals (#6909) plus `M5.AUX.1` strap markers.
Choosing preset vs explicit straps after a pin bump stays a measured-DRC
decision (#246 lists it).

## Disposition

- `README.md` / `ROADMAP.md` status text refreshed to distinguish the
  measured 0.9.0 counts (1 `M1.S.4` + 2 `M1.S.5` router tips) from the
  dated upstream dispositions, and to cite #7397 (open) for the router tips
  instead of the closed #4508. `evidence/item10.json` re-attested in the
  same PR (README is an item 10 path).
- #28 follow-up posted converging the preset citation on #7001, linking
  the two settings comments and stating the pin-era PDN options with the
  probe results.
- The 2026-11-21 addendum and every record directory are untouched.
- No waiver, no deck edit, no pin change: `spec/` untouched.

## Run provenance

| What | Value |
|---|---|
| Flow code | `feature/issue-245`, worktree of `2051215` (origin/main); run.sh requests transcribed verbatim into scratch |
| PDK checkout | The-OpenROAD-Project/asap7 @ `d24f8b857ff74cf5b21ab18a7e1b11a3954c449b`, `asap7sc7p5t_28` @ `f970bd3c3292b79ae4d022a3ec80533534614066`, `asap7_pdk_r1p7` @ `58d72c9d291e186a77468586ab0c43d8a21eda6a` — the §1 pins of `spec/pdk-bringup.md` |
| klt (pin) | `klayout-tools==0.9.0` via uvx (probes 1–2, and the DRC of probes 3–4) |
| klt (main) | `git+…@9b5a4ec71e68930303ab22015da4d8b0ab671429` → `klt 0.9.3.dev3711+g9b5a4ec71e68` (probes 3–4) |
| Deck | packaged `asap7.drc` of 0.9.0, `sha256:14f146f0…e0f12d13`, 267 categories, for every DRC run above |
| Host tools | Yosys 0.67+post, OpenROAD 26Q3-1510-g6cb3f2b704, KLayout 0.30.12 (host) / 0.30.14 (uvx env, warned) |
| Scratch | `/tmp` (short `TMPDIR`; the yosys→ABC hang of 2026-11-15-record-equality.md does not fire) |
| Records | none written; `flow/smoke/records/*` untouched (verified by `git status` in the PR) |
