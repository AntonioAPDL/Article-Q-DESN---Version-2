# PriceFM R125 frozen internal diagnosis

The bounded diagnostic completed on Jerez on 2026-10-06: 9/9 cells,
108 origin/candidate combinations, 90 operator/cell score sets, zero failures,
zero active/pending workers and zero model refits. All 83 frozen output hashes
verified on both hosts. All 432 input/reference hashes remained unchanged,
including the 216 original fitted-model artifacts. A bit-identical Muscat
mirror independently reproduced all 90 metric sets with zero difference.
Storage is 6.582 MiB; no RDS/RDA/RData was created or removed.

Executed source remains frozen at 3c3bc986ea0c5d7b2bba39ceba7e0db048b208b3
on work/pricefm-r125-forecast-estimand-20261006, clean and pushed on both
hosts. This separate closeout adds metadata only; it is not executed source.
The companion config records exact source lineage, metrics and evidence hashes.
Both hosts passed 456 Python tests and four pinned R suites without failures,
errors or skips. The real two-origin S=500 smoke reproduced R124 controls.

## Matched internal evidence

These are twelve predetermined validation origins per candidate/internal split
inside BG outer Fold 1 training, not official folds. AQL is training-scaled
price. All candidates, coefficients, priors, tau0 and reservoirs are unchanged.

| Candidate | Original mean-curve AQL | Clipped CDF-pool AQL | Linear CDF-pool AQL | Raw coverage 80% | Clipped coverage 80% |
|---|---:|---:|---:|---:|---:|
| A | 0.06892978 | 0.06332527 | 0.06335636 | 38.0% | 81.6% |
| B | 0.06762836 | 0.06526223 | 0.06513446 | 56.1% | 69.0% |
| C | 0.08186491 | 0.07509419 | 0.07504252 | 36.0% | 67.6% |

Clipped-pool AQL improves 8.13%, 3.50% and 8.27% for A, B and C respectively.
The matched original controls reproduce R124; these subset means must not be
subtracted from its complete-support means. Sorting crossed curves alone has
very little effect (A 0.06886859, B 0.06752766, C 0.08176744). Most of the
change follows from CDF pooling rather than crossing repair alone. Both tail
rules give similar accuracy but must remain separately reported.

A now leads this small diagnostic and all its AL fits are formally converged.
Its frozen specification is two layers [256,256], m_y=2880, m_x=4,
alpha=.2, rho=.55, input scale=.025, coverage input fan=16,
recurrent sparsity=.05, interlayer gain=.2 and tau0=.0001499045764139044.
This is a promising lead, not a newly promoted region winner. Confirm on the
complete already-available internal supports before changing the selection.
No new screening or model refitting is needed for that confirmation.

## Interpretation and remaining limits

Average conditional quantiles are not generally quantiles of a mixture CDF.
The new diagnostic builds normalized distributions from sorted seven-level
curves, then inverts their average CDF. Seven knots do not identify the tails;
clipped and linear rules, unweighted knot sorting and independent-level
posterior coupling are explicit diagnostic conventions, not a uniquely
identified predictive likelihood. No AL scale posterior is invented.

The oracle-state clipped-pool AQL is A=0.02717164, B=0.04480381,
C=0.03320283. This suggests substantial room to improve the generated price
driver even after the forecast-quantity change; it does not prove this is the
sole cause. Oracle arms use future target truth and can never be selected or
published. A/C demonstrate that the observed band issue is not restricted to
B's 21 capped fits. B's compact exports lack full RHS/latent/covariance state,
so neither exact continuation nor full stationarity can be certified from
apparently flat saved raw ELBO traces. The nine-page PDF includes those traces.

## Promotion question and next order

The current main R98 registry has 38 regions and 114 region/fold cases.
BG official test mean AQL is current QDESN 9.65948446 and cached PriceFM
Phase-I 8.53975727 EUR/MWh. No new matched official-fold forecasts exist here.
Internal scaled AQL cannot establish that the new model beats either reference.
No registry, manuscript, main or Overleaf update is authorized by this stage.

The immediate efficient next step is a complete-support training-only
forecast-operator confirmation using the same frozen fits and both tail rules.
The small subset changed A/B ranking, so jumping directly to new full fits
would choose prematurely. After freezing the intended operator and region
specification, separately prepare the three full BG training-window Normal
fits plus 21 independent AL fits. Internal partial-window fits cannot be
relabeled full-fold fits. Use the strict matched comparison validator to align
actual cached comparators, origins, seven levels, H=96 and EUR/MWh units.
Report the prespecified mean across all relevant regions/folds, not a per-case
dual-comparator gate or test-picked family. Disclose prior test exposure as a
retrospective evaluation. Only completed whole-cohort evidence can justify
coordinator promotion and a broader performance claim.

No downstream launch occurs automatically. All runtime evidence and local
plans remain ignored. No new scientific article assets are approved.

NOT_READY_FOR_INTEGRATION
