# PriceFM R123: Bounded Connectivity and Capacity Refinement

## Purpose and evidence

BG is the pilot region. This is a successor experiment, not a restart,
replacement or alteration of the completed R122 campaign. The R122 fit revision
is `0d168bf1a596631f9da8bb861d4c236da924b9ac`; its completed diagnostic revision
is `8fb145e3e83963f5edf01dbfe9d2ae341e89be80`. R122 completed 6,720 Ridge cells,
348 Normal RHS fits and 63 independent AL VB fits. All nine ladders passed the
numerical gate; 24 atoms formally converged and 39 reached the cap. Neither
formal convergence nor a successful campaign proves global optimality.

R122's frozen winner has D=2, widths [128,128], m_y=2016, m_x=0, alpha=.1,
rho=.7, input scale=.05, fan=8 and graph-mean exogenous summaries. Its pure
all-layer readout has 257 coefficients. The reconstructed reservoir SHA256 is
`fe2d590be516872054e9efee5006716212f0ab36513d3fbbb67c2eef3dc26d49`.
Current-exogenous row degrees are [0,0,0,1,4,0], including zero connections
for all three BG channels. Only 782 of 2,016 price-lag coordinates are connected.
This is a legitimate sparse restriction, not leakage, and is NOT yet a proven
cause of the forecast weakness. Raw lag order is not effective information access.

Full internal AL AQL is .07086814 versus .07975937 for the earlier Stage-0B
winner, an 11.15% reduction on the same validation timestamps. Training support
differs. The matched 36-origin diagnostic gave mean-feature AQL .06136721,
80% coverage 50.75%; the stochastic Normal driver gave .06183564 and 91.98%.
Oracle preceding-price histories reduced AL AQL to .03658942 but are NOT
deployable or selectable. These processed-unit subset numbers cannot be
compared directly with official currency-unit PriceFM/R97 results.

## Fixed scientific boundaries

- Select only within Fold-1 training, using its existing 940 daily origins and
  expanding train/validation counts 506/125, 631/135, 766/174.
- Standardize separately on each internal training subset. Teacher-force the
  historical state at each new origin. Recursively generate future price lags
  within its 96-step, 24-hour forecast. One step is 15 minutes, not an hour.
- The current exogenous vector at time t predicts y_t; endogenous lags end at
  y_(t-1). Future exogenous inputs retain the existing retrospective availability
  convention. No future observed price enters a deployable path.
- Readout remains `[1,h1,...,hD]`, with no ARX input bypass, calendar or new
  horizon feature. No official validation/test file is loaded in this campaign.
- Fixed reservoir seeds are reused for paired comparisons; the canonical
  first seed defines downstream fits, never the seed with the best test score.
- This does not open an exAL, joint or MCMC campaign. Those require a separate
  scientifically justified protocol. No current MCMC winner is established here.
- No registry, manuscript, authority or Overleaf mutation. Historical tests have
  been viewed; any eventual benchmark is retrospective, not a pristine test.

## Implemented DAG

1. Freeze source/runtime/input hashes and completed parent evidence. Require a
   clean committed task checkout and a ten-second distinct-physical-core audit.
   At most 15 single-thread workers, 200 GiB memory and disk floors. Check again
   before the RHS stage. Stop scheduling at any failed computational gate.
2. Run focused independent Normal/AL prior tests using the exact frozen Normal
   runtime and exact CRAN exdqlm 1.1.1. Neither package is upgraded or patched.
3. Replay the three frozen R122 finalists on 12 predetermined origins in each
   internal split, 500 paths, without refitting. Retain mean-feature, path-mean
   and Normal-driver controls. Add two explicitly diagnostic quantile-function
   reconstructions, with clipped versus linearly extrapolated tails. Sorting
   repairs quantile crossings and reports their frequency. Seven independent
   AL working densities are never claimed to define one predictive density.
   Neither tail rule selects a winner or changes the primary scoring objective.
4. Evaluate 24 connectivity structures with two seeds: two graph policies,
   three exogenous-lag orders (0,24,96), and uniform fan8 / coverage fan8 /
   balanced fan8 / balanced fan32. The same-fan recurrent matrices are paired.
   Uniform unchanged controls reuse archived statistics and scores only after
   source/hash/specification/reservoir checks. Missing evidence fails closed.
5. Choose coverage versus balanced using equal-weight training-internal pilot
   AQL, then late AQL. Both guarantee current-exogenous and named recent/seasonal
   price-lag connections. Balanced weights allocate half the expected input
   energy to price and half to exogenous groups, preventing lag-count dilution.
   This compares input designs, not an identified causal contribution of each
   covariate. The fan32 sentinel also changes connection count.
6. Freeze 600 new, deterministic, non-Cartesian capacity structures. Retain the
   pilot cells as controls. Uniform controls are displayed but excluded from
   downstream refits: the new family requires guaranteed current-input access.
   Two seeds per new structure; third seed for the best
   50 complete structures. This is a bounded search, not an assertion that the
   global optimal DESN was found. Deep/slow candidates fail a score-blind 240-step
   paired-initial-state washout test if discrepancy exceeds .001. They are
   recorded as rejected, not silently given a different training window.
7. Fit the best 30 complete three-seed structures under Normal RHS on all three
   splits at a dimension-adjusted tau center. For the leading 10 only, try .3
   and 3 times that center, reusing the center fits. No many-order tau expansion.
   With r=p-1, m0=min(20,max(5,round(sqrt(r)))), center is
   `(m0/(r-m0))/sqrt(766*96)`. This is a fixed reference-size heuristic for the
   project's product-prior convention, not a universal optimal tau formula.
