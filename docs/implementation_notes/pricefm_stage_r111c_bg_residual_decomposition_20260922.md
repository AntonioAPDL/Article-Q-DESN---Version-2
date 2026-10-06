# PriceFM Stage-R111C: BG residual decomposition

## Purpose

Stage-R111B completed all 51 tasks without failure. Its mixed-exposure AL readout reduced pooled BG AQL from 12.21527 to 11.11211, beat the cached PriceFM surface at 11.49281, and improved every fold relative to R110. It nevertheless remained 2.63% above the R97 direct reference at 10.82717 and narrowly missed the preregistered 10% R110-improvement gate by 0.97 percentage points.

The gate must not be weakened after observing the result. R111C therefore performs no fitting and no additional selection. It decomposes the exact residual using frozen prediction arrays to decide whether another recursive-model experiment is scientifically justified.

This document is also the master closeout plan for the R101--R111 recursive
forecast branch. It separates completed scientific work from future ideas so
that a later chat cannot mistake a useful diagnostic result for permission to
restart a broad campaign.

## Current authority and scope

The complete protocol-valid authority is the 114-row R98 surface constructed
from the region-frozen R97 fits. In this document, `R97 direct reference`
denotes the fold-aligned BG slice of that authority used by R108 and later
diagnostics. Retaining R97 for BG therefore means retaining the corresponding
row of the complete R98 authority, not creating a case-level fallback after
looking at R111B.

R111A and R111B are mechanism experiments. R111A resolved the EE active-neighbor
question, while R111B partially repaired BG. Neither stage authorized a new
authority surface, a broad launch, registry mutation, article mutation, MCMC,
or joint fitting. R111C preserves that boundary.

## Evidence contract

The audit uses four fold-aligned BG validation surfaces:

| Surface | Role |
|---|---|
| R97 direct reference | Current valid Q-DESN authority |
| R110 frozen-readout replay | Pre-exposure-alignment recursive comparator |
| R111B mixed exposure | Completed candidate under diagnosis |
| PriceFM quantile-path surface | External model comparator |

For each of three folds, all surfaces must share exactly the same validation anchors, truth values, seven quantiles, and 96 horizons. R108, R110, and R111B terminal records and their prediction artifacts are hash-verified. The response scaler is recovered from the R111B source manifest and independently hash-verified before predictions are transformed to the original price scale.

No test split, model runner, optimizer, launcher, registry, or manuscript file is touched.

## Decomposition

For truth `y`, quantile forecast `q_tau`, and quantile level `tau`, R111C recomputes

```text
L_tau(y, q_tau) = max(tau (y - q_tau), (tau - 1) (y - q_tau)).
```

It aggregates the same loss by:

1. fold;
2. each of the seven quantiles;
3. exact horizon;
4. 24-hour horizon blocks;
5. forecast origin;
6. fold-by-block-by-quantile cells.

It also recomputes interval coverage, interval width, crossing, median MAE, and median RMSE. Gap-attribution columns are weighted by their exact number of loss atoms and must sum back to the pooled R111B-minus-R97 AQL difference.

## Audited diagnosis

The frozen predictions show a coherent pattern:

- R111B beats PriceFM in every fold and by 3.31% pooled.
- R111B beats R97 in fold 1 but loses in folds 2 and 3.
- R111B beats R97 over horizons 1--24 by about 1.05 AQL points.
- R111B loses to R97 over horizons 25--48, 49--72, and 73--96.
- Every quantile has a positive pooled R111B-minus-R97 gap.
- The largest residual cells concentrate in fold 3 at horizons 49--72 and fold 2 at horizons 73--96.

This rules against a single tail, crossing, or simple interval-calibration explanation. Exposure alignment repaired a real mismatch, but recursive target-driver error continues accumulating after the first forecast day. R97 avoids that recursive state-transfer burden and remains the stronger valid authority.

## Historical mechanism audit

The optimal decision depends on the complete chain, not only the final AQL:

| Stage | Question | Audited conclusion | Consequence |
|---|---|---|---|
| R98 | Which complete surface is protocol-valid? | All 114 rows were frozen without test-driven case mixing. | Retain the complete R98/R97 authority. |
| R107 | Are more VB iterations the missing repair? | Exact-200 and exact-500 fits were practically equivalent. | Do not spend more iterations on the same objective. |
| R108 | Is endogenous-driver quality material? | Fold-aligned counterfactuals showed that it is. | Diagnose the Normal driver before downstream refits. |
| R109 | Can a saved Normal driver be reused? | Neither saved driver passed the continuation gate. | Permit only a bounded standalone redesign. |
| R110C | Is path representation alone sufficient? | Raw paths won selection, but confirmation failed. | Do not launch all regions. |
| R110D | Which focus mechanisms remain admissible? | EE neighbor completion was admissible; broad work was not. | Run only the bounded EE mechanism stage. |
| R111A | Does completing EE neighbors work? | All mechanism gates passed. | Preserve the EE finding without promoting authority. |
| R111B | Does exposure-aligned BG readout close the gap? | It repaired R110 and beat PriceFM, but missed the fixed gate and R97. | Decompose the residual without refitting. |
| R111C | What remains after the BG repair? | Loss accumulates after hour 24 across all quantiles. | Stop the recursive branch and retain R97. |

