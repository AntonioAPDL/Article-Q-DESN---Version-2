# Joint QVP regularized-horseshoe global-scale correction

## Status

`IMPLEMENTATION_CORRECTED_RESULTS_REQUIRE_PROVENANCE_REVIEW`

## Scope

This change corrects the global-scale update in the shared
`joint_qvp_qdesn.R` inference module. It changes no reservoir feature,
likelihood, coefficient parameterization, quantile grid, forecast definition,
score, article table, figure, or reported numerical result.

## Mathematical correction

For a block of \(p\) penalized coefficients, the stated hierarchy is

```text
beta_j | tau^2, lambda_j^2 ~ Normal(0, tau^2 lambda_j^2),
tau^2 | xi ~ IG(1/2, 1/xi),
xi ~ IG(1/2, 1/tau0^2).
```

Conditioning on the coefficient block gives

```text
tau^2 | ... ~ IG(
  (p + 1) / 2,
  1 / xi + sum_j beta_j^2 / (2 lambda_j^2)
).
```

The previous implementation used `p / 2` in the MCMC draw, the VB coordinate
factor, and the VB objective accounting. It thereby omitted the one-half shape
contribution from `tau^2 | xi`. The objective calculation also represented
the two half-Cauchy augmentation factors with prior shapes zero and one rather
than one-half and one-half.

The correction introduces one validated function,
`app_joint_qvp_rhs_tau2_shape()`, and uses it in all three locations. The MCMC
and VB global-scale shapes are now `(p + 1) / 2`. The VB objective now accounts
for `tau^2 | xi` and `xi` with their two `IG(1/2, ...)` prior factors. The
variational factor for `xi` continues to have shape one, as required by its
coordinate update.

## Exposure and rerun boundary

Whether a result requires refitting is determined by its recorded inference
function and source commit, not by its article label alone.

| Result family | Exposure | Required action |
|---|---|---|
| Independent Q-DESN validation produced through the `exdqlm` package | Not exposed; the package uses `(m+1)/2` | No rerun for this correction |
| Current PriceFM R69B--R92 independent AL/exAL authority | Not exposed; these fits use the `exdqlm` RHS implementation | No rerun for this correction |
| Authoritative GloFAS FR09 result | Not exposed; it uses the separate latent-path VB implementation, which uses `(m+1)/2` | No rerun for this correction |
| GloFAS Normal RHS and Part 3 partitioned RHS calculations | Not exposed; their implementations already use `(m+1)/2` | No rerun for this correction |
| Phase181 four-model simulation comparison | Exposed. Joint fits and nominally independent comparators use the shared QVP engine | Rerun all affected VB initializations and MCMC fits before replacing article assets |
| Phase182 or later JOINT work derived from the pre-correction engine | Potentially exposed | Verify the frozen source commit; rerun every affected fit |
| GloFAS Part 1 quantile fits produced by `app_glofas_part1_quantile_fit_readout()` | Exposed for both one-level and joint modes because the routine calls the shared QVP update | Rerun before scientific promotion; FR09 remains unchanged |
| GloFAS Part 4 joint quantile fits derived from the same engine | Potentially exposed | Verify source provenance and rerun before promotion if the shared update was active |
| Jerez JOINT article-confirmation fits | Potentially exposed | If fitting has not started, update the source first; otherwise rerun completed affected fits |

The word *independent* does not by itself establish that a fit is unaffected.
Phase181's independent comparator fits each probability level separately but
invoke the same shared MCMC update with a one-level coefficient block. Those
fits therefore require rerunning alongside the joint fits.

Results that used a fixed global scale throughout are unaffected by the shape
error because the update was not evaluated. This exception must be established
from the frozen configuration and trace, not inferred from an initialization
value or a finite warmup period.

## Verification

`application/tests/test_joint_qvp_rhs_global_shape.R` checks:

1. exact shapes for block sizes 1, 2, and 7;
2. invalid block-size rejection;
3. the complete MCMC inverse-gamma update under fixed random seeds;
4. the first VB coordinate update against an independent calculation; and
5. the VB prior, entropy, and log-precision accounting against an independent
   calculation of both half-Cauchy augmentation factors.

The focused test is registered in `application/tests/run_tests.R`.

At the correction commit, the new test and the directly related AL, exAL,
MCMC, VB, GloFAS Part 1, and PriceFM joint-continuation tests pass. The complete
repository harness reaches the new test successfully and then stops in the
pre-existing `test_joint_qvp_qdesn_synthetic_artifacts.R` fixture with an
`rbind` column-count error. The same harness fails at the same fixture and with
the same message on the unmodified `origin/main` parent, establishing that this
is an inherited test boundary rather than a regression introduced here.

## Publication boundary

This implementation correction does not retroactively change any stored fit.
No current table, figure, result registry, or manuscript claim is replaced by
this commit. Corrected article results require a separately frozen scientific
rerun, validation packet, and coordinator integration. Until then, the
Phase181 numerical assets must be treated as requiring replacement before the
next article publication.
