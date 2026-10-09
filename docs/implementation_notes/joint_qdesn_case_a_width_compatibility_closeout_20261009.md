# JOINT Case A Score-Width Compatibility Audit and Closure

Date: 2026-10-09

## Decision

Retain the integrated v2 Asymmetric Laplace Tail specification and stop model
tuning. Do not optimize posterior score-interval width, refit an
independent-only challenger, reopen the architecture screen, or change the
article. The current evidence does not identify an independent-model sampler,
forecast, numerical, or predictive pathology.

This decision is deliberately different from the Laplace Bridge action. The
old Laplace result combined much wider joint intervals with materially worse
joint scores and was replicated under matched controls. Case A instead has
lower joint scores, stable independent score chains, finite predictive
functionals, and zero contract crossings. Its independent interval widths are
moderate in absolute terms and are not exceptional among the eight scenarios.

## Audited Evidence

The audit is bound to the v2 authority derived from `origin/main` commit
`b83a6086dadbb482edaa02427b290fda8e5215b5`. For MCMC:

| Model | Score mean | 95% interval | Width | Score R-hat | Bulk ESS |
| --- | ---: | --- | ---: | ---: | ---: |
| Joint AL | 0.380476 | [0.370515, 0.398501] | 0.027987 | 1.0287 | 194.6 |
| Independent AL | 0.415977 | [0.391040, 0.443547] | 0.052507 | 1.0034 | 3736.1 |
| Joint exAL | 0.373684 | [0.367577, 0.385804] | 0.018228 | 1.0009 | 931.3 |
| Independent exAL | 0.432277 | [0.399755, 0.468327] | 0.068572 | 1.0037 | 3020.0 |

Independent-to-joint width ratios are 1.88 for AL and 3.76 for exAL. The
independent models nevertheless have stronger score-chain diagnostics than
joint AL. Their mean-design half-score differences are 0.000261 and 0.001521,
well below the frozen 0.005 gate, and their maximum chain-score deviations are
0.00241 and 0.00331. Mean-state forecasting narrows all four intervals relative
to recursive path propagation but does not change the ordering. The width
difference is therefore not caused by a bad independent MCMC chain or unstable
state integration.

The expanded architecture changed the tradeoff: joint AL/exAL mean scores
improved by 4.83% and 4.72%, while independent AL/exAL worsened by 3.54% and
7.78%. The specification was selected on a separate Gaussian recursive
calibration window and was shared across the four quantile rows, so this is
not protected-window leakage. It remains an architecture-sensitivity caveat
and does not justify an independent-only rescue.

Most importantly, the fixed-backbone campaign evaluated the same Case A
backbone on two fresh DGP realizations. Average joint versus independent widths
were 0.073586 versus 0.022166 for AL and 0.112755 versus 0.028395 for exAL.
The width ordering therefore reverses outside the article realization. That
reversal is incompatible with a stable independent-model overspread defect.

## Statistical Interpretation

The joint and independent posteriors need not have equal score widths. Joint
models preserve cross-quantile dependence and borrow information across
levels. Independent fits use the declared product-posterior coupling. Their
integrated-score distributions can consequently have different variances even
when both computations are correct.

The reported intervals quantify posterior readout uncertainty conditional on
the averaged recursive design. They are not repeated-DGP confidence intervals,
full posterior-predictive intervals, or a target to minimize. Selecting a
model merely because its interval is narrower could reward excessive
shrinkage. Existing manuscript text already states this conditional scope and
describes numerical comparisons without claiming general superiority.

## Implemented Audit

The deterministic audit consists of:

- `application/config/joint_qdesn_case_a_width_closure_contract_v1.csv`;
- `application/R/joint_qdesn_case_a_width_closure.R`;
- `scripts/audit_joint_qdesn_case_a_width_closure.R`;
- `application/tests/test_joint_qdesn_case_a_width_closure.R`.

It verifies hashes for the tracked v2 sources and the two frozen external
closeout packets, reconstructs current and fresh-seed width ratios, checks
score and mean-design stability, records architecture sensitivity, and audits
the existing manuscript wording. It fails closed on source drift. Outputs are
compact ignored receipts; no posterior object or model output enters Git.

Run from the dedicated worktree with:

```bash
Rscript scripts/audit_joint_qdesn_case_a_width_closure.R \
  "$PWD" \
  <fixed-backbone-confirmation-scores.csv> \
  <expanded-changed-case-comparison.csv> \
  <expanded-mean-design-diagnostics.csv> \
  local_trackers/joint_qdesn_case_a_width_closure_20261009
```

Expected decision: `retain_case_a_v2_no_retuning`.

## Future Trigger

No new run is recommended. If a reviewer later requires population-level
robustness, the next admissible experiment is replication-only: freeze the
current specification and priors, use fresh DGP seeds, fit all four models
symmetrically, retain exact M0 for exAL, and estimate the distribution of
joint-minus-independent scores and width ratios. It must not select an
architecture or use the article realization for tuning.

Architecture re-ranking becomes appropriate only if repeated fresh-seed
evidence shows nonfinite scores, unstable predictive functionals, pathological
fit/forecast recovery, or a reproducible implementation-specific defect.
Width inequality by itself is not such a trigger.

## Checklist

- [x] Refresh and bind the latest integrated v2 authority.
- [x] Confirm no active JOINT workers or tmux sessions.
- [x] Separate current-width differences from MCMC and state-integration failure.
- [x] Audit the preceding architecture's joint/independent tradeoff.
- [x] Verify the fresh-seed reversal under the same Case A backbone.
- [x] Confirm existing article language is already appropriately conditional.
- [x] Implement a hash-bound deterministic audit and focused regression test.
- [x] Run the focused test and complete frozen-source audit.
- [x] Commit and push the dedicated JOINT branch.

No article, Overleaf, main, GloFAS, PriceFM, dense-grid, or fitted-model file is
modified by this closure.
