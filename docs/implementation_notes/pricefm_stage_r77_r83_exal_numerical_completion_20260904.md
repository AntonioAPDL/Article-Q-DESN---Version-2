# PriceFM R77-R83 exAL Numerical Completion

## Scope

This work completes the validation-only independent exAL VB surface without
touching test data, the decision registry, the article, joint models, or MCMC.
The frozen R76 outcome is 280 completed atoms and 14 failed atoms across 11 of
the 42 exAL-anchored region/fold cases.

## Evidence chain

1. R77 classified the 14 failures. One FR fold-3 tau-0.25 atom failed in the
   structured gamma grid and 13 atoms failed the aggregate finite-output gate.
2. R80 replayed FR fold 3 at tau 0.25 and SE_4 fold 1 at tau 0.25 and 0.75 with
   field-level diagnostics. FR latent sufficient statistics had already reached
   magnitudes above `1e199` before the first structured update. Both SE atoms
   recovered to finite final values but retained transient non-finite scale
   trace entries.
3. R80B/R80C removed the ten-iteration scale/skewness freeze. The SE controls
   became bounded, but FR reached a finite scale above `2e13`; the registered
   R80 gate therefore failed and correctly blocked R81.
4. R80D varied the freeze over 1, 2, 3, and 5 iterations. Longer freezes made
   the FR trajectory progressively worse. This falsified a schedule-only fix.

## Root cause

The initial static exAL moments were produced by a second-order Gaussian delta
approximation at `gamma = 0`. The exAL scale-skewness representation contains
`abs(gamma)`, so this is a nonsmooth point. For the FR tau-0.25 anchor, the
observed delta correction changed `xi1` from about `1.4209` to about `-7.2987`
and `xi_lambda` from approximately zero to about `-1.4430`. The positivity
safeguard then floored `xi1` at `1e-12`. This effectively removed likelihood
precision from the first coefficient update and caused the upstream state
explosion. The later structured gamma-grid failure was a consequence, not the
origin, of the instability.

## R82 repair

R82 is a separately versioned local derivative of exact CRAN exdqlm 1.1.1. It
retains the R72 scale-aware SPD repair, the R75 large-n GIG repair, and the R80
failure callback. For structured exAL only, it initializes the first CAVI step
with plug-in moments at the AL beta/sigma warm start and `gamma = 0`, equivalent
to a point-mass initialization. The first active scale/skewness block then
replaces those values with the existing exact structured
`q(gamma) q(sigma | gamma)` grid/GIG moments. No likelihood, prior, DESN,
feature, seed, data, or selection rule changes.

Runtime contract:

- version: `1.1.1.9004`
- repair: `scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-plus-structured-plugin-init`
- base tarball SHA-256: `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e`

## Gates

R82 replays exactly three registered controls: FR fold 3 tau 0.25 and SE_4 fold
1 at tau 0.25 and 0.75. All must complete with the R82 runtime, at least 35
structured updates, finite required traces, scale below 100, gamma magnitude
below 4, final beta norm below ten times its AL anchor, first state step below
100, and last-ten state/scale steps below 2. A failure blocks all scientific
retries.

If and only if R82 passes, R83 may refit exactly the 14 failed R76 atoms with
immediate structured updates. This was the registered R83 boundary; R83 remains
validation-only and writes no binary model objects.

## R84 validation-only family closeout

R84 is implemented but cannot materialize until R83 completes cleanly. It
hash-verifies and reuses the 280 successful R76 atoms, accepts exactly the 14
R83 replacements under the `1.1.1.9004` runtime and structured plug-in
initialization contract, and reconstructs all 42 exAL seven-quantile surfaces.
For each region/fold case, raw original-scale validation AQL chooses between the
complete exAL surface and the frozen R73 AL surface. ExAL is eligible only when
all seven traces are finite and tail-stable. Every R83 replacement must also
retain the registered R82 scale, beta, gamma, and first-step bounds; finite but
pathological completion is not sufficient. Monotone rearrangement is reported
as a sensitivity and cannot affect selection. The other 14 cases retain their
frozen AL family because no new exAL refit was authorized for them.

The output is a complete 56-case, 392-atom provisional independent VB selection
manifest. R84 still cannot read test data, mutate the registry or article,
launch another fit, or authorize joint/MCMC work.

## Post-R84 surface-wide audit

R84 exposed a broader provenance problem that was not part of the original R83
failure boundary. Applying the already registered R82 bounds retrospectively to
all 280 terminally completed R76 atoms found 169 atoms that failed at least one
bound: 153 reached scale at or above 100, 73 had a first state step at or above
100, and three were tail-unstable. Every one of the 42 exAL case surfaces
contains at least one R76 atom. More importantly, all 280 R76 atoms used the
same mathematically invalid nonsmooth delta initializer, whether or not their
terminal values appeared bounded.

Consequently, R84 is quarantined as a diagnostic ranking rather than a frozen
scientific selection. The efficient homogeneous repair is to refit exactly the
280 legacy R76 atoms with the R82 runtime, retain the 14 R83 outputs, and leave
all 392 R73 AL atoms untouched. Test access remains blocked until a complete
repaired exAL surface passes the pre-existing numerical gates and a new
validation-only AL/exAL family selection is frozen.

## Prohibited actions

- Do not open test data during R77-R83.
- Do not mutate the PriceFM registry or article.
- Do not fit joint or MCMC models.
- Do not reinterpret diagnostic controls as scientific results.
- Do not weaken a failed numerical gate to obtain completion.
