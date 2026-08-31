`%||%` <- function(x, y) if (is.null(x)) y else x

r67_required_exports <- c(
  "exalStaticLDVB",
  "exal_make_vb_control",
  "exal_make_vb_sigmagam_control"
)

r67_fork_only_exports <- c(
  "beta_prior",
  "exal_ldvb_fit",
  "normal_desn_fit",
  "qdesn_fit_vb"
)

r67_assert_cran_package <- function(library, expected_version = "1.1.1") {
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
  exports <- getNamespaceExports(namespace)
  missing <- setdiff(r67_required_exports, exports)
  fork_only <- intersect(r67_fork_only_exports, exports)
  if (!identical(as.character(description$Version), as.character(expected_version))) {
    stop("Expected exdqlm ", expected_version, ", observed ", description$Version, call. = FALSE)
  }
  if (!identical(as.character(description$Repository), "CRAN")) {
    stop("The exdqlm runtime is not marked Repository: CRAN.", call. = FALSE)
  }
  if (length(missing) || length(fork_only)) {
    stop(
      "Unexpected exdqlm API; missing=", paste(missing, collapse = ","),
      "; fork_only=", paste(fork_only, collapse = ","),
      call. = FALSE
    )
  }
  list(
    library = library,
    package_path = normalizePath(file.path(library, "exdqlm"), mustWork = TRUE),
    version = as.character(description$Version),
    repository = as.character(description$Repository),
    packaged = as.character(description$Packaged),
    exports = sort(exports)
  )
}

r67_rhs_controls <- function(rhs) {
  rhs <- rhs %||% list()
  controls <- list(
    tau0 = as.numeric(rhs$tau0 %||% 1),
    shrink_intercept = isTRUE(rhs$shrink_intercept %||% FALSE),
    freeze_tau_iters = as.integer(rhs$freeze_tau_iters %||% 0L),
    freeze_tau_warmup_iters = as.integer(rhs$freeze_tau_warmup_iters %||% 0L)
  )
  if (!is.finite(controls$tau0) || controls$tau0 <= 0) {
    stop("RHS-NS tau0 must be finite and positive.", call. = FALSE)
  }
  controls
}

r67_sigmagam_control <- function(namespace, profile) {
  profile <- profile %||% list()
  builder <- getExportedValue("exdqlm", "exal_make_vb_sigmagam_control")
  do.call(builder, list(
    factorization = as.character(profile$factorization %||% "structured"),
    structured_grid_size = as.integer(profile$structured_grid_size %||% 151L),
    structured_span_sd = as.numeric(profile$structured_span_sd %||% 6),
    freeze_warmup_iters = as.integer(profile$freeze_warmup_iters %||% 10L),
    force_after_warmup = isTRUE(profile$force_after_warmup %||% TRUE),
    postwarmup_damping = as.numeric(profile$postwarmup_damping %||% 0.2),
    postwarmup_damping_iters = as.integer(profile$postwarmup_damping_iters %||% 30L),
    min_postwarmup_updates = as.integer(profile$min_postwarmup_updates %||% 35L)
  ))
}

r67_vb_control <- function(namespace, qcfg, likelihood, profile = NULL) {
  qcfg <- qcfg %||% list()
  likelihood <- match.arg(tolower(as.character(likelihood)[1L]), c("al", "exal"))
  args <- list(
    max_iter = as.integer(qcfg$max_iter %||% 150L),
    tol = as.numeric(qcfg$tol %||% 1e-4),
    n_samp_xi = as.integer(qcfg$n_samp_xi %||% 200L),
    verbose = isTRUE(qcfg$verbose %||% FALSE)
  )
  if (identical(likelihood, "exal")) {
    args$sigmagam <- r67_sigmagam_control(namespace, profile)
  }
  builder <- getExportedValue("exdqlm", "exal_make_vb_control")
  control <- do.call(builder, args)
  ignored <- intersect(
    names(qcfg),
    c("min_iter_elbo", "tol_par", "progress_every", "chunking")
  )
  attr(control, "r67_ignored_fork_controls") <- ignored
  control
}

