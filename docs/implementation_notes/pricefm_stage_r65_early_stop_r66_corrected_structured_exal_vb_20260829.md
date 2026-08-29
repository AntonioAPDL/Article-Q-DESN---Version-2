# PriceFM Stage-R65 early stop and Stage-R66 corrected structured-exAL VB continuation

Date: 2026-08-29

Status: implementation and validation in progress. R65 is frozen. R66 may launch
only through the real-case production gate described below. Test access,
registry mutation, article mutation, joint fitting, and MCMC remain blocked.

## Executive decision

R65 must not be resumed as written. Its non-median structured-exAL fits were not
merely weak candidates: they exposed a production implementation defect in the
structured sigma-gamma path. The scientifically efficient continuation is R66:

1. preserve all 114 case-specific R62 DESN and information-set contracts;
2. reuse only hash-valid R65 adapters, normal anchors, and AL fits;
3. never reuse an R65 exAL fit;
4. fit corrected structured-exAL afresh for every one of the 798 quantile
   components;
5. run `AT` fold 1 as the first real production case;
6. start the remaining 113 cases only if that case passes mechanism,
   convergence, predictive-harm, crossing, provenance, and test-firewall gates;
7. close out by validation-only, whole-seven-quantile bundle selection.

This is not another specification search. R66 changes the broken inference
mechanism while holding the scientific model surface fixed.

## Frozen R65 evidence

The read-only R65 early-stop closeout is at:

`application/data_local/pricefm/authoritative/pricefm_stage_r65_early_stop_closeout_20260829`

| Item | Frozen value |
|---|---:|
| Planned region/fold cases | 114 |
| Planned quantile components | 798 |
| Metric-complete cases | 52 |
| Partial checkpointed cases | 20 |
| Not-started cases | 42 |
| Terminal components | 426 |
| Hash-valid AL fits | 440 |
| Hash-valid R65 exAL fits | 426, all excluded from reuse |
| Reusable adapters | 72 |
| Reusable normal anchors | 72 |
| Completed-case structured winners | 0 |
| Median structured/AL validation AQL ratio | 12.7799 |
| Median AL crossing rate | 0.02006 |
| Median R65 structured crossing rate | 0.49608 |

Only the median quantile converged consistently: 52 completed cases at
`tau=0.50`, versus zero or one completed cases at each non-median quantile.
Test remained sealed. No R65 process remains active, and no R65 artifact is
deleted because R66 still needs the valid checkpoints.

## Root-cause diagnosis

The collapsed generalized-inverse-Gaussian algebra agreed with the legacy
static objective. The failure was in how production VB consumed that algebra:

- a valid `eta_start` continuation was ignored in favor of a repeated coarse
  global initialization;
- exact conditional-GIG moments were calculated but then overwritten by the
  Gaussian delta-moment path;
- damping changed the Gaussian summary but not the moments used by downstream
  updates;
- Gaussian entropy was used after a structured update;
- convergence could be declared before any exact structured moment commit;
- existing integration coverage centered on `tau=0.50`, where the gamma effect
  is neutral;
- the finite difference for `Var(log sigma)` was too small and amplified Bessel
  evaluation noise.

These defects explain the signature observed in R65: tail nonconvergence,
boundary-like gamma/sigma behavior, severe AQL inflation, and near-random
quantile ordering. Broader DESN or tau0 screening would not repair this
mechanism and would waste compute.

## Corrected package boundary

The correction is isolated in the dedicated `exdqlm` branch
`work/pricefm-structured-exal-tail-fix-20260829` at commit:

`ab5741ceb854db9a53889a17c91d2d30f4d8c41d`

Pinned source hashes:

| Source | SHA-256 |
|---|---|
| `R/exal_ldvb_engine.R` | `d82d1be56a156c32eb681f5464ac00ea8765992034c84824c0c98066d09912e3` |
| `R/exal_inference_config.R` | `18f6a140e0dc4e33702528b21db8bf3b264b743fc745f2daf0b276143fb11044` |
| `R/exal_sigmagam_structured.R` | `c039125ab261c950ea464cc886f48257558b273df1e400aa407f72ff36e5d762` |

The package is installed once in the immutable PriceFM runtime library:

`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_libraries/exdqlm_ab5741c`

The install manifest is `pricefm_r66_install_manifest.json`. The detached source
checkout is `/data/jaguir26/local/src/exdqlm__wt__pricefm_r66_ab5741c`.

Focused package validation covers seven quantiles, exact conditional-moment
reconstruction, continuation, hybrid/full-refresh equivalence, chunking,
likelihood-family dispatch, and substep profiling. The package install passed;
the only warnings were pre-existing unknown LaTeX macros in one Rd file.

## R66 scientific contract

R66 uses the seven paper quantiles `0.10, 0.25, 0.45, 0.50, 0.55, 0.75,
0.90`. Each region/fold retains its own authoritative DESN, lag, feature-policy,
graph/local information-set, RHS-NS `tau0`, and training-window settings. There
is no universal model specification and no component-wise likelihood
cherry-picking.

