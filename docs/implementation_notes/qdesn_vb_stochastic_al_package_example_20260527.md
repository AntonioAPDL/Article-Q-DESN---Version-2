# Q-DESN VB Stochastic AL Package Example

Date: 2026-05-27

## Purpose

This note records a small package-level example comparing:

- package static AL LDVB, unchunked full-data CAVI
- package static AL LDVB, exact chunked full-data CAVI
- package static AL LDVB, stochastic mini-batch VB

Exact chunking is full-data equivalent. Stochastic AL is approximate.

This note does not implement or validate stochastic exAL, hybrid AL,
variance-reduced AL, streaming/posterior-as-prior VB, article GloFAS
approximate batching, or multivariate Q-DESN batching.

## Package State

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- controls commit: `c321b3b Add stochastic AL VB batching controls`
- implementation commit: `246554e Implement stochastic AL VB batching`

## Data-Generating Setup

The example uses a simple static synthetic AL readout problem:

```r
set.seed(20260527)
n <- 100L
x <- seq(-1, 1, length.out = n)
X <- cbind(`(Intercept)` = 1, x = x, x2 = x^2)
beta <- c(0.2, 0.6, -0.3)
y <- as.numeric(X %*% beta + stats::rnorm(n, sd = 0.08))
```

The beta prior is ridge with `tau2 = 50`. All fits use `p0 = 0.5`,
`likelihood_family = "al"`, and `al_fixed_gamma = 0`.

## Controls

Unchunked AL:

```r
list(
  max_iter = 40L,
  min_iter_elbo = 10L,
  tol = 0,
  tol_par = 0,
  n_samp_xi = 32L,
  verbose = FALSE
)
```

Exact chunked AL adds:

```r
chunking = list(
  enabled = TRUE,
  mode = "exact",
  chunk_size = 17L
)
```

Stochastic AL uses:

```r
chunking = list(
  enabled = TRUE,
  mode = "stochastic",
  chunk_size = 20L,
  order = "random",
  seed = 20260527L,
  learning_rate = list(
    t0 = 10,
    kappa = 0.75,
    rho_min = 0.02
  ),
  refresh = list(
    full_every = 20L,
    objective_every = 20L,
    sigma_every = 5L,
    rhs_every = 20L,
    local_every = 20L
  ),
  diagnostics = list(
    trace = TRUE,
    store_batch_ids = TRUE,
    check_finite_every = 1L
  )
)
```

## Command

Run from the package repo:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript - <<'RS'
pkgload::load_all('.', quiet = TRUE)
set.seed(20260527)
n <- 100L
x <- seq(-1, 1, length.out = n)
X <- cbind(`(Intercept)` = 1, x = x, x2 = x^2)
beta <- c(0.2, 0.6, -0.3)
y <- as.numeric(X %*% beta + stats::rnorm(n, sd = 0.08))
prior <- exdqlm:::exal_make_beta_prior(type = 'ridge', tau2 = 50)

fit_one <- function(label, ctrl) {
  tm <- system.time({
    fit <- exdqlm:::exal_fit(
      y = y,
      X = X,
      p0 = 0.5,
      gamma_bounds = c(-3, 3),
      method = 'vb',
      likelihood_family = 'al',
      al_fixed_gamma = 0,
      vb_control = ctrl,
      prior_gamma = list(mu0 = 0, s20 = 10),
      prior_sigma = list(a = 1, b = 1),
      beta_prior_obj = prior
    )
  })
  list(label = label, fit = fit, elapsed = unname(tm[['elapsed']]))
}

base_ctrl <- list(
  max_iter = 40L,
  min_iter_elbo = 10L,
  tol = 0,
  tol_par = 0,
  n_samp_xi = 32L,
  verbose = FALSE
)
exact_ctrl <- modifyList(base_ctrl, list(
  chunking = list(enabled = TRUE, mode = 'exact', chunk_size = 17L)
))
stoch_ctrl <- modifyList(base_ctrl, list(
  max_iter = 90L,
  chunking = list(
    enabled = TRUE,
    mode = 'stochastic',
    chunk_size = 20L,
    order = 'random',
    seed = 20260527L,
    learning_rate = list(t0 = 10, kappa = 0.75, rho_min = 0.02),
    refresh = list(full_every = 20L, objective_every = 20L,
                   sigma_every = 5L, rhs_every = 20L, local_every = 20L),
    diagnostics = list(trace = TRUE, store_batch_ids = TRUE,
                       check_finite_every = 1L)
  )
))

fits <- list(
  fit_one('al_unchunked', base_ctrl),
  fit_one('al_exact_chunked', exact_ctrl),
  fit_one('al_stochastic', stoch_ctrl)
)
ref <- fits[[1]]$fit
summary <- do.call(rbind, lapply(fits, function(obj) {
  fit <- obj$fit
  data.frame(
    label = obj$label,
    elapsed_sec = obj$elapsed,
    iter = fit$iter,
    converged = fit$converged,
    stochastic = isTRUE(fit$misc$stochastic),
    beta0 = fit$qbeta$m[[1L]],
    beta1 = fit$qbeta$m[[2L]],
    beta2 = fit$qbeta$m[[3L]],
    sigma_last = tail(as.numeric(fit$misc$sigma_trace), 1L),
    max_abs_beta_diff_vs_unchunked = max(abs(fit$qbeta$m - ref$qbeta$m)),
    max_abs_beta_var_diff_vs_unchunked =
      max(abs(diag(fit$qbeta$V) - diag(ref$qbeta$V))),
    stringsAsFactors = FALSE
  )
}))
print(summary)
RS
```

## Results

| label | elapsed_sec | iter | converged | stochastic | beta0 | beta1 | beta2 | sigma_last | max_abs_beta_diff_vs_unchunked | max_abs_beta_var_diff_vs_unchunked |
| --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| al_unchunked | 2.834 | 40 | FALSE | FALSE | 0.1887994628997 | 0.577115786193295 | -0.257055595185948 | 0.0386263160554347 | 0 | 0 |
| al_exact_chunked | 13.721 | 40 | FALSE | FALSE | 0.188799462899698 | 0.577115786193292 | -0.257055595185939 | 0.0386263160553004 | 8.99280649946377e-15 | 3.50262353843167e-15 |
| al_stochastic | 1.610 | 90 | FALSE | TRUE | 0.190074678015221 | 0.581736601388653 | -0.255235244946024 | 0.0387725722740778 | 0.00462081519535817 | 4.64932769715371e-05 |

## Interpretation

The exact-chunked fit matches unchunked AL to floating-point tolerance, as
expected for a full-data-equivalent method.

The stochastic AL fit is finite, reproducible under the fixed seed in focused
tests, and close to the unchunked fitted state on this easy synthetic problem.
It is approximate and should not be interpreted as exact CAVI equivalence.

The small example is not a performance benchmark. At this scale, elapsed times
are dominated by overhead and implementation details. Runtime and memory claims
should use larger paired benchmarks after the method has more validation.

## Still Gated

- stochastic exAL batching
- hybrid AL SVI
- variance-reduced AL SVI
- streaming/posterior-as-prior VB
- article GloFAS stochastic or hybrid batching
- multivariate Q-DESN batching
