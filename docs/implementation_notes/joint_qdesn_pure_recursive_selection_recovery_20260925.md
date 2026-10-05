# JOINT pure-recursive selection recovery

Date: 2026-09-25

## Scope

This recovery is confined to the dedicated JOINT pure-DESN recursive-selection
lane. It does not alter model kernels, DGPs, protected article fixtures,
PriceFM, GloFAS, independent-QDESN workflows, article sources, or Overleaf.

## Incident

The Jerez campaign completed 6,144 ridge workers and 6,000 Gaussian RHS-VB
workers. Quantile stage 1 then stopped before fitting because width-dependent R
output wrapping split each long quantile-root/job-ID record.

The health audit also found duplicate `calibration_acrps_mean` fields in each
RHS summary. The first was inherited from the ridge frontier and the second was
the actual RHS recursive-calibration score. The old finalizer selected the
first field. This invalidated the derived eight-family winner table, but not
the completed ridge/RHS fits or their detailed predictions and VB traces.

Forensic reconstruction found 6,000 finite actual RHS scores, 5,994 converged
fits, and six nonconverged fits. Correct selection changes six family
architectures and five `tau0` values. All corrected winners are fully
converged.

## Repair contract

1. Preserve and inventory the superseded derived selection and unused
   quantile staging.
2. Normalize each completed RHS summary to a unique schema containing only
   worker/candidate identity, diagnostics, and worker-produced metrics.
3. Refresh each modified worker manifest and verify it.
4. Recompute RHS aggregates and family winners using actual RHS calibration
   aCRPS, requiring finite hard-gate-passing and fully converged replicate
   groups.
5. Record the recovery Git state in the selection manifest.
6. Remove only unused task-owned quantile staging; refuse recovery if any
   quantile worker has a `DONE` or `FAILED` marker.
7. Regenerate the 408-job nested quantile plan and assert stage cardinalities
   `24, 24, 48, 48, 48, 168, 24, 24`.
8. Resume the idempotent controller at quantile VB. Completed ridge and RHS
   workers are never relaunched.

## Implementation

- `application/R/joint_qdesn_pure_recursive_campaign.R` now emits unique
  worker summaries, fails on duplicate columns, repairs legacy RHS summaries,
  validates result identity against the frozen plan, and selects only from the
  actual RHS metric.
- `application/scripts/emit_joint_qdesn_pure_recursive_quantile_jobs.R`
  emits literal TSV queue records from a validated R data frame.
- `application/scripts/recover_joint_qdesn_pure_recursive_campaign.R`
  performs the one-time fail-closed runtime migration and quantile-plan rebuild.
- `application/scripts/launch_joint_qdesn_pure_recursive_campaign.sh`
  checks exact stage cardinality and nonempty worker arguments before launch.
- `application/tests/test_joint_qdesn_pure_recursive_campaign.R` covers
  duplicate-metric normalization, clean future summaries, long absolute paths,
  and all eight stage counts.

## Promotion boundary

The regenerated selection is an initializer for quantile VB and MCMC, not an
article result. Article integration remains blocked until all 408 quantile-VB
jobs, 136 article-VB components, 160 MCMC workers, DGP-oracle work, and 64
paired path/mean-state score cells are complete, finite, audited, and
hash-manifested on the dedicated branch.
