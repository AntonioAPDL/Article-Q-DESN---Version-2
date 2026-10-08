# R129: Target-Preserving AL Convergence Recovery

This lane does not change R128's screening, region-specific DESN/tau0 choices,
designs, priors, Normal drivers, forecast information set or authority. R128's
six finite median fits remain formally unconverged in their original evidence.
The package remains exact CRAN exdqlm1.1.1; no namespace or source patch is used.

The original raw-coordinate stopping test is insufficient for highly correlated
reservoir features. R129 checks the actual intended mean-field stationary
equations in parameter-uncertainty and predictive coordinates, including beta
covariance, sigma, latent variables and RHS auxiliaries. The cheap auxiliary
reconstruction is conditional on saved q(beta) and q(sigma), not an AL refit.
Two deliberately different starting states must agree. The reconstructed full
variational distribution is explicitly labeled; exact optimizer resumption or
recovery of discarded historical latent state is not claimed.

For d=p-1 shrunk coefficients, the project RHS-NS product density includes
the Gaussian horseshoe factor and an additional Gaussian slab factor.
With t=tau^2, the global hierarchy is t|xi~IG(1/2,1/xi),
xi~IG(1/2,1/tau0^2), IG density proportional to x^(-a-1)exp(-b/x).
The tau-dependent Gaussian factor contributes t^(-d/2), hence the global
shape is (d+1)/2=p/2. The slab factor is tau-independent under this product
convention. The actual installed CRAN update agrees. The intercept has fixed
zero center and precision1e-16 and is outside the shrinkage block.
Local lambda^2 and nu shapes are1; xi shape is1. The free slab shape is
a_zeta+d/2. Sigma has shape1+3n/2 under the AL Gaussian/exponential mixture.
No shape, prior center, prior scale, slab control or tau0 is taken from a fit.

The certificate derives unknown AL mixture moments analytically from current
beta mean/covariance and sigma. It checks the beta mean in posterior-standard-
deviation units, observed-design predictor RMS, covariance in posterior precision
coordinates, sigma's IG rate fixed point, every RHS IG rate, agreement between
auxiliary starting states and full ELBO change after the joint update.
All checks use training data only and thresholds are fixed before scoring.

Outward AL optimization still calls public exalStaticLDVB with unchanged priors.
Its raw-coefficient computational stopping tolerance is1e-3, not the final
acceptance criterion; the complete independent certificate determines acceptance.
This is not an unconditional tolerance relaxation. A failed certificate blocks
descendants, even if the public fit reports converged. A saved median can be
accepted by its new independent certificate while preserving its old false
formal flag. No changes to the old sealed files are permitted.

Only six saved-median certificate tasks are allowed before the release gate.
If all pass, schedule36 previously unrun AL levels and64 forecast chunks,
730 region/origin pairs, with S500 and the inherited stochastic Normal RHS
driver. One shared maximum15-physical-core scheduler enforces one thread per
task, RAM/disk reserves and immutable task seals. No new MCMC, exAL, joint,
screening, all-region rollout, article update or promotion is authorized.

The diagnostic accesses version-pinned internal prior/entropy functions to
verify the implemented objective. Production fitting uses public APIs only.
New compact state records permit future audits without duplicating X/y in
fit objects. Original R128 evidence is read-only and its371 completed certified
or uncertified fitting/screening artifacts are not deleted or relocated.

Entrypoint: application/scripts/pricefm/459_run_pricefm_stage_r129_recovery.py.
Prepare requires a clean committed task source, source-matched test receipt,
exact frozen R128/R127 heads, no active R128 workers, verified reused task
seals and input/source hashes. Resource or certification failures stop admission
and preserve evidence. Unsealed partial outputs are never overwritten on resume.
