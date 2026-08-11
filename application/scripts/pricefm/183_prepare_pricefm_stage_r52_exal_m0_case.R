#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(jsonlite)
  library(yaml)
})

`%||%` <- function(x, y) if (is.null(x)) y else x
args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
cfg_path <- arg("--config")
if (is.null(cfg_path)) stop("--config is required", call. = FALSE)
force <- tolower(arg("--force", "false")) %in% c("1", "true", "yes")
cfg <- yaml::read_yaml(cfg_path)$pricefm_stage_r52_case
out <- cfg$output_dir
summary_path <- file.path(out, "case_summary.json")
if (file.exists(summary_path) && !force) {
  existing <- jsonlite::fromJSON(summary_path)
  if (identical(existing$status, "completed")) {
    cat(jsonlite::toJSON(existing, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(save = "no", status = 0L)
  }
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
init_dir <- file.path(out, "initialization")
if (dir.exists(init_dir) && length(list.files(init_dir)) && !force) {
  stop("Incomplete initialization exists; rerun with --force true", call. = FALSE)
}
dir.create(init_dir, recursive = TRUE, showWarnings = FALSE)
if (force && length(list.files(init_dir))) {
  unlink(list.files(init_dir, full.names = TRUE), recursive = TRUE, force = TRUE)
}

started <- proc.time()[["elapsed"]]
adapter_manifest_path <- file.path(cfg$adapter_dir, "adapter_manifest.json")
if (!file.exists(adapter_manifest_path)) {
  status <- system2(
    cfg$python_executable,
    c(cfg$adapter_builder, "--smoke-config", cfg$adapter_config, "--force", "true")
  )
  if (!identical(status, 0L)) stop("Adapter build failed for ", cfg$id, call. = FALSE)
}

source_manifest <- jsonlite::fromJSON(cfg$source_adapter_manifest, simplifyVector = FALSE)
rebuilt_manifest <- jsonlite::fromJSON(adapter_manifest_path, simplifyVector = FALSE)
hash_rows <- list()
k <- 0L
for (split in c("train", "val", "test")) {
  for (field in c("X_sha256", "y_sha256", "rows_sha256")) {
    k <- k + 1L
    old <- source_manifest$splits[[split]][[field]]
    new <- rebuilt_manifest$splits[[split]][[field]]
    hash_rows[[k]] <- data.frame(
      split = split, field = field, source_sha256 = old,
      rebuilt_sha256 = new, passed = identical(old, new), stringsAsFactors = FALSE
    )
  }
}
k <- k + 1L
old_map <- source_manifest$feature_manifest$feature_map_matrix_sha256
new_map <- rebuilt_manifest$feature_manifest$feature_map_matrix_sha256
hash_rows[[k]] <- data.frame(
  split = "all", field = "feature_map_matrix_sha256", source_sha256 = old_map,
  rebuilt_sha256 = new_map, passed = identical(old_map, new_map), stringsAsFactors = FALSE
)
hashes <- do.call(rbind, hash_rows)
utils::write.csv(hashes, file.path(out, "design_replay_audit.csv"), row.names = FALSE)
if (!all(hashes$passed)) stop("Rebuilt adapter hash mismatch for ", cfg$id, call. = FALSE)

pkgload::load_all(cfg$exdqlm_path, quiet = TRUE)
source_cfg <- yaml::read_yaml(cfg$source_config)$pricefm_desn_smoke
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
X_train <- read_matrix(file.path(cfg$adapter_dir, "X_train.csv"))
y_train <- read_vector(file.path(cfg$adapter_dir, "y_train.csv"))
if (nrow(X_train) != length(y_train)) stop("Training design mismatch", call. = FALSE)

rhs_cfg <- source_cfg$rhs_ns
rhs <- list(
  tau0 = as.numeric(rhs_cfg$tau0),
  shrink_intercept = isTRUE(rhs_cfg$shrink_intercept),
  freeze_tau_iters = as.integer(rhs_cfg$freeze_tau_iters %||% 0L),
  freeze_tau_warmup_iters = as.integer(rhs_cfg$freeze_tau_warmup_iters %||% 0L)
)
prior <- exdqlm::beta_prior("rhs_ns", rhs = rhs)
safe_sigma <- function(fit) {
  value <- fit$qsiggam$sigma_mean %||% NULL
  if (is.null(value)) {
    omega <- as.numeric(fit$omega2$mean %||% fit$omega2$mode %||% NA_real_)[1L]
    value <- if (is.finite(omega) && omega > 0) sqrt(omega) else NA_real_
  }
  value <- as.numeric(value)[1L]
  if (!is.finite(value) || value <= 0) stop("Nonfinite VB sigma", call. = FALSE)
  value
}
safe_gamma <- function(fit) {
  value <- as.numeric(fit$qsiggam$gamma_mean %||% 0)[1L]
  if (!is.finite(value)) stop("Nonfinite VB gamma", call. = FALSE)
  value
}
vb_init <- function(fit, gamma_zero = FALSE) {
  beta_m <- fit$qbeta$m %||% fit$beta$mean
  beta_V <- fit$qbeta$V %||% fit$beta$cov
  if (length(beta_m) != ncol(X_train)) stop("VB beta dimension mismatch", call. = FALSE)
  init <- list(
    beta_m = as.numeric(beta_m), beta_V = as.matrix(beta_V),
    sigma = safe_sigma(fit), gamma = if (gamma_zero) 0 else safe_gamma(fit)
  )
  state <- fit$beta_prior$state %||% NULL
  if (!is.null(state)) init$beta_state <- state
  init
}
make_control <- function() {
  qcfg <- source_cfg$qdesn_vb
  exdqlm::exal_make_vb_control(
    max_iter = as.integer(qcfg$max_iter),
    min_iter_elbo = as.integer(qcfg$min_iter_elbo),
    tol = as.numeric(qcfg$tol), tol_par = as.numeric(qcfg$tol_par),
    n_samp_xi = as.integer(qcfg$n_samp_xi), progress_every = 1000000L,
    verbose = FALSE, chunking = qcfg$chunking
  )
}
fit_vb <- function(likelihood, tau, init = list()) {
  exdqlm::exal_ldvb_fit(
    y = y_train, X = X_train, p0 = tau,
    gamma_bounds = c(exdqlm:::L.fn(tau), exdqlm:::U.fn(tau)),
    likelihood_family = likelihood, al_fixed_gamma = 0,
    beta_prior_obj = prior, prior_sigma = source_cfg$qdesn_vb$prior_sigma,
    prior_gamma = source_cfg$qdesn_vb$prior_gamma,
    vb_control = make_control(), init = init
  )
}

set.seed(as.integer(cfg$seed))
normal_fit <- exdqlm::normal_desn_fit(
  X_train, y_train, beta_prior_type = "rhs_ns",
  omega_prior = source_cfg$normal$omega_prior, rhs = rhs,
  control = source_cfg$normal$vb_control
)
normal_init <- vb_init(normal_fit, gamma_zero = TRUE)

metric_source <- utils::read.csv(cfg$source_metric_summary, stringsAsFactors = FALSE)
metric_source <- metric_source[
  metric_source$method_id == cfg$method_id & metric_source$split %in% c("val", "test"),
  , drop = FALSE
]
scale_by_split <- setNames(vapply(c("val", "test"), function(split) {
  d <- metric_source[metric_source$split == split, , drop = FALSE]
  original <- d$AQL[d$unit == "original"]
  scaled <- d$AQL[d$unit == "scaled"]
  if (length(original) != 1L || length(scaled) != 1L || !is.finite(scaled) || scaled <= 0) {
    stop("Cannot recover metric scale for ", split, call. = FALSE)
  }
  as.numeric(original / scaled)
}, numeric(1L)), c("val", "test"))
pinball <- function(y, pred, tau) ifelse(y >= pred, tau * (y - pred), (1 - tau) * (pred - y))
prediction_inputs <- lapply(c("val", "test"), function(split) list(
  X = read_matrix(file.path(cfg$adapter_dir, paste0("X_", split, ".csv"))),
  y = read_vector(file.path(cfg$adapter_dir, paste0("y_", split, ".csv")))
))
names(prediction_inputs) <- c("val", "test")

init_rows <- list()
metric_rows <- list()
taus <- as.numeric(unlist(cfg$taus, use.names = FALSE))
for (j in seq_along(taus)) {
  tau <- taus[[j]]
  set.seed(as.integer(cfg$seed) + j * 1009L)
  al_fit <- fit_vb("al", tau, normal_init)
  exal_fit <- fit_vb("exal", tau, vb_init(al_fit, gamma_zero = TRUE))
  beta <- as.numeric(exal_fit$qbeta$m)
  sigma <- safe_sigma(exal_fit)
  gamma <- safe_gamma(exal_fit)
  state <- exal_fit$beta_prior$state %||% NULL
  init <- list(
    beta = beta, sigma = sigma, gamma = gamma,
    beta_prior_state = state,
    v = as.numeric(exal_fit$qv$E_v %||% exal_fit$qv$m %||% rep(1, nrow(X_train))),
    s = pmax(as.numeric(exal_fit$qs$E_s %||% exal_fit$qs$m %||% rep(0, nrow(X_train))), 0)
  )
  label <- sprintf("tau%02d", as.integer(round(tau * 100)))
  init_path <- file.path(init_dir, paste0(label, "_init.rds"))
  saveRDS(init, init_path, compress = "xz")
  init_rows[[j]] <- data.frame(
    tau = tau, init_path = init_path, n_features = length(beta), sigma = sigma,
    gamma = gamma, beta_l2 = sqrt(sum(beta^2)), finite = all(is.finite(beta)) &&
      is.finite(sigma) && is.finite(gamma), stringsAsFactors = FALSE
  )
  for (split in c("val", "test")) {
    pred <- as.numeric(prediction_inputs[[split]]$X %*% beta)
    loss <- mean(pinball(prediction_inputs[[split]]$y, pred, tau))
    metric_rows[[length(metric_rows) + 1L]] <- data.frame(
      tau = tau, split = split, scaled_AQL = loss,
      scale_factor = scale_by_split[[split]], original_AQL = loss * scale_by_split[[split]],
      stringsAsFactors = FALSE
    )
  }
}
initializations <- do.call(rbind, init_rows)
metrics <- do.call(rbind, metric_rows)
utils::write.csv(initializations, file.path(out, "vb_initialization_manifest.csv"), row.names = FALSE)
utils::write.csv(metrics, file.path(out, "vb_replay_metrics.csv"), row.names = FALSE)
if (!all(initializations$finite) || nrow(initializations) != 7L) {
  stop("Incomplete or nonfinite VB initialization", call. = FALSE)
}

vb_test <- mean(metrics$original_AQL[metrics$split == "test"])
vb_val <- mean(metrics$original_AQL[metrics$split == "val"])
authority_test <- as.numeric(cfg$authority_qdesn_AQL)
parity_abs <- abs(vb_test - authority_test)
parity_rel <- parity_abs / max(abs(authority_test), .Machine$double.eps)
parity_pass <- is.finite(parity_rel) && parity_rel <= as.numeric(cfg$vb_parity_relative_tolerance)
summary <- list(
  status = "completed", id = cfg$id, region = cfg$region, fold = as.integer(cfg$fold),
  design_hashes_passed = sum(hashes$passed), design_hashes_total = nrow(hashes),
  initializations = nrow(initializations), vb_validation_AQL = vb_val,
  vb_test_AQL = vb_test, authority_qdesn_AQL = authority_test,
  vb_test_parity_abs_delta = parity_abs, vb_test_parity_relative_delta = parity_rel,
  promotion_replay_eligible = parity_pass,
  m0_launch_eligible = all(hashes$passed) && all(initializations$finite),
  core_update_mode = cfg$core_update_mode,
  elapsed_seconds = as.numeric(proc.time()[["elapsed"]] - started),
  registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE
)
tmp_summary <- paste0(summary_path, ".tmp")
writeLines(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), tmp_summary)
if (!file.rename(tmp_summary, summary_path)) stop("Could not atomically publish case summary", call. = FALSE)
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")
