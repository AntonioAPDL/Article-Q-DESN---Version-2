# GloFAS latent-path VB: RHS global-scale warmup

## Scope

This change wires the existing GloFAS configuration field
`inference.vb_ld.rhs_freeze_tau_warmup_iters` into the article-side
latent-path AL variational Bayes engine. Before this change, the application
adapter passed the field but `application/R/latent_path_vb_al.R` updated both
regularized-horseshoe global scales on every iteration. Historical fits are
therefore effective zero-warmup fits, irrespective of the value recorded in
their YAML configuration.

The change is intentionally limited to the two global RHS scales:

- the shared/reference readout scale and its auxiliary variable;
- the discrepancy readout scale and its auxiliary variable.

The coefficient blocks, local RHS scales, slab scale, AL augmentation,
likelihood scale, and future latent path continue to update from iteration 1.
The posterior target after release is unchanged. This is an initialization
sensitivity control, not a change to `tau0` and not a claim that one warmup
length is theoretically optimal.

## Configuration contract

```yaml
inference:
  vb_ld:
    rhs_freeze_tau_warmup_iters: 25
    rhs_update_every: 1
    rhs_min_tau_updates: 1
```

The GloFAS application adapter defaults to 25 frozen iterations, one global
update per iteration after release, and at least one global update. Low-level
calls that do not use the application adapter retain the explicit zero-warmup
default.

For a configured warmup of `k`, global scales are fixed on iterations `1:k`.
The first global update occurs at the end of iteration `k + 1`; iteration
`k + 2` is the first coefficient update that uses the released scale. The
convergence gate therefore cannot pass before `k + 2`. A fit fails before
starting if `max_iter` cannot satisfy that requirement. With a cadence greater
than one, the first post-warmup update is forced and later updates follow the
configured cadence.

## Recorded diagnostics

Each fit stores:

- requested warmup, cadence, and minimum update count;
- first and last global-scale update iterations for both coefficient blocks;
- global-scale update counts and final effective scales;
- a per-iteration table of warmup state, update decisions, effective global
  scale, auxiliary expectation, coefficient norm, and local-scale summaries;
- a convergence-gate trace confirming that each released scale influenced a
  subsequent coefficient update.

Post-fit extraction recognizes the latent-path prior state and writes separate
shared/reference and discrepancy RHS summaries. It also accepts the latent
engine's `parameter_change_trace` name and exposes global-scale traces to the
standard trace-table workflow.

## Controlled p95 comparison

The first scientific use is a cold-start p95 comparison based on the completed
`fr09_persistence_innovation` p95 configuration:

1. immutable historical fit: effective warmup `k = 0`;
2. candidate `fr09_p95_tauwarm25`: `k = 25`;
3. candidate `fr09_p95_tauwarm50`: `k = 50`.

The two new fits must differ only in warmup length. Data, cutoff, quantile,
DESN features, seeds, direct-readout contract, priors, likelihood, VB controls,
and cold-start policy remain fixed. Selection uses observed-history p95 check
loss plus finite-value, prediction-identity, upper-tail excursion, and
discrepancy-support gates. Forecast-window scores are excluded. No full-seven
launch, promotion, manuscript update, or cleanup is automatic.

## Validation requirements

- exact freeze/release boundaries for `k = 25` and `k = 50`;
- local-scale and coefficient updates during warmup;
- numerical compatibility for explicit `k = 0`;
- independent shared/reference and discrepancy state accounting;
- update-cadence and convergence-gate behavior;
- fail-closed handling of insufficient `max_iter`;
- deterministic tiny latent-path AL/VB integration fit;
- complete application test suite and `git diff --check`.
