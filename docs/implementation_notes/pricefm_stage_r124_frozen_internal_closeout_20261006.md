# PriceFM R124 frozen internal closeout

## Completion and source separation

All nine forecast panels completed on Jerez with zero failures, 1,302 scored
origin/candidate combinations, 500 paths per origin, and zero model refits.
The 63 independent AL VB fits and nine certified Normal parents were reused.
All 216 input artifact hashes were unchanged. The completed evidence ledger
verified 83 files; the entire compact campaign occupies 20.134 MiB. All replay
workers exited. No official validation/test window or article registry opened.

Executed source remains frozen at 0924e857ba74a499a22712db0f99b6de711d7d01
on work/pricefm-r124-covariance-replay-20261006 on both hosts, clean and pushed.
Scientific fits remain owned by 40d42d15a477c2f9d50dbc69b4eb9885da91ec29;
the reservoir source is 7ae8d6f578000ab17cd30567a23f7b806028cee0.
This closeout is metadata-only on a separate branch from fetched main
e721bfddee81269864febea0eca0bbd0c5eba369. It must not be mislabeled as the
source executed by the replay. The companion config manifest records exact
spec/tau0 anchors, frozen hashes, scores, tests and source identities.

Runtime tag: pricefm_stage_r124_covariance_preserving_replay_v2_20261006.
The initial tag without v2 is preserved separately: its two-origin simulation
completed, but duplicate metadata keywords blocked serialization. No full
workers started there. The v2 regression covers serialization and reuse.

## Matched internal results

These are BG outer-Fold-1 training-internal splits, not the three official
folds or article currency AQL. H=96 quarter-hour steps means 24 hours.
The original unweighted three-split mean-AQL rule remains unchanged.

| Candidate | Split 1 AQL | Split 2 AQL | Split 3 AQL | Mean AQL | 80% coverage |
|---|---:|---:|---:|---:|---:|
| B | 0.079088 | 0.060495 | 0.090569 | 0.076717 | 52.4% |
| A | 0.077365 | 0.069693 | 0.095755 | 0.080938 | 35.3% |
| C | 0.075167 | 0.072119 | 0.100398 | 0.082561 | 38.4% |

B remains the primary quantile-readout leader. Its legacy mean AQL was
0.076763: correcting covariance inflation improved the point estimate by only
about 0.059%. This is not a demonstrated material accuracy improvement.
The numerical correction is nevertheless required: it restores N(m,V), not
N(m,V+jI). All 72 saved covariance and projected-variance checks passed.

Matched-origin Normal-driver diagnostic means are A=0.075082, B=0.076694,
C=0.077996, with 80% coverage 84.9%, 86.7%, 82.0%, respectively. A's Normal
driver has the lowest diagnostic mean AQL; this is not a silent replacement
of the agreed quantile-readout selection criterion or evidence against PriceFM.
For B, mean quantile-band width is 0.303 versus Normal-driver width 0.695.
Primary/path-specific mean AQL differs by about 6e-9 for B and at most 1.1e-7
across candidates: the two averaged operators are effectively identical here.

## What the diagnosis establishes

For sampled future features Z_s from the Normal driver and independently
sampled quantile coefficients beta_(q,s), the current operators are:

```
mean_feature:   mean(beta_q)' mean(Z)
path_specific:  mean(beta_(q,s)' Z_s)
```

Under this independent modular sampling design, both converge to
E(beta_q)'E(Z). Their small difference is finite Monte Carlo pairing noise,
not fundamentally different treatment of a marginal predictive quantile.
Coefficient covariance largely affects Monte Carlo noise in these mean curves;
it does not itself turn their endpoints into predictive-mixture quantiles.

In general E[Q_q(Y | Z, parameters)] is not
Q_q(E[F(Y | Z, parameters)]). The isolated two-component Normal calculation
in the regression tests verifies the distinction. Nominal 80% curves formed
from these averaged conditional quantile functions are not automatically an
80% marginal predictive interval or a posterior credible interval.

The observed undercoverage is therefore not attributable to the removed
covariance inflation. Nor does it establish VB underdispersion or a single
remaining causal mechanism. A/C formally converged yet also under-cover;
cap status alone cannot explain the cross-candidate pattern. Conditional
readout misspecification, shrinkage, driver mismatch and uncertainty pooling
remain distinct hypotheses. B's 21 capped fits still lack full exported
RHS/latent-state stationarity certificates; visible flat ELBO tails do not
replace those certificates.

