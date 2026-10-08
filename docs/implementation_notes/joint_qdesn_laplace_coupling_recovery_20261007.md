# JOINT Laplace Coupling Recovery

## Decision

The source screen at HEAD 80e2c887188071349395d2784a42fef7f08e7033
completed 32/32 MCMC workers and 16/16 score cells with no worker failures. It
stopped correctly before selection because the second AL baseline replicate had
a localized tau-.75 quantile-functional R-hat of 1.849955, above the frozen hard
threshold 1.5. Aggregate score R-hat was 1.240635, relative chain score range
1.34%, state-half difference .12%, scores finite, and contract crossings zero.
This is neither a missing-output failure nor evidence that all models must be
refitted.

The recovery preserves that source runtime exactly. It does not weaken the old
gate, rewrite the old selection history, modify the DESN, retune tau0, alter the
forecast or score, or change M0/VB1. It copies sealed inputs into a new runtime,
adds two fresh chains to each of the three affected dataset-2 AL joint cells,
and recomputes those cells using four chains. Every exAL result and the first AL
replicate are reused from sealed source evidence.

## Frozen Recovery Rule

The six supplemental chains use the same data, training-calibrated controls,
VB initializers, 2,000-iteration AL budget, burn 500, thin 2, and target hashes.
Only seeds are new and frozen. Recovered summaries replace source cells 9-11 in
an explicitly versioned audit packet; the original summaries remain present.

Selection is performed separately for AL and exAL. A likelihood advances only
if its baseline is hard-eligible. Among eligible arms, the lowest matched mean
DGP-integrated score wins when its improvement is positive; otherwise baseline
is retained. Review-level scalar or functional diagnostics below the hard gate
do not veto a mean gain. A likelihood whose baseline remains ineligible is
reported as blocked and is not forced into confirmation. This allows exAL to
continue even if AL remains unresolved.

Fresh confirmation uses the original two protected DGP replicates, three chains,
long budgets, mean-reservoir recursive forecast, seven-level score grid and
case-specific Laplace DESN. Depending on recovered eligibility, confirmation has
18 workers for one qualifying likelihood or 24-36 under baseline/challenger
combinations. No article fixture is used.

## Reproducibility and Boundaries

The recovery root records the source path, expected source HEAD, hashes of all
critical source evidence, a copy of all 16 source score summaries, sealed dataset
2 context/oracle/calibration, three warmups, and six original chains. Current
source files and execution HEAD are independently frozen. The launcher is Jerez
only, requires a clean pushed dedicated branch, applies physical-core capacity
gates both before and after preparation, pins the controller to the reserved set
and one numerical thread per worker, resumes only unsealed work, and fails closed.

Runtime, draws, copied models, logs, PDFs, and local trackers remain ignored.
Commit and push only the dedicated recovery branch. Do not merge main, modify
the source runtime, update article files, or publish Overleaf. A matched article
fixture remains necessary before authority can change.

Focused verification:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla application/tests/test_joint_qdesn_laplace_coupling_recovery.R
bash -n application/scripts/launch_joint_qdesn_laplace_coupling_recovery.sh
bash application/tests/test_joint_exqdesn_cpu_queue.sh
```

After closeout, the handoff must report both source and recovery branches/HEADs,
exact counts, selection status by likelihood, manifests and hashes, tests,
storage, article-safe files, exclusions, risks, and READY/NOT_READY status.

## Schema-Safe Continuation

The first recovery execution completed all six supplemental chains, then failed
closed before selection when the frozen source-chain metadata (26 columns) and
new recovery-chain metadata (28 columns) reached a positional `rbind`. The two
additional columns, `source_cell_id` and `source_worker_id`, are provenance only.
All 12 chains have 750 finite retained draws, matching within-cell target hashes,
and verified manifests. No model fit failed and no MCMC rerun is warranted.

The continuation does not edit or resume that frozen failed runtime under a new
HEAD. It verifies the predecessor freeze, exact expected failure, source pointer,
screen plan, and all 12 chain manifests; imports only workers 3, 4, 7, 8, 11 and
12 into a fresh runtime; records every imported file by size and SHA-256; and
freezes the new runtime under the corrected commit. Source workers 1, 2, 5, 6,
9 and 10 continue to come directly from the original source campaign.

Scoring reuses the frozen source scorer and intercepts only its metadata bind,
aligning data-frame columns by name after validating the invariant metadata
fields. The same schema-safe binder is used when recovered summaries replace
source cells 9-11. Forecast construction, score computation, diagnostics,
eligibility, selection, DESN controls, priors, seeds, M0 and VB1 are unchanged.

The continuation launch form is:

```bash
bash application/scripts/launch_joint_qdesn_laplace_coupling_recovery.sh \
  "$NEW_ROOT" "$SOURCE_ROOT" "$CPUS" continuation "$FAILED_RECOVERY_ROOT"
