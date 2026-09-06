#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    "Usage: pricefm_stage_r67_fork_al_rhsns_probe.R FORK_LIBRARY OUTPUT_JSON",
    call. = FALSE
  )
}

library_path <- normalizePath(args[[1L]], mustWork = TRUE)
output_path <- args[[2L]]
description <- utils::packageDescription("exdqlm", lib.loc = library_path)
namespace <- loadNamespace("exdqlm", lib.loc = library_path)
exports <- getNamespaceExports(namespace)
required <- c("beta_prior", "exal_ldvb_fit", "exal_make_vb_control")
if (!all(required %in% exports)) {
  stop("Fork probe requires the historical QDESN LDVB API.", call. = FALSE)
}

x <- seq(-1, 1, length.out = 120L)
X <- cbind(1, x, sin(3 * x), cos(2 * x))
y <- 0.4 - 0.7 * x + 0.2 * sin(3 * x) + 0.08 * cos(11 * x)
rhs <- list(
  tau0 = 1e-3,
  shrink_intercept = FALSE,
  freeze_tau_iters = 5L,
  freeze_tau_warmup_iters = 5L
)
prior <- getExportedValue("exdqlm", "beta_prior")("rhs_ns", rhs = rhs)
control <- getExportedValue("exdqlm", "exal_make_vb_control")(
  max_iter = 120L,
  min_iter_elbo = 50L,
  tol = 1e-7,
  tol_par = 1e-7,
  n_samp_xi = 20L,
  progress_every = 1000000L,
  verbose = FALSE,
  chunking = list(
    enabled = TRUE,
    mode = "exact",
    chunk_size = 32L,
    order = "sequential",
    trace = FALSE
  )
)
lower <- get("L.fn", envir = namespace)(0.25)
upper <- get("U.fn", envir = namespace)(0.25)
set.seed(7731L)
fit <- getExportedValue("exdqlm", "exal_ldvb_fit")(
  y = y,
  X = X,
  p0 = 0.25,
  gamma_bounds = c(lower, upper),
  likelihood_family = "al",
  al_fixed_gamma = 0,
  beta_prior_obj = prior,
  prior_sigma = list(a = 1, b = 1),
  prior_gamma = list(mu0 = 0, s20 = 10),
  vb_control = control,
  init = list()
)

payload <- list(
  package = "exdqlm",
  version_label = as.character(description$Version),
  repository = if (is.null(description$Repository)) "" else as.character(description$Repository),
  engine = "fork_exal_ldvb_fit_exact_chunked_al_rhs_ns",
  seed = 7731L,
  tau = 0.25,
  tau0 = 1e-3,
  converged = isTRUE(fit$converged),
  iter = as.integer(fit$iter),
  qbeta_m = as.numeric(fit$qbeta$m),
  qbeta_V = as.numeric(fit$qbeta$V),
  sigma = as.numeric(fit$qsiggam$sigma_mean),
  prediction = as.numeric(X %*% fit$qbeta$m),
  exact_chunking = isTRUE(fit$misc$exact_chunking)
)

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
cat(
  jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, digits = 17),
  "\n",
  file = output_path,
  sep = ""
)
