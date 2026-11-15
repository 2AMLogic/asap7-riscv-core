# spec

ASAP7 is a predictive PDK; this block is layout, DRC and timing only and is never fabricated.

- [`core.md`](core.md) — the ratified target specification (rows ratified or deferred)
- [`core.rows.json`](core.rows.json) — machine-readable listing of the `core.md` target table (adds no row)
- [`statistical-rows.json`](statistical-rows.json) — hash-bound statement that no ratified row is statistical (T1 item 6)
- [`pdk-bringup.md`](pdk-bringup.md) — pins, what resolves under `klt`, DRC deck and LVS coverage, Liberty corner headers
- [`decisions/`](decisions/) — one record per decision, numbered from `0001`
  (see [Decision record numbering](#decision-record-numbering); the directory
  is the register, so list it rather than trusting a count written here)

## Decision record numbering

Each record in [`decisions/`](decisions/) is a file named `NNNN-<slug>.md`,
where `NNNN` is a four-digit sequence number. **The next author takes the
lowest unused number.** There is no index to consult — list the directory:

```bash
ls spec/decisions | sed -nE 's/^([0-9]{4})-.*\.md$/\1/p' | sort -u | tail -1
```

A number identifies exactly one record, with the one recorded exception below.
`.github/workflows/ci.yml` has a guard step ("Decision record numbers are
unique") that fails the build on any *other* duplicate number, naming the
number and the colliding files.

**Cite a record by linking its path**, as `README.md` and [`core.md`](core.md)
do — `[decision 0007](decisions/0007-adopt-core-pin.md)` — not by bare number.
A bare number does not survive a collision, and it does not carry the record's
status: a record may be `proposed` (awaiting operator ratification) or
`adopted`, and citing a proposed record as settled authority misreads it.

### Recorded collision: two records share `0012`

Two records were committed with the number `0012`. **Neither is renumbered.**
A committed record is not rewritten — `decisions/0013-asap7-deck-record-follow-ups.md`
states "Existing records are not edited" — and renumbering either one would
mean editing it. The collision is recorded here instead, so it is read as a
known fact rather than as an error:

| Record | Subject | Status |
|---|---|---|
| [`0012-pin-klt-0-9-0-and-ratify-asap7-drc-deck.md`](decisions/0012-pin-klt-0-9-0-and-ratify-asap7-drc-deck.md) | pin `klayout-tools==0.9.0` for DRC, LVS and the smoke flow; ratify the new ASAP7 DRC deck hash | proposed 2026-11-05 |
| [`0012-shared-archtest-module-and-item9-reattestation.md`](decisions/0012-shared-archtest-module-and-item9-reattestation.md) | one shared module for the two arch-test drivers; T1 item 9 re-attested | adopted 2026-11-06 |

**Every bare "decision 0012" citation in this repository resolves to the
first one** — the `klt` 0.9.0 / ASAP7 DRC deck record. Nothing anywhere cites
the shared-archtest record, by number or by filename.

The tree is the register: enumerate the bare citations on demand rather than
trusting a file-and-line inventory written here — such a list rots as soon as
any cited file moves:

```bash
git grep -nPi '(?<!\[)decisions? 0012' -- . ':!spec/README.md'
```

`(?<!\[)` is per-occurrence, so a bare citation sharing a line with a markdown
link is still reported, and `':!spec/README.md'` keeps this section from
matching its own prose. Where `git grep -P` is unavailable (git built without
PCRE support), the portable equivalent:

```bash
git grep -nEio '.?.?decisions? 0012' -- . ':!spec/README.md' | grep -vi '\[decision'
```

`0012` is the only duplicated number. The `ci.yml` guard allowlists exactly
this pair of filenames, so a third `0012` — or a collision on any other
number — still fails the build.
