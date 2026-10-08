# R129B: same-state stationarity and preserved R128 fits

## Scope and evidence

R128's 371 sealed tasks, including all screening and six full Normal RHS fits,
remain frozen. Its six median AL VB fits reached 1000 iterations with the raw
coefficient convergence flag false. R129 audited these saved fits without new
AL optimization. Denmark passed three certificates; Croatia failed three
because of the composed, look-ahead shrinkage-rate residual. R129 stopped
automatically before any of its 36 outward AL fits or 64 forecast chunks ran.

R129B preserves those failed audit packets and hashes them as inputs. It changes
the diagnostic equation, not the posterior, fitted coefficients, covariance,
scale, thresholds, frozen regional specifications or tests used for selection.
The versioned scripts retain R129 names for compatibility; the new campaign,
source commit, preparation, contracts and evidence are isolated by the R129B tag.

## Root cause and independent derivation

Write a variational state as `(q_beta, q_scale, q_latent, q_rhs)`. A block
stationarity condition compares each block's optimal update with that block at
this *same* state. R129 instead compared `q_rhs` with the RHS update after moving
`q_beta` to its next mean and covariance. That quantity measures propagation
through a composed update, not the original state's RHS coordinate residual.
With posterior precision condition numbers about `3e11` in Croatia, tiny
coefficient discrepancies can be amplified by that composition.

For the executed CRAN 1.1.1 RHS product density and `d = p - 1` shrunk weights,
use `t = tau^2`, `l_j = lambda_j^2`, `c = slab^2`, and inverse gamma density
`IG(x;a,b) proportional to x^(-a-1) exp(-b/x)`. With `B_j = E(beta_j^2)`,
all conditional variational shape/rate equations at one state are:

```
a_lj = 1;        b_lj = B_j E(1/t)/2 + E(1/nu_j)
a_nuj = 1;      b_nuj = 1 + E(1/l_j)
a_t = (d+1)/2;  b_t = sum_j B_j E(1/l_j)/2 + E(1/xi)
a_xi = 1;       b_xi = tau0^(-2) + E(1/t)
a_c = a_c0+d/2; b_c = b_c0 + sum_j B_j/2
```

The intercept is excluded and has fixed zero center and precision `1e-16`.
Half-Cauchy auxiliaries contribute the extra `1/2` to the global shape. The
separate slab Gaussian product contributes no further global-scale factor.
The diagnostic independently evaluates these equations instead of invoking a
composed CAVI sweep. Mean, covariance, latent, scale and ELBO checks remain
unchanged. RHS reconstruction from unit and dispersed starts remains mandatory.
The old look-ahead value is still reported as a nongating diagnostic.

Six isolated checks of the actual saved states gave direct same-state RHS
residuals `3.52e-10` to `4.35e-10`, against the unchanged `1e-6` threshold.
The package's same-state update independently gave `6.93e-10` to `8.63e-10`.
Injecting a 1% global-rate error gave `0.0099503` and was rejected. All Croatian
coefficient, covariance, scale, predictor and ELBO checks had already passed.
These facts support a false rejection by the composed diagnostic, not a claim
that the raw CRAN convergence flag was true or that a global optimum is proved.

## Execution and limits

1. Source-matched release on Muscat and Jerez, including public CRAN numerical
   fits, perturbed coefficient/covariance/scale rejection, independent shape
   equations and rejection of perturbations to all ten RHS shape/rate blocks.
2. Audit all six saved medians with the corrected same-state certificate.
3. Only if all pass, fit the 36 previously unrun independent AL VB levels through
   public CRAN APIs: median -> 0.45/0.55 -> 0.25/0.75 -> 0.10/0.90.
4. Forecast 64 chunks / 730 region-origin pairs, seven quantiles, S=500 and
   H=96 quarter hours. Normal RHS recursive paths drive the pure all-layer
   readout; teacher forcing occurs between origins, never within an origin.
5. Freeze six fold comparisons to R98 and both PriceFM references. Keep test
   comparisons descriptive because these pilot regions have been examined.

Maximum 15 distinct physical cores, one thread per worker, 200 GiB RAM/disk
reserves, 4 GiB campaign output cap. Outward fits keep R128's raw tolerance
`1e-5` and maximum 1000 iterations; R129's untested `1e-3` early stopping is
not carried forward. No automatic budget changes follow a failed certificate.
Original false raw flags remain false even if an independent certificate passes.
Auxiliary completion is a new derived variational distribution, not exact
restoration of discarded optimizer state. No coefficient whitening, jitter,
package patch, new Normal/median optimization, MCMC, exAL, joint fit, screening,
registry mutation, article mutation, integration or all-region rollout.

## Reproducibility

Run source is the isolated R129B task branch. Preparation pins R128/R127 heads,
all inherited source hashes, reused inputs, superseded diagnostic packets, raw
CSV identity and source-matched release. Each task seals artifact hashes.
Controller locking, dependency certification, resource checks and a final raw
content rehash are retained. Runtime and the detailed master plan stay ignored.
Any failed fit retains its evidence and blocks dependent work rather than being
silently reused or reported as converged.
