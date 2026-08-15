# Joint exQDESN Phase146 Sigma-Gamma Geometry

## Motivation

Phase145C completed 32 long chains without implementation failures. Repeating
the gamma update with refreshed sigma and latent `s` improved gamma R-hat, ESS,
and between-chain agreement, but did not improve quantile-grid forecast error.
The remaining near-unit gamma-sigma chain-mean correlations identify the
conditional geometry, rather than burn-in or chain count alone, as the next
sampler target.

## Contract

Phase146 does not change the exAL likelihood, gamma support, priors, DESN
features, RHS specification, fixture, or scoring contract. It adds a symmetric
random-walk Metropolis update for each `(sigma_q, gamma_q)` block on
`(log(sigma_q), logit(gamma_q))`. The target is the complete-data joint kernel
already documented in the supplement, including both transformation
Jacobians.

The proposal correlation is negative below the median, positive above the
median, and zero at the median. This follows the signed ridge observed in
Phase145C. Two proposal scales are compared against the Phase145C
`refresh3_sigma_s` control.

## Overnight packet

- One frozen case: `student_t_location_scale`.
- Three variants.
- Eight chains per variant, 24 chain jobs total.
- 12,000 iterations, 3,000 burn-in, thinning by 3.
- 24 MCMC workers and six VB preparation workers.
- Raw R objects are not retained.

The experiment remains `review` unless implementation gates, contract
noncrossing, acceptance, quantile-grid performance, and gamma diagnostics all
support promotion. A geometry gain without predictive stability is not enough
for propagation to the remaining scenarios.