```

It first reruns only the three affected scores. Selection then determines an
18-worker exAL-only confirmation, a 30-worker exAL-plus-AL-baseline confirmation,
or a 36-worker two-challenger confirmation. Completed source and supplemental
chains are never scheduled again.

## Final Closeout: 2026-10-08

The schema-safe continuation completed without refitting any sealed source or
supplemental chain. The final inventory is 32/32 source-screen chains, 6/6
supplemental chains, and 18/18 fresh protected-confirmation chains, with 16/16,
3/3, and 6/6 corresponding score cells. There were no worker failures. All 18
confirmation chains used `M0_v_collapsed_support_logit`, retained 1,500 finite
draws, and agreed on one target hash within each of the six model-replicate
cells. All confirmation score rows are finite, all quantile-functional checks
pass, and forecast contract crossings are zero.

The recovered screen left AL blocked under the original frozen contract because
the baseline maximum functional R-hat was 1.544426, just above the unchanged
1.5 hard gate. Its conditional-variance candidate was eligible and improved
the internal mean score by 0.003037, but it was not forced into confirmation.
For exAL, the relaxed-innovation-slab candidate was selected for confirmation
after an internal mean gain of 0.000329.

Fresh protected confirmation reversed that small exAL screen gain:

| Model | Mean DGP-integrated score | Mean 95% width | Canonical score | Fit oracle MAE |
|---|---:|---:|---:|---:|
| Independent exAL | 0.405934 | 0.065639 | 0.395803 | 0.125355 |
| Joint exAL baseline | 0.486456 | 0.202751 | 0.476564 | 0.148016 |
| Joint exAL relaxed slab | 0.489506 | 0.210895 | 0.479350 | 0.147360 |

The relaxed arm was worse than the joint baseline by 0.627% in mean score and
4.017% in interval width, and it improved neither protected replicate. Both
candidate-minus-baseline posterior contrast intervals include zero. The joint
baseline and relaxed arm remain much more coherent than independent exAL,
reducing raw crossings by about 96.5%, but both have substantially worse scores
and intervals about three times as wide. Because aggregate score and functional
diagnostics pass, this overspread is not explained by unresolved scalar or
functional MCMC mixing. It is a predictive score/coherence tradeoff under this
readout-prior structure.

The scientific decision is `retain_baseline_review`. Do not promote the relaxed
slab, rerun it with more chains, change the article authority, or reuse the
protected confirmation as a new tuning window. Integration should preserve the
schema repair and the audited negative result. A future AL-only confirmation is
scientifically distinct and may be considered on a new post-integration branch:
the conditional-variance arm had a larger internal gain and passed its own
functional gate, but any such experiment must freeze a new review-level baseline
policy prospectively rather than rewrite this completed contract.

The complete Jerez runtime remains ignored at 537 MiB. A 280 KiB compact packet
containing the freeze, selection, confirmation, and closeout evidence was copied
to the matching ignored Muscat cache path and independently hash-verified. The
tracked coordinator handoff is
`docs/implementation_notes/joint_qdesn_laplace_coupling_recovery_integration_handoff_20261008.md`.
