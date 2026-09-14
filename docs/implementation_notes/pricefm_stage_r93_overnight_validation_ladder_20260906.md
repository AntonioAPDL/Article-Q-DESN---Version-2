# PriceFM Stage-R93 Overnight Validation Ladder

## Purpose and scope

Stage-R93 tests the region-frozen selection algorithm on `SE_2`, the worst
current PriceFM region. The decision unit is the region: one DESN geometry,
one information set, one RHS `tau0`, and one likelihood family are selected
without using any forecast/test window. This is a bounded proof of the proposed
algorithm, not a new all-region production surface.

The overnight controller continues the already-running 240-candidate normal
scaled-Ridge screen and automates only the admissible validation ladder. It
stops after freezing AL or exAL on the reserved original Fold-1 validation
window. Test scoring, registry changes, article changes, joint fitting, and
MCMC remain blocked.

## Audit findings

1. The live Ridge run is healthy and resumable. It must not be stopped or
   relaunched; the controller observes its existing `launch_status.csv` until
   all 240 experiment rows are complete.
2. The generic PriceFM model runner is appropriate for the normal Ridge and
   normal RHS stages, using the probed R93 exact-name runtime repair. It is not
   appropriate for the final AL/exAL stage because its quantile path depends on
   fork-only helpers and does not explicitly enforce the repaired structured
   sigma/gamma profile.
3. The final quantile runner therefore calls the exported
   `exalStaticLDVB()` API through the validated R67/R72/R75 adapters and the
   hash-pinned R82 structured-initialization runtime.
4. The originally declared quantile order needed a branching correction. A
   single rolling state would initialize `tau=0.55` from `tau=0.10`. R93 now
   uses the intended median-centered tree:

   ```text
   outer normal RHS -> 0.50
                         |-> 0.45 -> 0.25 -> 0.10
                         `-> 0.55 -> 0.75 -> 0.90
   ```

   At every quantile, exAL is initialized from the same-quantile AL fit.
5. Formal convergence is recorded, but the repaired exAL family is eligible
   only if all seven atoms pass the established numerical gates. AL is the
   mandatory complete finite fallback.

## Frozen selection protocol

1. **Ridge closeout.** Rank all 240 candidates by median AQL over inner folds
   101--103, then worst-window AQL, state dimension, total units, and stable ID.
   Advance exactly 30 geometries.
2. **Coarse normal RHS.** Fit the 30 geometries at `tau0` values `1e-4`,
   `1e-3`, and `1e-2` on the same three internal windows. This is 90
   experiments and 270 model cells.
3. **Conditional RHS refinement.** Run exactly three additional `tau0` arms
   (`5e-5`, `5e-4`, `2e-3`) for only the winning geometry when the coarse
   winner is on a boundary or the two best same-geometry settings are within
   one percent. Otherwise skip this stage. The maximum cost is nine cells.
4. **Outer normal confirmation.** Fit the single frozen normal RHS winner on
   original Fold 1 train/validation, with the test interval absent. This fit
   writes lightweight coefficient and scale summaries for initialization.
5. **Independent quantile ladder.** Fit seven AL and seven repaired structured
   exAL RHS_NS VB atoms at the paper quantiles
   `0.10,0.25,0.45,0.50,0.55,0.75,0.90`. Geometry and `tau0` remain frozen.
6. **Validation family freeze.** Compare only complete numerically eligible
   seven-quantile families on original Fold-1 validation AQL. Select one family
   as a whole; per-quantile family mixing is forbidden.
7. **Hard stop.** Write the frozen validation contract and wait for explicit
   authorization before any all-fold test audit.

After Ridge completion, the protocol requires 285 model fits without optional
refinement or 294 with it. Ten normal experiments run concurrently, one
single-threaded process per selected logical CPU. The 14 quantile atoms run in
their dependency order on one CPU and checkpoint after each atom.

## Numerical and provenance gates

- Selection inputs contain only `train` and `val`; test adapter files are
  rejected.
- Config, data config, normal initialization summaries, runtime manifest,
  runner, and public-API adapter scripts are hash frozen.
- The exAL runtime must identify the CRAN 1.1.1 base tarball SHA-256
  `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e`,
  local version `1.1.1.9004`, and the R82 structured initialization repair.
- Every AL atom must be finite. Every exAL atom must additionally have the
  required trace, at least 35 structured updates, `sigma < 100`,
  `abs(gamma) < 4`, beta-norm inflation below 10, first state delta below 100,
  and last-ten state/sigma delta below 2.
- No binary model artifact is written. The controller removes heavy `X_*.csv`
  adapter matrices only after metrics are materialized.
- The controller requires a clean, exact task-branch HEAD and at least 100 GiB
  free disk and 32 GiB available memory.
- Before each new launch, the assigned CPUs must remain below 35 percent usage
  for two consecutive samples. Thread-count environment variables are fixed at
  one.

## Automation and recovery

- `294_advance_pricefm_stage_r93_validation_ladder.py` closes the RHS,
  refinement, outer-normal, and quantile-validation stages and materializes the
  next bounded contract.
- `295_run_pricefm_stage_r93_quantile_ladder.R` implements the public-API,
  median-centered AL/exAL quantile ladder with atom-level checkpoints.
- `296_orchestrate_pricefm_stage_r93_overnight.py` waits for Ridge completion,
  advances each gate, launches the authorized validation work, and stops before
  test.

The controller holds an exclusive lock. Existing completed stages are reused.
Incomplete closeout directories are preserved under an orchestrator quarantine
before deterministic regeneration. Partial quantile atoms are resumed from
their CSV/JSON checkpoints. Any failed experiment, source-hash mismatch,
resource timeout, incomplete AL family, or firewall violation causes a
fail-closed terminal state with no downstream action.

Live state is recorded at:

```text
application/data_local/pricefm/authoritative/
  pricefm_stage_r93_overnight_validation_ladder_20260906/orchestrator/state.json
```

Runtime logs and generated artifacts remain under the ignored PriceFM
`application/data_local` tree. The reproducibility scripts, tests, and this
note are the only tracked additions.

## Why this is the efficient next step

The protocol reuses the active Ridge work, advances only 30 of 240 geometries,
refines `tau0` only when the observed validation surface warrants it, and fits
the expensive quantile models only once for a frozen regional specification.
It directly tests the no-fold-tuning design while preserving a fully sealed
test audit. A broader all-region launch before this proof would multiply cost
without first validating the central selection algorithm.

## Explicitly blocked

- no test or forecast-window selection;
- no all-fold test scoring without a new authorization;
- no registry or manuscript mutation;
- no article-repository work;
- no joint Q-DESN fit;
- no MCMC;
- no GloFAS, joint-validation, or other-lane changes;
- no merge to `main` or Overleaf branch.