This sequence eliminates the plausible low-cost alternatives in the correct
order. Another iteration increase would repeat R107; another saved-driver
replay would repeat R109; another path representation would repeat R110C; and
another BG exposure arm would tune the same validation evidence after R111B.
None is an admissible continuation.

## Alternatives considered

### Launch a broad R112 recursive campaign

Rejected. R111B's fixed mechanism gate failed, R111C shows that the residual is
not confined to a correctable quantile or interval statistic, and no independent
training-only criterion has selected a new mechanism. Scaling a failed focus
mechanism to 38 regions would be expensive and scientifically weaker.

### Relax the 10 percent R111B gain gate

Rejected. The observed gain was 9.03 percent. Changing the threshold after
seeing that value would make the gate outcome-dependent. R111B remains useful
diagnostic evidence without being relabelled a pass.

### Promote R111B because it beats PriceFM

Rejected. R111B beats the cached PriceFM surface in all BG folds, but the
prospective comparator set also contains the current valid Q-DESN authority.
R111B is 2.63 percent worse than R97 pooled and only wins fold 1.

### Continue tuning calibration or tails

Rejected for this branch. Every quantile has a positive pooled gap against R97,
there are no crossings, and the sign reversal occurs by horizon block. A simple
tail or interval-width correction cannot explain that geometry.

### Preserve the work and stop fitting

Accepted. It retains all scientific information, avoids validation reuse, and
leaves a clean starting point for a genuinely new training-only question.

## Frozen decision

R111C must produce:

```text
residual_classification = late_horizon_recursive_transfer_not_single_quantile_calibration
recommended_action = stop_recursive_redesign_retain_R97
article_classification = diagnostic_only_no_promotion
```

Accordingly:

- do not launch a broad R112 recursive campaign;
- do not tune another BG exposure arm on these validation results;
- do not promote R111B to the registry or article;
- retain R97 as the BG authority;
- preserve R111B/R111C as reproducible diagnostic evidence;
- hand the frozen PriceFM lane to integration only when the broader valid R97 authority is ready for publication.

Future PriceFM work should address weak regions through preregistered, training-only Normal Ridge/Normal RHS screening rather than further post-hoc optimization of this BG validation surface.

## Implemented work plan

The following work is complete and reproducible:

1. validate R98, R107--R111B summary contracts and mutation guards;
2. hash-verify every R108, R110, and R111B BG terminal and prediction surface;
3. recover and hash-verify the response scalers from the frozen source manifests;
4. recompute R97, R110, R111B, and PriceFM metrics on identical folds,
   origins, quantiles, and horizons;
5. decompose the residual by fold, quantile, exact horizon, 24-hour block,
   origin, and fold-block-quantile cell;
6. audit coverage, width, crossings, median MAE, and median RMSE;
7. produce weighted attribution whose strata sum to the pooled AQL gap;
8. materialize the historical mechanism matrix, implementation ledger,
   source manifest, decision JSON, and Markdown report;
9. enforce explicit no-fit, no-launch, no-test, no-registry, and no-article
   state in the terminal summary.

There are zero unfinished model fits in this branch. Work that remains blocked
is deliberately not an implementation backlog: a broad R112 launch and
registry/article promotion are prohibited by the frozen evidence.

## Efficient progression after closeout

1. Freeze R111A--R111C runtime artifacts and their hash manifests.
2. Integrate the reproducibility code through the coordinator without treating
   R111A or R111B as article authority.
3. Publish the complete R98/R97 validity-first authority only through its
   existing coordinator-reviewed package.
4. If further predictive improvement is pursued, write a new preregistration
   using only training-contained Normal Ridge/Normal RHS screening in weak
   regions. It must define its region scope, selection statistic, compute
   budget, and validation gate before fitting.
5. Do not reuse the BG R111B validation outcomes to select that future model.

This is more efficient than another recursive continuation because it closes a
fully investigated branch and reserves compute for a new question with an
independent selection rule.

## Outputs

The script materializes metric CSVs, a historical mechanism audit, an
implementation ledger, JSON, Markdown, and a source manifest under:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/
pricefm_stage_r111c_bg_residual_decomposition_20260922
```

The output is deterministic and contains no model objects or duplicated heavy prediction arrays.
