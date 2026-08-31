# Joint QDESN Phase181 Score-Stability Extension

Date: 2026-08-26

## 1. Decision

Phase181 is a same-specification Monte Carlo extension of the completed
Phase180 balanced DGP-integrated score packet. It is not another DESN or
regularized-horseshoe calibration screen.

The immutable baseline is:

`application/cache/joint_qdesn_phase180_balanced_dgp_score_packet_20260824`

Its manifest SHA-256 is:

`93287a327f1b820e89de0cb4df295e15f6264fd2f96d157931cd17d23558b3e6`

Phase180 contains 32 finite scenario-model cells, zero contract crossings,
verified worker sources, 15 passing score functionals, and 17 review-level
score functionals. Its implementation hard gates pass; its overall gate is
`review`.

## 2. Reconciled Scientific Goal

The current goal is to improve the Monte Carlo estimate of the case-specific
posterior DGP-integrated finite-grid score without changing the fitted model
specification. Each scenario and model retains its frozen DESN controls,
`tau0`, `zeta2`, prior controls, likelihood, readout structure, article
fixture, forecast design, and seven-level quantile grid.

The user-declared promotion rule is:

1. Require complete manifests, finite posterior draws and scores, verified
   source hashes, and zero contract crossings.
2. Compare the full balanced eight-chain Phase181 posterior score mean with
   the corresponding immutable Phase180 posterior score mean.
3. Promote the Phase181 estimator when its finite mean is strictly lower.
4. Retain Phase180 otherwise.
5. Report R-hat, ESS, raw crossings, monotone adjustments, and chain
   sensitivity, but do not use a review-level mixing diagnostic as a veto.

This rule promotes an estimator/source packet, not a new model specification.
Results with review-level diagnostics remain descriptive and must not be
presented as definitive superiority evidence.

## 3. Audit Findings

### 3.1 Formal score-functional review

Seventeen Phase180 cells fail at least one review threshold for posterior
score R-hat, bulk ESS, or tail ESS. The most important remaining scalar issue
is the alpha/intercept block; the exact-M0 gamma/sigma repair is not the sole
remaining bottleneck.

### 3.2 Chain-sensitive score means

A leave-one-chain-out audit of all 32 Phase180 posterior score means identified
two additional score-pass cells with a relative mean shift above five percent:

- Independent exQDESN RHS, persistent heavy tail: approximately 73.4 percent.
- Independent exQDESN RHS, regime shift: approximately 8.05 percent.

Independent exQDESN RHS for the Laplace bridge has an approximately 97.3
percent shift and is already one of the 17 formal review cells. In all three
cases, chain 2 is the dominant source of the mean shift. This behavior is kept
as evidence; no chain is deleted or trimmed after inspection.

### 3.3 Final extension scope

The deterministic union contains 19 cells:

- seven AL cells;
- twelve exAL cells;
- 152 workers at eight chains per cell.

The remaining 13 cells retain their verified Phase180 sources unless the
extension finalizer detects a hard source defect.

## 4. Why This Is the Minimum Useful Next Stage

Another DESN/`tau0` screen would repeat a question already resolved by the
case-specific Phase179 controls and would confound model tuning with Monte
Carlo stability. Deleting unfavorable chains would bias the posterior summary.
Rerunning all 32 cells would spend compute on 13 cells without an extension
trigger.

The selected design instead uses the longer budgets already predeclared in
the Phase180 master plan:

| Likelihood | Chains | Iterations | Burn | Thin | Retained per chain |
|---|---:|---:|---:|---:|---:|
| AL | 8 | 24,000 | 4,000 | 4 | 5,000 |
| exAL exact M0 | 8 | 48,000 | 8,000 | 8 | 5,000 |

All exAL chains use the support-logit-v2 dispersed gamma starts that repaired
the Phase180 endpoint failures. Chain and independent-quantile component seeds
come from a new disjoint Phase181 namespace.

## 5. Frozen Outputs

Preparation writes:

- `extension_cell_selection_audit.csv`;
- `chain_leave_one_out_audit.csv`;
- `extension_cell_registry.csv`;
- `worker_plan.csv`;
- `component_seed_plan.csv`;
- `vb_initialization.csv`;
- `chain_start_values.csv`;
- `chain_start_preflight.csv`;
- provenance, README, and SHA-256 manifest.

Finalization writes:

- extension-only posterior score draws and summaries;
- `mean_metric_promotion_decisions.csv`;
- the recomposed 32-cell selected source registry;
- the recomposed 32-cell posterior score packet;
- joint-minus-independent contrasts;
- oracle recovery, crossing, parameter, runtime, and source diagnostics;
- final gate assessment, provenance, README, and SHA-256 manifest.

Article staging is separate from manuscript mutation. It may proceed when all
hard gates pass even if mixing remains `review`, but its wording must retain
the descriptive qualification.

## 6. Reproducible Commands

Prepare:

```bash
Rscript application/scripts/279_prepare_joint_qdesn_phase181_score_stability_extension.R \
  --cache-root application/cache --vb-cores 8
```

Health check:

```bash
Rscript application/scripts/281_check_joint_qdesn_phase181_score_stability_extension.R \
  --cache-root application/cache --write
```

Launch with an audited CPU set:

```bash
JOINT_QDESN_PHASE181_CPU_LIST=<comma-separated-cpus> \
JOINT_QDESN_PHASE181_MAX_PARALLEL=40 \
bash application/scripts/285_launch_joint_qdesn_phase181_score_stability_extension.sh
```

Focused tests:

```bash
Rscript application/tests/test_joint_qdesn_phase181_score_stability_extension.R
Rscript application/tests/test_joint_qdesn_phase180_balanced_dgp_score_packet.R
```

## 7. Gates and Interpretation

`fail` is reserved for incomplete or invalid manifests, missing workers,
nonfinite draws or scores, source/hash defects, previsibility defects, or
contract crossings.

`review` records score-functional mixing, scalar-parameter mixing, raw
crossing frequency, monotone-adjustment frequency, or product-posterior
pairing sensitivity.

Promotion is case specific and mean based. A promoted cell with review-level
mixing is usable as the selected finite-run estimator under the user's rule,
but it remains descriptive article evidence. No universal DESN specification
is selected.

## 8. Checklist

- [x] Preserve the immutable Phase180 packet and hashes.
- [x] Reconcile prior extension plans with the current mean-improvement rule.
- [x] Freeze the 19-cell trigger and 152-worker budget.
- [x] Verify compact initialization and support-logit-v2 starts.
- [x] Run 152 independently seeded extension workers.
- [x] Verify every worker and checkpoint manifest.
- [x] Reconstruct extension posterior score functionals.
- [x] Apply strict lower-mean promotion after hard gates.
- [x] Recompose and verify exactly 32 selected cells and 16 contrasts.
- [x] Stage article-safe tables and wording with review disclosure.
- [x] Freeze a clean integration handoff on the dedicated JOINT branch.

Dense-grid fitting remains deferred until this current-grid extension closes.

Phase181 closed with 152/152 workers complete, zero failures, 13 lower-mean
source promotions, 32 finite final cells, 16 joint-minus-independent
contrasts, and zero contract crossings. The final interpretation and ordered
next-stage contract are recorded in
`joint_qdesn_phase181_final_closeout_and_dense_grid_plan_20260830.md`.
