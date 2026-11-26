# Persistent-heavy-tail sealed V5 closeout

## Frozen identities

- Lane: `work/joint-qdesn-persistent-tail-sealed-v5-20261126`.
- Execution source commit: `aa90d97dae6f7b8c405381e0b5784d95325a1395`.
- V4 evidence commit: `beedc227c0c40b2f4b77e0130f89c90bf1adc2da`.
- Run tag: `joint_qdesn_persistent_tail_sealed_v5_20261126`.
- Host and runtime: Jerez, pinned R 4.6.0, physical CPU IDs 0--14,
  one numerical thread per worker.

The V4 closeout manifest, terminal decision, two-challenger table, and exact
control were verified against the four SHA-256 pins in the V5 contract. The
three finalist specifications were frozen at SHA-256
`f2d70d3c54fd7beb03be60ed23823d1bbcb9173bdb9eecdbd6502dfcfa28a61d`
before any sealed fixture was materialized.

## Completion

All 15 planned workers completed: three profiles by five matched sealed DGP
fixtures, with zero worker failures, zero contract crossings, zero protected
rows, and 15 verified worker manifests. The launcher exit receipt is zero and
the nine-entry closeout manifest verifies completely.

An incidental outer tmux command wrote the literal text `$?n` to
`pipeline.exit_status.txt`. That file is not part of the scientific closeout
manifest. The launcher's own authoritative receipt is
`orchestration/s1/exit_status.txt = 0`; worker health, manifests, and finalizer
outputs independently verify completion. No fit or result was changed in
response to this orchestration-only typo.

## Result

| Profile | Mean DGP score | Empirical 95% interval | Fit/H1 gates | Matched result |
|---|---:|---:|---|---|
| V4-3242 | 0.434943 | [0.417311, 0.472686] | pass | beats exact in 5/5 fixtures |
| V4-2430 | 0.442931 | [0.421372, 0.482204] | fail | upper fit and upper H1 fail |
| exact V2 | 0.445256 | [0.417975, 0.485382] | pass | reference |

V4-3242 improves the matched mean by `0.0103128`, or approximately 2.32%.
Its empirical paired challenger-minus-exact interval is
`[-0.0194049, -0.0006637]`. The marginal score intervals overlap, so the result
is a descriptive sealed confirmation and not a formal equivalence or
superiority theorem. V4-2430 is not eligible despite its slightly lower score
mean because the predeclared upper-tail fit and horizon-one safeguards fail.

The frozen terminal status is
`V5_COMPLETE_SEVEN_LEVEL_CONTINUATION_AUTHORIZED`. This authorizes only a new,
separately frozen seven-level independent-AL confirmation for V4-3242 versus
exact V2. It does not authorize joint, exAL, MCMC, article, or Overleaf changes.
Any later exAL MCMC run must retain exact M0.

## Evidence and hashes

Runtime root on both hosts:

`application/cache/joint_qdesn_persistent_tail_sealed_v5_20261126`

| Artifact | SHA-256 |
|---|---|
| `v5_decision.csv` | `23690e7b4ce3e9f3ff23d4b450417df9103a6499910fbac26eb6623d8923677e` |
| `v5_profile_summary.csv` | `be670367dc80f11cfc51ea2cd31b48bae897c059d7ced49f24ba38903a2245e6` |
| `v5_matched_contrasts.csv` | `5536a6bae8dd1591f46734a39b8d1ce8c5cb1192d0d243c84b23b3cf2dbfc081` |
| `v5_closeout_manifest.csv` | `7a91bcce921a361e9836b1d6cb809e602640559e8acfd5c916058920fd55e333` |
| `v5_transfer_inventory.csv` | `961d02e093ae4015b2cc9fa52bd430fa9523e59d6d76f9893a6eabb0589a426e` |
| `v5_transfer_inventory_verification.csv` | `70989d3efd5794e6a50adfaba711771579e71ef5a6bd9e138436bf5b7562a5ab` |

The transfer inventory contains 149 files totaling 8,341,973 bytes. It was
verified independently after transfer from Jerez to Muscat.

## Verification completed

- V5 focused test: 34 expectations passed.
- V5 source guard: 19 checks and five mutation rejections passed.
- V4 inherited deterministic-registry test: 54 expectations passed.
- Persistent-tail fit-first regression: 20 expectations passed.
- DGP-integrated score regression passed.
- Posterior-target contract regression passed.
- Real preparation rehearsal passed before production.
- Production preparation and all worker/closeout manifests passed on Jerez.
- `git diff --check` passed.

Runtime files, fixtures, fit initializers, logs, and generated score packets
remain ignored and must not enter Git. No article file, main branch, or Overleaf
ref was modified.
