`%||%` <- function(x, y) if (is.null(x)) y else x

r75_assert_repair_package <- function(
    library,
    expected_version = getOption("pricefm.expected_exdqlm_version", "1.1.1.9002"),
    expected_repair = getOption(
      "pricefm.expected_exdqlm_repair", "scale-aware-SPD-plus-large-n-GIG"
    )) {
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
  expected_base <- "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
  if (!identical(as.character(description$Version), expected_version) ||
      !identical(as.character(description$Repository), "PriceFM-local") ||
      !identical(as.character(description[["Config/PriceFM/base-tarball-sha256"]]), expected_base) ||
      !identical(as.character(description[["Config/PriceFM/repair"]]), expected_repair)) {
    stop("R75 package provenance metadata is invalid.", call. = FALSE)
  }
  exports <- getNamespaceExports(namespace)
  missing <- setdiff(r67_required_exports, exports)
  fork_only <- intersect(r67_fork_only_exports, exports)
  if (length(missing) || length(fork_only)) {
    stop("Unexpected R75 public API surface.", call. = FALSE)
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

r75_fit_quantile <- function(library, X, y, tau, rhs, qcfg,
                             profile = NULL, init = NULL, seed = 1L) {
  package <- r75_assert_repair_package(library)
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  y <- as.numeric(y)
  tau <- as.numeric(tau)[1L]
  if (nrow(X) != length(y) || !ncol(X) || any(!is.finite(X)) || any(!is.finite(y))) {
    stop("X and y must be finite and dimensionally compatible.", call. = FALSE)
  }
  if (!is.finite(tau) || tau <= 0 || tau >= 1) {
    stop("tau must lie strictly between zero and one.", call. = FALSE)
  }
  control <- r67_vb_control(NULL, qcfg, "exal", profile)
  prior_sigma <- qcfg$prior_sigma %||% list(a = 1, b = 1)
  prior_gamma <- qcfg$prior_gamma %||% list(mu0 = 0, s20 = 10)
  mu0 <- as.numeric(prior_gamma$mu0 %||% 0)[1L]
  s20 <- as.numeric(prior_gamma$s20 %||% 10)[1L]
  if (!is.finite(s20) || s20 <= 0) stop("prior_gamma$s20 must be positive.", call. = FALSE)
  args <- list(
    y = y, X = X, p0 = tau,
    beta_prior = "rhs_ns",
    beta_prior_controls = r72_rhs_controls(rhs),
    a_sigma = as.numeric(prior_sigma$a %||% 1),
    b_sigma = as.numeric(prior_sigma$b %||% 1),
    log_prior_gamma = function(gamma) stats::dnorm(gamma, mean = mu0, sd = sqrt(s20), log = TRUE),
    init = init, dqlm.ind = FALSE,
    n.samp = as.integer(qcfg$n_samp %||% 200L),
    vb_control = control,
    verbose = isTRUE(qcfg$verbose %||% FALSE)
  )
  set.seed(as.integer(seed))
  started <- proc.time()[["elapsed"]]
  fit <- do.call(getExportedValue("exdqlm", "exalStaticLDVB"), args)
  attr(fit, "r75_elapsed_seconds") <- as.numeric(proc.time()[["elapsed"]] - started)
  attr(fit, "r75_package_contract") <- package
  fit
}