8. Pick three distinct DESN structures from complete Normal RHS results. Fit
   seven independent AL levels on all three splits: .50 -> .45/.55 -> .25/.75
   -> .10/.90, using upstream fits only as initial states. Existing 1,000-iteration
   and score-blind numerical gates remain; a 750-iteration companion is run only
   when the existing paired-cap gate is needed. Maximum primary panel: 63 atoms.
9. Freeze full internal metrics, source hashes, accepted/capped counts and the
   final internal choice. A completed internal phase is NOT article promotion.
   The official validation/refit/test and coordinator publication stage remains
   separately gated. Do not retune on later-fold tests or require each individual
   region/fold to beat both reference models.

## Parameter space and rationale

Capacity-matched architectures: D2 widths128/192/256; D3 widths96/128/192;
D4 widths64/96/128; D6 widths48/64/96; D8 widths32/48/64; tapers
[192,128,96] and [128,96,64,48]. Limit pure readout to 577 coefficients.
Exactly 36 D8 sentinels; do not scale every layer to width300.

m_y: 960,1152,1344,1560,1728,2016,2304,2688,2880. Primary m_x:
0,4,12,24,48,96; exactly 60 sentinels at192/336/672. The current 3,120-row
source supports these with the fixed240 washout. Larger than2,880 needs a new
common-support data contract, not merely a larger loop bound.

alpha: .05,.075,.1,.15,.2,.3; rho: .55,.65,.7,.82,.9,.95; external input scale:
.01,.025,.05,.1,.2; **separate inter-layer gain**: .05,.1,.2,.5,1.0; input
fan8/16/32/64; recurrent density .02/.05/.1. All four existing local/graph
exogenous policies are represented. Exact realized parameter coverage is
saved in the frozen candidate manifest. No claim that every Cartesian pair
has been tested. Higher inter-layer gain tests whether upper layers previously
received an excessively weak signal; alpha/rho alone cannot settle that.

## Prior and forecast interpretation

The called Normal factory is `beta_prior -> beta_prior_rhs_ns ->
qdesn_rhs_ns_prior_obj`; the independent AL public API uses the installed
static RHS-NS implementation. For their project's product density,
`N(beta_j;0,tau2*lambda_j2) N(0;beta_j,zeta2)`, the slab factor is independent
of tau2. Gaussian HS normalizers contribute `tau2^(-d/2)`; the auxiliary
`IG(1/2,1/xi)` contributes `tau2^(-3/2)`. Thus shape=(d+1)/2 and rate is
`1/xi + .5 sum(beta_j^2/lambda_j2)`. VB replaces squared coefficients and
inverse scales by expectations. Here d=p-1, so shape=p/2 is CORRECT; it must
not be confused with an erroneous d/2. The implementation retains the product
factor normalizers and the excluded intercept's separate zero-centered prior.
This project convention is not interchangeable with silently normalizing the
product into a different hierarchical regularized-horseshoe density.

The focused R gate checks both exact runtimes at dimensions7/31/257/577,
different initial scales, unchanged prior hyperparameters, zero prior natural
centers and equal AL prior ELBOs under different supplied baseline centers.
It is NOT a complete audit of historical MCMC or joint fits. Tau is a
deliberately selected training-only model hyperparameter, not an inherited
posterior summary. Quantile beta/sigma warm starts do not redefine priors.

The historical forecast operator averages conditional quantile functions over
generated histories; it does not take marginal mixture quantiles. Linear
readouts explain why path and mean-feature averages nearly coincide. The
new reconstruction diagnostic is a sensitivity experiment, not a normalized
joint working likelihood or an identified predictive distribution. Its tail
assumptions and independent-level posterior coupling must remain visible.

## Reproducibility, recovery and integration

New modules use private engine instances; historical executed files are not
edited. Compact source/model manifests and checksums accompany all outputs.
No partial/corrupt model directory is automatically deleted or accepted.
Completed outputs resume only with matching contracts and hashes. Any invalid
output blocks the phase and needs an explicit audited recovery namespace.
The R122 backend's legacy stage labels are implementation provenance, not a
claim to have rerun the historical campaign; new top-level contracts use R123.

Generated roots: `application/data_local/pricefm/{launch_prep,campaigns}/
pricefm_stage_r123_bg_input_connectivity_20261003`. Keep excluded, along with
large NPZ, binaries, RDS, logs and environment artifacts. The local full plan
is ignored by the existing `local_trackers/` rule. Only code, protocol, tests
and this compact reproducibility note belong to the task branch. Integration
requires R122 dependencies as well as this successor; never merge this lane
directly to main or Overleaf. No article-safe replacement files are produced.

Run the new Python file plus the existing seven-file R120-R122 suite, and the
focused R prior gate on the exact target server, before the controller launch.
The initial ignored-document fixture from R120 must accompany isolated-test
worktrees; its absence is a test-setup failure, not a model regression.

```bash
PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python
env PYTHONDONTWRITEBYTECODE=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 "$PY" -B \
  application/scripts/pricefm/433_run_pricefm_stage_r123_connectivity.py \
  --workers 15 --code-root "$PWD"
```

Use the committed Jerez task worktree, a detached background launcher and
preserved controller log. Inspect early task terminals before leaving it.
Do not confuse 15 reserved cores with nine diagnostic jobs or nine later
quantile ladders. Main campaign readiness is NOT_READY_FOR_INTEGRATION until
the scientific phase and its freeze audit are finished.