The two complete validation surfaces are:

- `qdesn_al_rhs_ns_exact_chunked_r66_parity`;
- `qdesn_exal_rhs_ns_exact_chunked_structured_corrected_r66`.

AL is a parity control and same-quantile warm start. Corrected exAL is the only
new candidate. Selection occurs once per region/fold over the complete raw
seven-quantile validation AQL. PAVA is diagnostic only.

Corrected sigma-gamma profile:

| Control | Value |
|---|---:|
| Structured grid size | 151 |
| Grid span | 6 SD |
| Frozen warmup | 10 iterations |
| Post-warmup damping | 0.2 |
| Damping duration | 30 iterations |
| Minimum post-warmup updates | 35 |
| Minimum exact commits | 5 |
| Minimum relative gamma boundary margin | `1e-6` |
| Maximum VB iterations | at least 150 |

## Checkpoint reuse contract

Reuse is data-flow reuse, not result promotion. Each external R65 fit must have
a readable status JSON, a matching case/config/package/tau/method identity, and
a fit SHA-256 that agrees with both the status and the bytes on disk. Reused
adapter files are individually hashed. R66 writes references and provenance in
its own output namespace rather than copying or mutating R65 artifacts.

Expected reuse from the frozen inventory is 72 adapters, 72 normal anchors, and
440 AL components. R66 must build the remaining 42 adapters, 42 normal anchors,
and 358 AL components. All 798 corrected exAL components are new.

## Real-case production gate

`pricefm_joint_at_f1` is a real R66 result, not a disposable smoke run. It runs
first and remains part of the final 114-case surface. Broad continuation is
blocked unless all required gates pass:

- seven terminal AL/exAL components and seven converged exAL fits;
- final moment source `conditional_gig_exact` at all quantiles;
- continuation source `eta_start` with no optimizer fallback;
- at least five exact moment commits per quantile;
- finite positive sigma and finite interior gamma at all quantiles;
- corrected-exAL/AL validation AQL ratio at most 1.5;
- corrected-exAL crossing rate at most 0.20 and no more than 0.10 above AL;
- validation-only predictions and no test adapter files.

Lower-tail gamma exceeding upper-tail gamma is recorded as a non-blocking
orientation diagnostic because data-specific skew need not be symmetric.

## Reproducible stage wiring

| Role | Path |
|---|---|
| R65 early-stop closeout | `application/scripts/pricefm/228_closeout_pricefm_stage_r65_early_stop.py` |
| R66 package materializer | `application/scripts/pricefm/materialize_pricefm_stage_r66_package.py` |
| R66 preparation | `application/scripts/pricefm/229_prepare_pricefm_stage_r66_corrected_structured_exal_vb.py` |
| R66 case runner | `application/scripts/pricefm/230_run_pricefm_stage_r66_corrected_structured_exal_vb_case.R` |
| R66 gated launcher | `application/scripts/pricefm/231_launch_pricefm_stage_r66_corrected_structured_exal_vb.py` |
| R66 monitor | `application/scripts/pricefm/232_monitor_pricefm_stage_r66_corrected_structured_exal_vb.py` |
| R66 validation closeout | `application/scripts/pricefm/233_closeout_pricefm_stage_r66_corrected_structured_exal_vb.py` |
| R66 R helpers | `application/scripts/pricefm/pricefm_stage_r66_vb_helpers.R` |

Run tag:

`pricefm_stage_r66_corrected_structured_exal_vb_20260829`

The gated launcher requires an explicit `--authorize true`, at least 20 workers,
one unique logical CPU per worker, at least 150 GiB free disk, and at least 100
GiB available memory. It writes `production_gate.csv/json` before any broad
fan-out. A failed gate terminates the launcher after the first real case.

## Closeout and promotion boundary

After all 114 metric summaries exist and no case job failed, R66 closeout:

1. verifies exact-moment telemetry and convergence for every component;
2. verifies AL parity against the frozen R62 component and bundle metrics;
3. compares corrected exAL against the current R62 authority using validation
   only;
4. freezes only complete corrected-exAL bundle winners into a test-audit queue;
5. leaves test, registry, article, joint, and MCMC actions blocked.

No candidate is article-relevant at R66 closeout alone. A later, explicitly
authorized stage must audit each frozen candidate on test against both the
current authoritative Q-DESN result and cached PriceFM, then require complete
seven-quantile reproducibility and manifest hashes before any promotion.

## Explicitly prohibited during R66

- opening test data during preparation, fitting, gate evaluation, or closeout;
- reusing any R65 structured-exAL fit;
- changing case-specific DESN, information-set, RHS-NS, or training contracts;
- selecting AL/exAL separately by quantile;
- fitting joint models or MCMC;
- mutating the decision registry or article;
- deleting R65 checkpoints before R66 finishes;
- touching GloFAS, joint-QVP, individual-validation, or unrelated jobs.
