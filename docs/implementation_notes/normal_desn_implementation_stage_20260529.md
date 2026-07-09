# Normal DESN Implementation Stage

Date: 2026-05-29

## Scope

This stage adds a Normal-likelihood DESN readout to the shared `exdqlm`
package branch used by the Q-DESN article workflow. The goal is a fast
conditional-mean baseline and a future initialization source for AL/exAL
Q-DESN fits.

The implementation is deliberately separate from the AL/exAL readout engine.
It reuses Q-DESN feature construction but gives the Normal readout its own
class so existing quantile-specific forecasting methods are not asked to
interpret Gaussian posterior draws.

## Implemented Targets

### Exact scaled-ridge Normal DESN

For fixed DESN features `X` and response `y`, the implemented exact model is

```text
y | beta, omega2, X ~ N(X beta, omega2 I)
beta | omega2       ~ N(b, omega2 P^{-1})
omega2              ~ IG(a, b)
```

The package computes the closed-form Normal-inverse-gamma posterior:

```text
P_n = P + X'X
h_n = P b + X'y
m_n = P_n^{-1} h_n
a_n = a + T / 2
B_n = b + 0.5 (y'y + b'P b - m_n'P_n m_n)
```

This target is exact, preserves the full-data target, and does not use VB or
MCMC.

### RHS/RHS_NS Normal DESN VB

The RHS-family Normal readout is implemented as a global mean-field VB
approximation. RHS/RHS_NS shrinkage states remain global and are updated from
the global beta second moments. This target is not presented as the same
closed-form conjugate model as scaled ridge.

## Package API

New exported package functions:

- `normal_desn_fit()`: fixed-design Normal DESN readout.
- `qdesn_fit_normal()`: Q-DESN wrapper that reuses the existing DESN feature
  builder and attaches a Normal readout.
- `normal_desn_posterior_draws()`: posterior draws for beta and `omega2`.
- `normal_desn_posterior_predict()`: fixed-design posterior predictive draws.
- `predict_mu.qdesn_normal_fit()`: in-sample fitted means.
- `posterior_predict.qdesn_normal_fit()`: posterior predictive wrapper for
  `qdesn_normal_fit` objects.
- `qdesn_normal_to_vb_init()`: beta-moment initializer for future AL/exAL
  workflows.
- `qdesn_normal_to_mcmc_init()`: beta/sigma/gamma initializer for AL/exAL
  MCMC workflows.

The Q-DESN wrapper returns class `qdesn_normal_fit`, not `qdesn_fit`, because
the current `qdesn_fit` forecast methods assume AL/exAL readout draws.

## Reproducibility Metadata

The wrapper records:

- likelihood family: `normal`;
- target: `conditional_mean`;
- target label;
- exact versus VB status;
- design hash;
- feature-settings hash;
- package SHA and package version.

## Validation

Focused package tests cover:

- closed-form scaled-ridge posterior algebra;
- input validation;
- finite RHS/RHS_NS approximate VB fits;
- posterior draw and posterior predictive reproducibility;
- Q-DESN design reuse through `qdesn_fit_normal()`;
- Q-DESN RHS-family approximate Normal readout routing;
- Normal-to-AL/exAL initialization metadata.
- AL-VB routing from a Normal-derived initialization state.

## Simulated Behavior Smoke

A small simulated Q-DESN series was used as a behavior smoke after the
initializer contract was wired to the actual engine field names. The smoke fit:

- Normal DESN scaled ridge;
- Normal DESN RHS_NS VB;
- AL-VB from default initialization;
- AL-VB initialized from Normal DESN;
- exAL-VB initialized from Normal DESN;
- a tiny AL-MCMC run initialized from Normal DESN.

All fitted states were finite. On this small smooth series, the readout RMSE
against the fitted response was approximately:

```text
normal_scaled_ridge   0.2410
normal_rhs_ns_vb      0.1816
al_vb_cold            0.1778
al_vb_normal_init     0.1778
exal_vb_normal_init   0.1778
al_mcmc_normal_init   0.1783
```

This is not a performance claim. It is a reproducibility and wiring check:
Normal DESN outputs now provide valid initial values for the implemented
AL/exAL VB and AL MCMC readout paths.

## Deferred Work

Deferred by design:

- recursive Normal DESN forecast paths;
- exact chunked Normal DESN sufficient-stat accumulation;
- Normal DESN warm starts;
- Normal DESN rolling/online wrappers;
- stochastic or hybrid Normal DESN batching;
- using Normal RHS/RHS_NS as an exact closed-form posterior.

The next safe extension is exact chunked Normal DESN for the scaled-ridge
target, since it only requires chunking `X'X`, `X'y`, and `y'y`.
