# Deferred rerun register for the joint-QVP global-scale correction

## Status

`DEFERRED_MANDATORY_BEFORE_FINAL_PROJECT_CLOSEOUT`

## Decision

The shared joint-QVP regularized-horseshoe implementation was corrected in
commit `0ed0e8827755b9a1e6985da577692efc8105e186` and integrated into
authoritative `main` by commit
`597096492651cc56bff04a365f16fe99a2c5908f`. The correction changes the
inverse-gamma shape for an updated global variance from (p/2) to
((p+1)/2), as required by the stated half-Cauchy augmentation.

The scientific reruns listed below are deliberately deferred. They are not
required for editorial reorganization of the manuscripts, and no expensive
fit is to be restarted solely for the current compression revision. This
deferral does not validate, correct, or promote any stored result produced by
the earlier update.

## Mandatory work before final project closeout

| Result family | Required disposition |
|---|---|
| Phase181 joint simulation and its nominally independent comparators | Refit every VB initialization and MCMC analysis that used the shared joint-QVP update; regenerate all affected tables, figures, contrasts, diagnostics, and manifests. |
| Phase182 and later JOINT analyses | Establish the exact source commit and whether the global scale was updated. Rerun each exposed fit from a corrected frozen source. |
| GloFAS Part 1 quantile analyses | Rerun the exposed one-level and joint modes before any scientific promotion. |
| GloFAS Part 4 or later joint analyses | Complete source-level provenance review and rerun if the affected update was active. |
| Jerez JOINT article-confirmation analyses | Require the corrected source before fitting; if any affected fit already completed under earlier code, replace it. |

The independent validation analyses produced by the `exdqlm` package, the
current PriceFM R69B--R92 authority, the authoritative GloFAS FR09 analysis,
and the GloFAS Normal-RHS and Part 3 partitioned-RHS calculations use separate
implementations with the correct ((p+1)/2) shape and need no rerun for this
specific correction.

## Acceptance criteria

This item may be closed only when all of the following hold:

1. every candidate result has a frozen source commit and an explicit record of
   whether the global scale was updated or fixed;
2. every exposed fit has been rerun from code containing the correction;
3. focused mathematical, MCMC, VB, manifest, and source-provenance checks pass;
4. replacement article assets are regenerated as complete comparison sets,
   without selecting favorable cells;
5. the main article and supplement are rebuilt and reviewed after those assets
   are integrated; and
6. the scientific owners approve the revised interpretation before final
   project closeout.

## Present publication boundary

The current editorial compression changes presentation only. It preserves the
existing numerical assets verbatim and must not describe them as recomputed
under the corrected update. The affected JOINT assets remain provisional and
must be replaced before the project is declared scientifically complete. No
current run should be interrupted, cleaned, or promoted on the authority of
this register.

The mathematical audit, exposure table, and verification record are in
`docs/implementation_notes/joint_qvp_rhs_global_shape_correction_20260908.md`.
