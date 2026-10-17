# 0002 — STA corners and Vt flavours

**Status:** accepted 2026-10-17 (SS, TT ratified; FF provisional). Timing is predicted, not measured.

**Decision.** Corners are the RVT NLDM Liberty files listed in `spec/core.md`: SS 0.63 V / 100 °C
(setup, 1 GHz target), TT 0.7 V / 25 °C, FF 0.77 V / 0 °C (hold, provisional). Voltage and
temperature are quoted from each file's `nom_voltage` / `nom_temperature`. Synthesis may use RVT
only.

**Why RVT only.** LVT and SLVT NLDM files ship at TT only, so cells from them have no SS timing
and cannot be signed off at the target corner. SRAM-Vt is out of scope.

**Why FF is provisional.** `asap7sc7p5t_SIMPLE_RVT_FF_nldm_211120.lib` has a 0.7 V / 25 °C header
(see `pdk-bringup.md` §5); a hold set built from it would silently mix corners. Trigger to
ratify: that file is shown to be characterised at FF, or a corrected file is pinned.

**Consequences.** Setup closure is claimed at SS only; hold closure is not claimed until FF is
ratified.