r67_safe_sigma <- function(fit) {
  value <- fit$qsig$E_sigma %||% fit$qsiggam$sigma_mean %||% NA_real_
  value <- as.numeric(value)[1L]
  if (!is.finite(value) || value <= 0) NA_real_ else value
}

r67_init_from_fit <- function(fit, gamma_zero = FALSE) {
  beta <- as.numeric(fit$qbeta$m %||% numeric())
  if (!length(beta) || any(!is.finite(beta))) {
    stop("Warm-start fit does not contain a finite qbeta mean.", call. = FALSE)
  }
  init <- list(beta = beta)
  sigma <- r67_safe_sigma(fit)
  if (is.finite(sigma)) init$sigma <- sigma
  if (isTRUE(gamma_zero)) init$gamma <- 0
  init
}

r67_fit_quantile <- function(library, X, y, tau, likelihood, rhs, qcfg,
                             profile = NULL, init = NULL, seed = 1L,
                             expected_version = "1.1.1") {
  package <- r67_assert_cran_package(library, expected_version = expected_version)
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  y <- as.numeric(y)
  tau <- as.numeric(tau)[1L]
  likelihood <- match.arg(tolower(as.character(likelihood)[1L]), c("al", "exal"))
  if (nrow(X) != length(y) || !ncol(X) || any(!is.finite(X)) || any(!is.finite(y))) {
    stop("X and y must be finite and dimensionally compatible.", call. = FALSE)
  }
  if (!is.finite(tau) || tau <= 0 || tau >= 1) {
    stop("tau must lie strictly between zero and one.", call. = FALSE)
  }
  control <- r67_vb_control(NULL, qcfg, likelihood, profile)
  prior_sigma <- qcfg$prior_sigma %||% list(a = 1, b = 1)
  prior_gamma <- qcfg$prior_gamma %||% NULL
  log_prior_gamma <- if (is.null(prior_gamma) || identical(likelihood, "al")) {
    NULL
  } else {
    mu0 <- as.numeric(prior_gamma$mu0 %||% 0)[1L]
    s20 <- as.numeric(prior_gamma$s20 %||% 10)[1L]
    if (!is.finite(s20) || s20 <= 0) stop("prior_gamma$s20 must be positive.", call. = FALSE)
    function(gamma) stats::dnorm(gamma, mean = mu0, sd = sqrt(s20), log = TRUE)
  }
  args <- list(
    y = y,
    X = X,
    p0 = tau,
    beta_prior = "rhs_ns",
    beta_prior_controls = r67_rhs_controls(rhs),
    a_sigma = as.numeric(prior_sigma$a %||% 1),
    b_sigma = as.numeric(prior_sigma$b %||% 1),
    init = init,
    dqlm.ind = identical(likelihood, "al"),
    n.samp = as.integer(qcfg$n_samp %||% 200L),
    vb_control = control,
    verbose = isTRUE(qcfg$verbose %||% FALSE)
  )
  if (!is.null(log_prior_gamma)) args$log_prior_gamma <- log_prior_gamma
  set.seed(as.integer(seed))
  started <- proc.time()[["elapsed"]]
  fit <- do.call(getExportedValue("exdqlm", "exalStaticLDVB"), args)
  attr(fit, "r67_elapsed_seconds") <- as.numeric(proc.time()[["elapsed"]] - started)
  attr(fit, "r67_package_contract") <- package[c("library", "package_path", "version", "repository", "packaged")]
  attr(fit, "r67_control_audit") <- list(
    likelihood = likelihood,
    public_api = "exalStaticLDVB",
    ignored_fork_controls = attr(control, "r67_ignored_fork_controls") %||% character(),
    exact_chunking_claimed = FALSE
  )
  fit
}

r67_prediction_frame <- function(fit, X, rows, method_id, tau, split = "val") {
  prediction <- as.numeric(as.matrix(X) %*% fit$qbeta$m)
  if (length(prediction) != nrow(rows)) {
    stop("Prediction and row metadata lengths differ.", call. = FALSE)
  }
  data.frame(
    method_id = as.character(method_id),
    split = as.character(split),
    origin_id = rows$origin_id,
    horizon = rows$horizon,
    tau = as.numeric(tau),
    pred_scaled = prediction,
    stringsAsFactors = FALSE
  )
}
