args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
default_library <- paste0(
  "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/",
  "runtime_libraries/exdqlm_cran_1p1p1"
)
package_library <- Sys.getenv("PRICEFM_R67_CRAN111_LIBRARY", unset = default_library)

source(file.path(root, "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"))
contract <- r67_assert_cran_package(package_library)
stopifnot(
  identical(contract$version, "1.1.1"),
  identical(contract$repository, "CRAN"),
  all(r67_required_exports %in% contract$exports),
  !any(r67_fork_only_exports %in% contract$exports)
)

x <- seq(-1, 1, length.out = 90L)
X <- cbind(1, x, sin(2 * x))
y <- 0.3 - 0.6 * x + 0.15 * sin(2 * x) + 0.03 * cos(9 * x)
rhs <- list(
  tau0 = 1e-3,
  shrink_intercept = FALSE,
  freeze_tau_iters = 2L,
  freeze_tau_warmup_iters = 2L
)
qcfg <- list(
  max_iter = 80L,
  tol = 1e-6,
  n_samp = 12L,
  n_samp_xi = 20L,
  verbose = FALSE,
  prior_sigma = list(a = 1, b = 1),
  prior_gamma = list(mu0 = 0, s20 = 10),
  chunking = list(enabled = TRUE, mode = "exact")
)

al <- r67_fit_quantile(
  package_library, X, y, tau = 0.25, likelihood = "al",
  rhs = rhs, qcfg = qcfg, seed = 6701L
)
al_audit <- attr(al, "r67_control_audit")
stopifnot(
  all(is.finite(al$qbeta$m)),
  identical(al_audit$likelihood, "al"),
  identical(al_audit$public_api, "exalStaticLDVB"),
  identical(al_audit$exact_chunking_claimed, FALSE),
  "chunking" %in% al_audit$ignored_fork_controls
)

exal <- r67_fit_quantile(
  package_library, X, y, tau = 0.25, likelihood = "exal",
  rhs = rhs, qcfg = qcfg,
  profile = list(
    factorization = "structured",
    structured_grid_size = 81L,
    structured_span_sd = 5,
    freeze_warmup_iters = 5L,
    force_after_warmup = TRUE,
    postwarmup_damping = 0.2,
    postwarmup_damping_iters = 20L,
    min_postwarmup_updates = 15L
  ),
  init = r67_init_from_fit(al, gamma_zero = TRUE),
  seed = 6702L
)
exal_audit <- attr(exal, "r67_control_audit")
stopifnot(
  all(is.finite(exal$qbeta$m)),
  identical(exal_audit$likelihood, "exal"),
  identical(exal_audit$public_api, "exalStaticLDVB"),
  identical(exal_audit$exact_chunking_claimed, FALSE)
)

rows <- data.frame(origin_id = seq_len(nrow(X)), horizon = rep(1L, nrow(X)))
prediction <- r67_prediction_frame(al, X, rows, "r67_al", 0.25)
stopifnot(
  nrow(prediction) == nrow(X),
  all(is.finite(prediction$pred_scaled)),
  all(prediction$split == "val"),
  all(prediction$tau == 0.25)
)

cat("PriceFM Stage-R67 CRAN 1.1.1 adapter tests passed.\n")
