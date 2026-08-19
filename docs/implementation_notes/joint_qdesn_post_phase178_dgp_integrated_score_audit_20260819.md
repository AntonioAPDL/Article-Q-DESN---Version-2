# Post-Phase178 DGP-Integrated Finite-Grid Score Audit

Date: 2026-08-19

## Purpose

Phase178 completed under its frozen forecast-oracle-MAE ranking contract. The
next decision layer evaluates the reported multi-quantile action with a proper
finite-grid forecast score before any Phase179 selected-versus-parity campaign
is prepared.

This stage is post-processing. It does not modify or rerun the Phase178 MCMC
sampler. It reconstructs forecast quantile paths from the retained posterior
parameter draws, evaluates their expected quantile score under the known DGP,
and preserves the original Phase178 ranking as historical provenance.

## Predictive Interpretation

The joint AL/exAL objective is a composite working likelihood for quantile-path
inference. It is not treated as a normalized scalar response predictive
density. The primary estimand therefore evaluates the issued finite vector of
conditional quantiles directly:

\[
  R(q)=\frac{1}{H}\sum_{h=1}^{H}\sum_{k=1}^{K}
  w_k\,2\,\mathbb{E}_{Y_h\sim F_{0,h}}
  \{\rho_{\tau_k}(Y_h-q_{h,k})\}.
\]

The expectation is under the known conditional DGP. Internally this score is
named `dgp_integrated_acrps`. It is a DGP-integrated finite-grid quantile score,
not the closed-form CRPS of a fitted joint predictive density.

## Frozen Current-Grid Contract

The versioned contract is
`application/config/joint_qdesn_post_phase178_dgp_score_contract_v1.csv`.
It is frozen and hash-manifested before protected DGP-integrated scores are
computed.

The fitted quantile grid is

`0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`.

Trapezoidal weights multiplying `QS_tau = 2 rho_tau` are

`0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025`.

They sum to 0.90 and are not renormalized. This preserves integration over the
fitted interval `[0.05, 0.95]` rather than silently assigning unit mass to the
truncated range.

The primary posterior report is the posterior mean score with an equal-tailed
95% credible interval. The posterior median and score of the canonical
posterior-mean monotone quantile action are retained as compact sensitivity
summaries.

## Posterior Draw Contract

- Joint readouts preserve retained within-draw cross-quantile dependence.
- Independent quantile fits are coupled with a fixed, seeded, within-chain
  product-posterior permutation. Equal MCMC iteration numbers are not treated
  as learned dependence.
- The primary score uses 1,000 equally spaced retained draws per chain.
- Alternate coupling seeds use 250 draws per chain for sensitivity.
- Reconstruction is chunked in blocks of 250 draws and never writes a full
  draw-by-time-by-quantile cube.
- Raw draw-level crossings are retained. The existing isotonic quantile
  contract is applied draw by draw before the reported score is computed.
- Contract crossings are a hard failure; raw crossing and adjustment burden
  are review evidence.

The scalar score contrast, not nonoverlap of two marginal intervals, is the
comparison object. Candidate-minus-parity and available joint-minus-independent
contrasts use a separate deterministic within-chain pairing permutation.

## DGP Expected-Loss Engine

`application/R/joint_qdesn_dgp_integrated_acrps.R` implements analytic expected
check loss for all five registry families:

- Gaussian;
- variance-standardized Laplace;
- variance-standardized Student-t;
- centered and variance-standardized Gaussian mixture;
- scale-standardized asymmetric Laplace with its nonzero mean preserved.

For `Y = mu + sigma Z`, expected check loss is evaluated as

\[
  \sigma\left[\frac{1}{2}\mathbb{E}|Z-z|
  +(\tau-1/2)(\mathbb{E}Z-z)\right],
  \qquad z=(q-\mu)/\sigma.
\]

Each analytic path is tested against high-accuracy numerical integration and a
fixed-seed Monte Carlo oracle. A separate local-minimum audit verifies that the
known conditional quantile minimizes expected check loss. Registry centering,
scale conventions, and forecast-row DGP parameters are used exactly once.

## Forecast Information Gate

Every scored forecast row must join one-to-one to its frozen DGP `mu`, `sigma`,
family parameters, response, true quantiles, origin, and horizon. The target
time must equal origin plus horizon and must occur strictly after the frozen fit
window. Later forecast origins may occur after that fit window because the
Phase178 design uses fixed fitted parameters with sequentially available lagged
observations; it does not refit the model at every origin.

Any malformed join, nonfinite context, nonpositive scale, or previsibility
defect fails closed.

## Decision Policy

Selection remains case-specific. A challenger replaces parity only when all of
the following hold under the predeclared contract:

1. complete verified sources and zero contract crossings;
2. at least a 0.5% lower matched DGP-integrated score;
3. practical superiority in at least two of three protected replicates;
4. median posterior probability of practical superiority at least 0.95;
5. stable score functionals, crossing contract, and independent coupling;
6. no more than 5% degradation in fit or forecast oracle-path recovery.

Practical near ties retain parity. Gamma/sigma diagnostics remain visible but
are review-level when score and quantile-path functionals are stable. An
unstable score functional cannot be waived by favorable point metrics.

## Reproducible Commands

After the Phase178 branch is integrated into the dedicated post-score branch:

```bash
Rscript application/tests/test_joint_qdesn_post_phase178_dgp_integrated_acrps.R

Rscript application/scripts/261_freeze_joint_qdesn_post_phase178_dgp_score_contract.R \
  --cache-root /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache

Rscript application/scripts/262_audit_joint_qdesn_post_phase178_dgp_scores.R \
  --cache-root /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache \
  --cores 8

Rscript application/scripts/263_check_joint_qdesn_post_phase178_dgp_scores.R \
  --cache-root /data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache
```

The audit uses manifest-verified per-cell checkpoints so an interrupted
post-processing run resumes completed cells without recomputing MCMC.

## Artifacts

The frozen contract directory contains the score, quadrature, coupling,
decision-margin, source-verification, provenance, and SHA-256 manifest tables.

The final score audit contains:

- compressed posterior score draws;
- posterior and canonical-action score summaries;
- candidate-minus-parity and available joint-minus-independent contrasts;
- expected oracle scores and regrets;
- realized-versus-expected compatibility checks;
- raw/contract crossing and adjustment diagnostics;
- pairing-seed, chain-allocation, and score-functional diagnostics;
- protected-replicate stability;
- original Phase178 decisions beside the new article-action decisions;
- Phase179 selected/parity templates;
- source-completeness, provenance, and SHA-256 manifests.

Phase178 is targeted evidence, not a complete 32-row article packet. Missing
draw-level article rows are labeled `source_incomplete`; they are not fabricated
from point summaries.

## Stage Boundaries

- The legacy MAE-centered Phase179 launcher remains unauthorized.
- No article table, figure, or manuscript file is modified by this stage.
- No 19-level model is fit here. Dense-grid fitting is a separately frozen
  later campaign using actual 19-level refits, not interpolation.
- No `main` or Overleaf branch is modified.
- PriceFM, GloFAS, and unrelated QDESN lanes remain untouched.
