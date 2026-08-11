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
cfg <- yaml::read_yaml(cfg_path)$pricefm_stage_r53_m0
out <- cfg$output_dir
summary_path <- file.path(out, "job_summary.json")
if (file.exists(summary_path) && !force) {
  existing <- jsonlite::fromJSON(summary_path)
  if (identical(existing$status, "completed")) {
    cat(jsonlite::toJSON(existing, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(save = "no", status = 0L)
  }
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
owner_path <- file.path(out, "job_owner.json")
if (file.exists(owner_path)) {
  owner <- jsonlite::fromJSON(owner_path)
  if (!identical(owner$id, cfg$id)) stop("Output ownership mismatch", call. = FALSE)
} else {
  writeLines(jsonlite::toJSON(list(id = cfg$id, config = normalizePath(cfg_path)), auto_unbox = TRUE, pretty = TRUE), owner_path)
}
known_outputs <- c(
  "posterior_draws.rds", "posterior_mean_predictions.csv.gz", "scalar_draws.csv.gz",
  "job_summary.json", "job_summary.json.tmp"
)
if (force) unlink(file.path(out, known_outputs), force = TRUE)

case_summary <- jsonlite::fromJSON(cfg$case_summary)
if (!identical(case_summary$status, "completed") || !isTRUE(case_summary$m0_launch_eligible)) {
  stop("Case replay has not authorized M0: ", cfg$case_id, call. = FALSE)
}
case_cfg <- yaml::read_yaml(cfg$case_config)$pricefm_stage_r52_case
source_cfg <- yaml::read_yaml(case_cfg$source_config)$pricefm_desn_smoke
pkgload::load_all(cfg$exdqlm_path, quiet = TRUE)
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
X <- read_matrix(file.path(cfg$adapter_dir, "X_train.csv"))
y <- read_vector(file.path(cfg$adapter_dir, "y_train.csv"))
if (nrow(X) != length(y)) stop("Training row mismatch", call. = FALSE)
init <- readRDS(cfg$init_path)
if (length(init$beta) != ncol(X)) stop("Initial beta dimension mismatch", call. = FALSE)

rhs_cfg <- source_cfg$rhs_ns
rhs <- list(
  tau0 = as.numeric(rhs_cfg$tau0),
  shrink_intercept = isTRUE(rhs_cfg$shrink_intercept),
  freeze_tau_iters = as.integer(rhs_cfg$freeze_tau_iters %||% 0L),
  freeze_tau_warmup_iters = as.integer(rhs_cfg$freeze_tau_warmup_iters %||% 0L)
)
prior <- exdqlm::beta_prior("rhs_ns", rhs = rhs)
control <- exdqlm::exal_make_mcmc_control(
  n_burn = as.integer(cfg$n_burn), n_mcmc = as.integer(cfg$n_mcmc),
  thin = as.integer(cfg$thin), verbose = TRUE, progress_every = 100L,
  init_from_vb = FALSE, store_latent_draws = FALSE, store_rhs_draws = TRUE,
  conditioning = list(mode = "diag_scale", intercept_column = 1L),
  precision_beta = exdqlm::exal_make_precision_beta_control("recommended"),
  slice = list(
    core_update_mode = as.character(cfg$core_update_mode),
    width_gamma = as.numeric(cfg$width_gamma),
    max_steps_out = as.integer(cfg$max_steps_out),
    max_shrink = as.integer(cfg$max_shrink),
    core_extra_passes = as.integer(cfg$core_extra_passes)
  ),
  control = list(rng_seed = as.integer(cfg$seed))
)
if (!identical(control$slice$core_update_mode, "m0_v_collapsed_support_logit")) {
  stop("Collapsed-M0 control was not consumed", call. = FALSE)
}

set.seed(as.integer(cfg$seed))
started <- proc.time()[["elapsed"]]
fit <- exdqlm::exal_mcmc_fit(
  y = y, X = X, p0 = as.numeric(cfg$tau),
  gamma_bounds = c(exdqlm:::L.fn(as.numeric(cfg$tau)), exdqlm:::U.fn(as.numeric(cfg$tau))),
  likelihood_family = "exal", beta_prior_obj = prior,
  prior_sigma = source_cfg$qdesn_vb$prior_sigma,
  prior_gamma = source_cfg$qdesn_vb$prior_gamma,
  mcmc_control = control, init = init
)
elapsed <- proc.time()[["elapsed"]] - started
mode_observed <- as.character(fit$diagnostics$core_update_mode %||% NA_character_)[1L]
if (!identical(mode_observed, "m0_v_collapsed_support_logit")) {
  stop("Fit diagnostics did not record collapsed M0", call. = FALSE)
}

beta_draws <- as.matrix(fit$samp.beta)
scalar <- data.frame(
  iter = seq_len(nrow(beta_draws)), sigma = as.numeric(fit$samp.sigma),
  gamma = as.numeric(fit$samp.gamma), rhs_tau = as.numeric(fit$samp.tau),
  rhs_c2 = as.numeric(fit$samp.c2), beta_l2 = sqrt(rowSums(beta_draws * beta_draws)),
  stringsAsFactors = FALSE
)
finite <- all(is.finite(beta_draws)) && all(is.finite(as.matrix(scalar[, -1L])))
if (!finite) stop("Collapsed-M0 produced nonfinite draws", call. = FALSE)
saveRDS(list(beta = beta_draws, scalar = scalar), file.path(out, "posterior_draws.rds"), compress = "xz")
utils::write.csv(scalar, gzfile(file.path(out, "scalar_draws.csv.gz")), row.names = FALSE)

beta_mean <- colMeans(beta_draws)
prediction_rows <- list()
for (split in c("val", "test")) {
  X_new <- read_matrix(file.path(cfg$adapter_dir, paste0("X_", split, ".csv")))
  rows <- utils::read.csv(file.path(cfg$adapter_dir, paste0("rows_", split, ".csv")), stringsAsFactors = FALSE)
  prediction_rows[[split]] <- data.frame(
    id = cfg$id, case_id = cfg$case_id, region = cfg$region, fold = as.integer(cfg$fold),
    chain = as.integer(cfg$chain), split = split, origin_id = rows$origin_id,
    horizon = rows$horizon, tau = as.numeric(cfg$tau),
    pred_scaled = as.numeric(X_new %*% beta_mean), stringsAsFactors = FALSE
  )
}
utils::write.csv(
  do.call(rbind, prediction_rows),
  gzfile(file.path(out, "posterior_mean_predictions.csv.gz")), row.names = FALSE
)

summary <- list(
  status = "completed", id = cfg$id, case_id = cfg$case_id,
  region = cfg$region, fold = as.integer(cfg$fold), tau = as.numeric(cfg$tau),
  chain = as.integer(cfg$chain), seed = as.integer(cfg$seed),
  n_train = nrow(X), n_features = ncol(X), n_burn = as.integer(cfg$n_burn),
  n_mcmc = nrow(beta_draws), elapsed_seconds = as.numeric(elapsed),
  init_from_vb = FALSE, explicit_vb_start = TRUE, finite_draws = finite,
  core_update_mode = mode_observed,
  gamma_density_evaluations_mean = as.numeric(fit$diagnostics$gamma_density_evaluations_mean %||% NA_real_),
  gamma_steps_out_mean = as.numeric(fit$diagnostics$gamma_steps_out_mean %||% NA_real_),
  gamma_shrink_mean = as.numeric(fit$diagnostics$gamma_shrink_mean %||% NA_real_),
  registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE
)
tmp <- paste0(summary_path, ".tmp")
writeLines(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), tmp)
if (!file.rename(tmp, summary_path)) stop("Could not atomically publish job summary", call. = FALSE)
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")
