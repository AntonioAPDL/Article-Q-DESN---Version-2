r72_assert_repair_package <- function(library, expected_version = "1.1.1.9001") {
  library <- normalizePath(library, mustWork = TRUE)
  if ("exdqlm" %in% loadedNamespaces()) {
    loaded_path <- normalizePath(find.package("exdqlm"), mustWork = TRUE)
    expected_path <- normalizePath(file.path(library, "exdqlm"), mustWork = TRUE)
    if (!identical(loaded_path, expected_path)) {
      stop("A different exdqlm namespace is already loaded: ", loaded_path, call. = FALSE)
    }
  }
  namespace <- loadNamespace("exdqlm", lib.loc = library)
  description <- utils::packageDescription("exdqlm", lib.loc = library)
  if (!identical(as.character(description$Version), expected_version) ||
      !identical(as.character(description$Repository), "PriceFM-local")) {
    stop("R72 requires the labeled PriceFM-local exdqlm SPD repair.", call. = FALSE)
  }
  expected_base <- "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
  if (!identical(as.character(description[["Config/PriceFM/base-tarball-sha256"]]), expected_base) ||
      !identical(as.character(description[["Config/PriceFM/repair"]]),
                 "scale-aware-SPD-Cholesky-with-telemetry")) {
    stop("R72 package provenance metadata is invalid.", call. = FALSE)
  }
  exports <- getNamespaceExports(namespace)
  missing <- setdiff(r67_required_exports, exports)
  fork_only <- intersect(r67_fork_only_exports, exports)
  if (length(missing) || length(fork_only)) {
    stop("Unexpected R72 public API surface.", call. = FALSE)
  }
  list(
    library = library,
    package_path = normalizePath(file.path(library, "exdqlm"), mustWork = TRUE),
    version = as.character(description$Version),
    repository = as.character(description$Repository),
    base_tarball_sha256 = expected_base,
    repair = as.character(description[["Config/PriceFM/repair"]])
  )
}

r72_rhs_controls <- function(rhs) {
  rhs <- rhs %||% list()
  controls <- list(
    tau0 = as.numeric(rhs$tau0 %||% 1),
    init_tau = as.numeric(rhs$init_tau %||% 1),
    shrink_intercept = isTRUE(rhs$shrink_intercept %||% FALSE),
    freeze_tau_iters = as.integer(rhs$freeze_tau_iters %||% 50L),
    freeze_tau_warmup_iters = as.integer(rhs$freeze_tau_warmup_iters %||% 50L)
  )
  if (!is.finite(controls$tau0) || controls$tau0 <= 0 ||
      !is.finite(controls$init_tau) || controls$init_tau <= 0) {
    stop("R72 RHS tau0/init_tau must be finite and positive.", call. = FALSE)
  }
  if (controls$freeze_tau_iters < 0L || controls$freeze_tau_warmup_iters < 0L) {
    stop("R72 RHS warm-up durations must be nonnegative.", call. = FALSE)
  }
  controls
}

r72_fit_quantile <- function(library, X, y, tau, likelihood, rhs, qcfg,
                             profile = NULL, init = NULL, seed = 1L) {
  package <- r72_assert_repair_package(library)
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  y <- as.numeric(y)
  tau <- as.numeric(tau)[1L]
  likelihood <- match.arg(tolower(as.character(likelihood)[1L]), c("al", "exal"))
  if (nrow(X) != length(y) || !ncol(X) || any(!is.finite(X)) || any(!is.finite(y))) {
    stop("X and y must be finite and dimensionally compatible.", call. = FALSE)
  }
  control <- r67_vb_control(NULL, qcfg, likelihood, profile)
  prior_sigma <- qcfg$prior_sigma %||% list(a = 1, b = 1)
  args <- list(
    y = y, X = X, p0 = tau,
    beta_prior = "rhs_ns",
    beta_prior_controls = r72_rhs_controls(rhs),
    a_sigma = as.numeric(prior_sigma$a %||% 1),
    b_sigma = as.numeric(prior_sigma$b %||% 1),
    init = init,
    dqlm.ind = identical(likelihood, "al"),
    n.samp = as.integer(qcfg$n_samp %||% 200L),
    vb_control = control,
    verbose = isTRUE(qcfg$verbose %||% FALSE)
  )
  prior_gamma <- qcfg$prior_gamma %||% NULL
  if (!is.null(prior_gamma) && identical(likelihood, "exal")) {
    mu0 <- as.numeric(prior_gamma$mu0 %||% 0)[1L]
    s20 <- as.numeric(prior_gamma$s20 %||% 10)[1L]
    args$log_prior_gamma <- function(gamma) {
      stats::dnorm(gamma, mean = mu0, sd = sqrt(s20), log = TRUE)
    }
  }
  set.seed(as.integer(seed))
  started <- proc.time()[["elapsed"]]
  fit <- do.call(getExportedValue("exdqlm", "exalStaticLDVB"), args)
  attr(fit, "r72_elapsed_seconds") <- as.numeric(proc.time()[["elapsed"]] - started)
  attr(fit, "r72_package_contract") <- package
  fit
}
