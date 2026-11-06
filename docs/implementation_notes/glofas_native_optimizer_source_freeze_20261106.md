# GloFAS native optimizer source-freeze boundary

## Scope

This note records the bounded Stages A--D implementation for the proposed
full-parameter GloFAS optimizer. It is a software qualification record, not a
native application fit, posterior-accuracy certificate, campaign launch, or
replacement of the current GloFAS authority. Article files, authority aliases,
executed forecasts, and historical jobs are unchanged.

The implementation preserves the executed two-DESN specification, the
independent median-AL target, all 51 issued members at each of 28 horizons,
ordinary unit member factors, separate Y/G scales, and the full normalized
Nishimura--Suchard product hierarchy. Future USGS remains scoring-only. The
native application and publication flags remain false in every new contract.

## Stage A: exact task and prior binding

`scripts/diagnostics/glofas_native_prior_contract.R` is a purpose-bound reader
for one declared 3,798-byte transition configuration. It does not construct a
design, load a fit, read future truth, or run a model. Its frozen read exported:

| Field | Bound value |
|---|---|
| Task | `gft-al-p050` |
| Posterior target | `72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03` |
| Reference `tau0` | `5.2043087000000001e-05` |
| Discrepancy `tau0` | `0.0001159` |
| Intercept precision | `1e-9` in both blocks |
| Learned slab prior | `zeta2 ~ IG(2,4)` in both blocks |
| Source-scale priors | separate `Y,G ~ IG(2,1)` |
| Configured `s2=4` | variational initializer, not a prior hyperparameter |

The exported hierarchy retains both Normal factors per penalized coefficient,
global shape `(r+1)/2` with the intercept excluded, local shape one, and one
coordinate Jacobian. The receipt records one RDS deserialization, zero design
or fit reads, and zero model runs.

## Stage B: changing-parameter two-DESN continuation

`scripts/diagnostics/glofas_two_desn_particle_backend.R` binds an in-memory
engine, retained cutoff states, compiled causal input contracts, readout order,
gains, issued-member matrix, ensemble centre, baseline, task identity, and
prior identity. It rejects fractional member policies and requires 51 unit
members per horizon.

The state backend starts both DESNs from retained cutoff states for each
parameter evaluation. It uses exact complete response prefixes, never rounded
keys, and resets its bounded cache between parameter values. Resampling carries
the response path, ancestry, and both DESN state collections together. Reference
lags use preceding simulated Y values; discrepancy lags use the issued centre
minus those same preceding Y values. The known baseline is added once.

`glofas_guided_collapsed_particle.R` retains its original callback interface
and arithmetic. Its additive state-backend route supplies aligned reference and
member locations without changing the AL transition, all-member likelihood,
resampling weights, or full importance correction.

Generated H2 and H28 tests compare cached and independently recomputed states,
features, and locations to `1e-10`; they also cover duplicated prefixes,
resampling, A/B/A parameter order, all member factors, causality, and RNG
restoration. These tests perform no authentic model read or fit.

## Stage C: native contract and marginal response quantiles

`scripts/diagnostics/glofas_native_parameter_optimizer.R` adds a genuine
native-facing contract to the existing optimizer core. It binds the complete
coordinate map, task, posterior target, effective and declared priors,
two-DESN static identity, source closure, one Jacobian, full product prior,
H28 inventory, retained gains, and `unit_member_likelihood_v1`. The application
contract contains 7,510 physical median-AL coordinates. It cannot authorize a
payload read, native fit, production launch, or publication.

The existing generated optimizer remains a wrapper with its original schema
and exact constructor validation. Generated fixture tests demonstrate identical
means, log standard deviations, scientific trace fields, and final gradients
between the legacy wrapper and the native interface. Elapsed wall time is the
only excluded parity field. Contract mutations are rejected.

`scripts/diagnostics/glofas_particle_marginal_quantiles.R` reports each marginal
future response quantile by inverting

```text
F_hat_h(y) = B^-1 sum_b sum_n W_bn 1(Y_bnh <= y),
```

where each outer draw has weight `1/B` and `W_bn` is the normalized terminal
H28 particle weight within that draw. It does not evidence-reweight outer
draws, substitute filtering weights, average per-draw quantiles, append response
noise, or reuse the Gaussian-Delta formatter. `expm1` is applied only after CDF
inversion. A delete-one outer-cluster jackknife is reported when at least four
independent outer draws exist; particle-replicate precision remains a later
Stage E assessment rather than an invented certificate.

## Source closure and remaining gates

The owned tracked closure comprises the four diagnostic modules above, the
narrow extension to `glofas_guided_collapsed_particle.R`, the extracted
optimizer core in `glofas_collapsed_parameter_optimizer.R`, their four focused
tests, this note, and their registered test entries. The implementation depends
on the existing nonlinear replay, collapsed AL target, innovation-coordinate,
particle-reference, particle-VI, unit-member, family-transition, and latent-path
RHS source already tracked on the branch base.

Stages E and F remain unexecuted. A later explicit decision is required before
any large native object read, H28 truth-free parity/cost/precision grid, native
median-AL fit, exAL or MQ derivation, campaign, authority change, or article
update. In particular, source qualification does not establish finite-particle
accuracy, variational-family adequacy, posterior accuracy, runtime feasibility,
or forecast improvement.
