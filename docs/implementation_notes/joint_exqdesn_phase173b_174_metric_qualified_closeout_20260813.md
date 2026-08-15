# Joint exQDESN Phase 173B/174 Metric-Qualified Closeout

## Scope

This closeout is confined to the 16 exAL cells in the balanced joint-QDESN
simulation study: eight mechanisms under the joint readout and the same eight
under independent single-quantile readouts. It consumes the completed Phase 173
exact-M0 audit without rerunning MCMC. The 16 AL cells, model specifications,
fixtures, quantile grid, scoring contract, and article repository remain
unchanged.

Phase 173B separates three questions that the original Phase 173 gate reported
together:

1. Is the implementation and scored monotone quantile-grid contract valid?
2. Is the posterior quantile path stable enough for the article estimand?
3. Are remaining warnings confined to scalar or coordinate-level mixing?

This separation is necessary because the article validates posterior quantile
grids, not a scalar predictive density and not gamma in isolation.

## Prospective method rule

Phase 170 selected `M0_v_collapsed_support_logit` before the article-fixture
campaign. Phase 173B therefore does not choose between historical and M0 rows
using the realized forecast score. A functionally qualified case uses M0 even
when its realized metric is worse. A historical exAL row is retained only when
the M0 implementation fails or the reported quantile functional is held.

The primary metric direction is recorded separately:

`M0 forecast oracle-quantile MAE - historical forecast oracle-quantile MAE`.

Negative values favor M0. The label `clear_improvement` requires a negative
difference larger than twice the available M0 chain-jackknife MCSE;
`directional_improvement` records a smaller negative difference. These labels
are Monte Carlo sensitivity descriptions, not significance tests, because a
comparable historical jackknife MCSE is not always available.

## Versioned functional policy

The policy is frozen in
`application/config/joint_exqdesn_phase173b_promotion_policy_v1.csv`.

- Ideal qhat partition stability uses the existing Phase 173 criteria:
  99th-percentile standardized difference at most 0.25 and first-percentile
  central-90% overlap at least 0.80.
- A natural review envelope doubles the standardized-difference ceiling to
  0.50 and relaxes overlap by ten percentage points to 0.70.
- Posterior mean, median, and 10% trimmed-mean forecast MAE must agree in
  direction and have a range no larger than the greater of 0.005 and 5% of the
  historical forecast MAE.
- Leave-one-chain-out evidence must remain at pass or review, never hold.
- Severe beta/alpha or transformed shape-coordinate diagnostics are accepted
  only when qhat remains inside the versioned envelope and posterior-summary
  and leave-one-chain-out checks pass.
- Nonfinite output, invalid support, missing initialization, leakage, or a
  contract crossing remains a hard failure.

These review limits are closeout diagnostics rather than a preregistered
statistical test. They are explicit, inspectable, and applied to every case.

## Results

Phase 173 completed all 16 cells and 128 chains with no implementation failure
and zero contract crossings. Its 51-file manifest verified completely.

Phase 173B produced the following hybrid decision:

| Decision | Cells |
|---|---:|
| M0 with mixing qualification | 11 |
| Historical exAL retained for functional hold | 5 |
| Hard candidate failure | 0 |
| M0 forecast-MAE improvements observed | 5 |
| M0 forecast-MAE improvements selected | 3 |

The selected M0 improvements are:

- independent Gaussian-mixture bridge;
- joint Laplace bridge;
- independent nonlinear reservoir-friendly dynamics.

Two favorable M0 point estimates were not promoted:

- independent Laplace bridge exceeded the qhat review envelope and changed
  direction across posterior mean/median/trimmed summaries;
- independent regime shift had a materially large posterior-summary range.

The remaining historical fallbacks are independent normal bridge, independent
persistent heavy tail, and joint regime shift. Their fallback is driven by
quantile-path or posterior-summary evidence, not by an unfavorable score alone.

M0 improved fit-window oracle-quantile MAE in all 16 cells. Forecast-window
performance was less uniform: five forecast-MAE and six check-loss improvements
were observed. This confirms that better in-sample posterior quantile recovery
does not imply a universal forecast improvement.

## Phase 174 packet

Phase 174 composes a complete 32-cell packet:

- all 16 AL rows remain value-identical to the Phase 155 source;
- 11 exAL rows trace to the Phase 173 M0 manifest;
- five exAL rows trace to the verified Phase 155 historical packet;
- every row records its source directory, source manifest hash, Phase 173B
  action, metric direction, and mixing qualification;
- all scores are finite and all contract crossing counts are zero;
- 31 raw adjacent-level crossings remain in the combined fit/forecast packet,
  including 25 in the forecast window, and remain pre-contract diagnostics;
- numerical winners are descriptive because complete winner-versus-runner MCSE
  is unavailable whenever a frozen historical row is involved.

Fourteen article-safe CSV/LaTeX assets are generated only under the ignored
staging directory. The staging audit verifies that the 14 currently tracked
article assets remain unchanged. Phase 175 promotion is not performed here.

## Artifacts

- Phase 173 source:
  `application/cache/joint_exqdesn_phase173_m0_balanced_article_audit_20260809`
- Phase 173B decision:
  `application/cache/joint_exqdesn_phase173b_metric_qualified_promotion_20260813`
- Phase 174 packet:
  `application/cache/joint_qdesn_phase174_balanced_mcmc_final_20260809`
- Phase 174 staging:
  `application/cache/joint_qdesn_phase174_article_assets_staging_20260809`
- Frozen integration handoff, generated only after branch synchronization:
  `application/cache/joint_exqdesn_phase174_integration_handoff_20260813`

All generated directories remain ignored runtime evidence. Each has its own
SHA-256 artifact manifest. No `.RData`, `.rda`, or `.rds` workspace is added.

The focused Phase 171-175, inference-dispatch, Phase 167-169, Phase 169R,
Phase 170, and Phase 155 tests pass. The older Phase 154 source-reconstruction
test cannot be rerun from retained storage because its Phase 124C source packet
was intentionally compacted in the previously documented legacy cleanup. This
does not affect the frozen Phase 155 artifact consumed here: its manifest
verifies, and its article-promotion regression passes. The limitation remains
recorded for integration review rather than being repaired by recreating or
silently substituting legacy evidence.

## Commands

```bash
Rscript application/scripts/238_audit_joint_exqdesn_phase173b_metric_qualified_promotion.R
Rscript application/scripts/237_build_joint_qdesn_phase174_article_assets_staging.R
Rscript application/scripts/239_freeze_joint_exqdesn_phase174_integration_handoff.R \
  --transcript-path <codex-session-jsonl>
```

Use `--force` only to quarantine and deterministically rebuild an existing
generated packet. No command launches a sampler.

## Integration boundary

This scientific lane commits and pushes only its dedicated task branch. It does
not merge or push `origin/main`, `overleaf/article-snapshot`, or
`overleaf-direct/main`. The integration chat must verify the frozen handoff,
merge the task branch, rerun tests, review the staged table differences,
compile the manuscript twice, and publish only the allow-listed article assets.

Article wording must retain four qualifications:

1. MCMC supplies posterior quantile-grid summaries, not a scalar predictive
   density derived from the composite exAL working likelihood.
2. Raw crossings are diagnostics; reported scores use the monotone contract.
3. M0 improves fit recovery uniformly but forecast recovery selectively.
4. Updated exAL evidence is used only for functionally qualified cells; five
   historical rows remain because the M0 quantile functional was not stable
   enough for promotion.