## Efficient next plan, not launched

1. Keep these corrected fits, scores and prediction arrays frozen. Do not
   repeat Ridge/RHS screening, tune tau0, widen bands ad hoc, force larger
   iteration budgets, or launch MCMC/joint fits merely because coverage is low.
2. Agree on the intended forecast quantity before official evaluation:
   averaged conditional quantile curves or marginal predictive quantiles.
   A marginal prediction needs explicit conditional CDF/working-density
   pooling and inversion, with a declared modular Normal-driver construction;
   averaging quantile functions is not that operation. Do not assume the
   composite joint working likelihood is a normalized generative density.
3. If authorized, do a bounded training-internal operator diagnosis using
   these frozen fits: conditional/oracle-state readout checks, causal
   recursive-state checks, and one explicitly derived CDF-pooling pilot.
   Separate conditional-fit quality, generated-driver quality and pooling
   error. Oracle future prices are diagnostic only, never publishable forecasts.
   Preserve seeds/origins and report conditional versus marginal estimands.
4. Address the capped-fit stationarity gap with the smallest full-state
   diagnostic justified by evidence. A compact warm-start refit is not an
   exact optimizer resumption when latent/RHS states were not saved. Keep
   priors fixed and preserve all formal convergence labels.
5. Only after the operator and acceptance policy are frozen and separately
   authorized, prepare the 24 full-training fits (three Normal, seven AL per
   official fold), using the frozen region specification rather than partial
   internal fits. Match actual cached PriceFM/authority origins, units and
   timestamps. Never use official test outcomes for tuning or claim the
   QDESN-with-PriceFM-driver score is PriceFM's own score.

This revises the earlier route directly to full-fold evaluation: the completed
replay shows essentially unchanged accuracy but a substantial conditional
versus predictive calibration gap. A forecast-only diagnosis is cheaper and
more informative than another broad fit campaign. No next-stage experiment
was implemented or launched during this closeout.

## Tests, evidence and handoff boundaries

Both hosts passed 401 Python tests and four pinned R suites at executed HEAD
0924e857. Exact commands, environments and logs are in each release receipt.
The inherited suite includes an ignored R120 plan-text fixture; reproduce it
by copying the byte-identical fixture from the frozen predecessor worktree,
not inventing a replacement. The four R suites cover sufficient-statistic
Normal fitting, RHS stationarity, prior separation and exact CRAN 1.1.1 AL
initialization. The real smoke verified all eight posterior samplers and
unchanged fit inputs. The nine-panel closeout reconstructed metrics from NPZ
arrays, froze ranking/report evidence, and verified parent ledgers again.

Result ledger SHA256:
c509cc55fdeffcdca8ee2f87f941f677d3c59e0a040608d5c6334fab9ff356e4.
PDF SHA256:
deb56ecc16d55f58aca68e8afe3388a0ad9ec5ff6d2e9737994f5c6ec3edd37b.
Preparation SHA256:
5a74eaba2e957e7aa52a19b9580ce7630091b09b28e6942bf6544986c9de4c82.

Jerez campaign prefix is the canonical DATA/campaigns/TAG. The bit-identical
Muscat copy is DATA/runtime_audits/pricefm_stage_r124_frozen_closeout_20261006/
jerez_campaign. DATA means
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm.
The nine-page PDF was inspected for readable summary and raw-ELBO pages.
An independent read-only Muscat check remapped and verified all 83 frozen
hashes, recomputed all 27 operator/cell metric sets from the NPZ arrays,
checked all 1,302 origins, exact anchors, convergence labels, the closeout
manifest and the hashed Muscat release evidence. It passed without changing
the mirror or generating another forecast. The executed source and tests
were not changed by this metadata-only closeout.
This note and the compact config manifest are source/reproducibility files,
not article-safe performance claims. All data_local/, local_trackers/, fitted
packets, NPZ/bin files, PDFs, libraries, caches and logs remain excluded.

The coordinator may integrate validated code and this source-only closeout
after reviewing the frozen predecessor dependency and rerunning combined
tests. Do not blindly merge the historical lane or overwrite its frozen
worktrees. No article figure/prose/registry or Overleaf publication is ready.

NOT_READY_FOR_INTEGRATION
