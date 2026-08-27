# PriceFM Stage-R62 end-to-end execution record

Date: 2026-08-27

Lane: PriceFM only

Branch: `work/pricefm-joint-quantile-20260824`

## Decision

The next valid action is to complete the six missing independent
seven-quantile comparators, not to launch another broad joint-model search.
The former R57 comparison authority used median-only validation values and is
not like-for-like with the joint seven-quantile score. Stage-R62A has rebuilt
108 of 114 exact independent comparators from historical artifacts without
opening test data. Stage-R62B prepares the remaining 42 quantile jobs (six
region/fold cells times seven quantiles), fitting AL and exAL in each job.

The resulting 114-cell surface is an input to later scientific decisions. It
does not itself authorize registry, MCMC, test, article, or Overleaf mutation.

## Reproduced audit

| Check | Result |
|---|---:|
| PriceFM surface cells | 114 |
| Exact seven-quantile matches reconstructed | 108 |
| Exact-comparator gaps | 6 |
| Historical median-only comparator cells | 114 |
| Historical family/value mismatches | 30 |
| Corrected family changes | 26 |
| Existing joint validation wins among matched cells | 11 |
| Joint near losses, at most 1% | 62 |
| Joint moderate losses, above 1% through 5% | 29 |
| Joint severe losses, above 5% | 6 |
| Provenance conflicts | 0 |
| Test opened | no |

The six gaps are `AT` fold 2, `BG` folds 1-3, `FI` fold 3, and `PL`
fold 2. Each replay preserves the exact case-specific source information set,
DESN geometry, training window, seed, RHS contract, and adapter contract. Only
the quantile and output paths change. This preserves the project objective of
selecting a model separately for every region/fold rather than imposing one
global specification.

## Implemented chain

1. `216_reconstruct_pricefm_stage_r62_matched_seven_quantile_authority.py`
   semantically fingerprints historical bundles, verifies exactly the seven
   paper quantiles, recomputes original-scale validation AQL, and selects AL or
   exAL using validation only.
2. `217_prepare_pricefm_stage_r62_gap_completion.py` clones the six exact source
   contracts into 42 train/validation-only jobs. Its materialized manifest is
   declaratively launch-blocked and test-blocked.
3. `218_launch_pricefm_stage_r62_gap_completion.py` requires an explicit
   command-line authorization, binds one process to each assigned CPU, limits
   numerical libraries to one thread, writes incremental status, skips complete
   jobs, and resumes summarization without refitting when durable fit artifacts
   already exist.
4. `219_closeout_pricefm_stage_r62_gap_completion.py` recomputes AL and exAL
   seven-quantile validation means and emits discoverable panel artifacts. It
   does not read test metrics.
5. Stage-R62A must then be rerun to freeze all 114 exact cells. Any remaining
   gap, conflict, malformed bundle, hash failure, or non-finite score blocks the
   next stage.

## Runtime evidence

Runtime artifacts remain outside the tracked worktree under
`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm`.

- R62A authority:
  `authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827`
- gap manifest:
  `experiment_grids/pricefm_stage_r62_gap_completion_20260827/launch_manifest.csv`
- gap run root:
  `runs/pricefm_stage_r62_gap_completion_20260827`
- gap preparation evidence:
  `authoritative/pricefm_stage_r62_gap_completion_prep_20260827`

The production interpreter is the preserved PriceFM Python 3.11 environment at
`application/data_local/pricefm/venv/bin/python`. The system Python is too old
for these scripts and is not an acceptable substitute.

## Completion and downstream gates

After all 42 jobs complete, closeout must report 42 complete jobs, zero failed
jobs, 12 complete AL/exAL seven-quantile panels, finite original-scale
validation AQL, and no test access. R62A must then reproduce 114 exact cells
with zero gaps and zero provenance conflicts.

Only after that freeze may a new case-specific joint campaign be designed.
The corrected queue should preserve existing joint wins, prioritize
mechanistically justified family-transfer and severe-failure cases, and avoid a
blanket capacity grid. A joint VB candidate enters confirmation only if it
beats its exact independent seven-quantile comparator on validation and passes
the declared hash, convergence, and scoring-contract gates. MCMC is reserved
for frozen validation winners. Test comparison, registry mutation, and article
assets remain blocked until confirmatory evidence passes.

## Explicitly blocked

- use of the old R57/R58/R59 `112/114` win claim for promotion;
- launch of the stale R61 manifest against the median comparator;
- test-adaptive fitting, selection, continuation, or tie-breaking;
- MCMC used as a repair mechanism for a losing VB candidate;
- registry, manuscript, table, figure, Overleaf, or `main` mutation;
- cleanup of R57-R62 predictions or checkpoints needed for provenance;
- any GloFAS, validation, DQLM, or other-lane process or artifact change.
