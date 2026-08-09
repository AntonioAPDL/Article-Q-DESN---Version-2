#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(yaml)
  library(jsonlite)
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
cfg <- yaml::read_yaml(cfg_path)$pricefm_stage_r50_mcmc
out <- cfg$output_dir
if (dir.exists(out) && length(list.files(out)) && !force) {
  stop("Output exists: ", out, call. = FALSE)
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)

pkgload::load_all(cfg$exdqlm_path, quiet = TRUE)
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
adapter <- cfg$adapter_dir
X <- read_matrix(file.path(adapter, "X_train.csv"))
y <- read_vector(file.path(adapter, "y_train.csv"))
rows <- utils::read.csv(file.path(adapter, "rows_train.csv"), stringsAsFactors = FALSE)
if (nrow(X) != length(y) || length(y) != nrow(rows)) stop("Training row mismatch", call. = FALSE)

base_frequency <- as.integer(cfg$training_weighting$base_frequency)
focused_frequency <- as.integer(cfg$training_weighting$focused_frequency)
frequency <- rep.int(base_frequency, nrow(rows))
frequency[rows$horizon >= 25L & rows$horizon <= 48L] <- focused_frequency
idx <- rep(seq_len(nrow(rows)), times = frequency)
if (identical(cfg$component, "horizon_1_24")) {
  idx <- idx[rows$horizon[idx] >= 1L & rows$horizon[idx] <= 24L]
} else if (!identical(cfg$component, "shared_static")) {
  stop("Unknown component: ", cfg$component, call. = FALSE)
}
X_fit <- X[idx, , drop = FALSE]
y_fit <- y[idx]
expected <- if (identical(cfg$component, "shared_static")) {
  as.integer(cfg$training_weighting$expected_rows)
} else {
  sum(frequency[rows$horizon >= 1L & rows$horizon <= 24L])
}
if (nrow(X_fit) != expected) stop("Weighted row count changed: ", nrow(X_fit), " != ", expected, call. = FALSE)

init_table <- utils::read.csv(cfg$init_manifest, stringsAsFactors = FALSE)
init_row <- init_table[init_table$component == cfg$component & abs(init_table$tau - as.numeric(cfg$tau)) < 1e-12, , drop = FALSE]
if (nrow(init_row) != 1L) stop("Missing unique initialization row", call. = FALSE)
beta_init <- as.numeric(read_matrix(cfg$init_beta_path)[, 1L])
if (length(beta_init) != ncol(X_fit)) stop("Initial beta dimension mismatch", call. = FALSE)
init <- list(beta = beta_init, sigma = init_row$sigma_init[[1L]], gamma = init_row$gamma_init[[1L]])

rhs <- list(
  tau0 = as.numeric(cfg$tau0),
  shrink_intercept = isTRUE(cfg$shrink_intercept),
  freeze_tau_iters = 5L,
  freeze_tau_warmup_iters = 5L
)
prior <- exdqlm::beta_prior("rhs_ns", rhs = rhs)
control <- exdqlm::exal_make_mcmc_control(
  n_burn = as.integer(cfg$n_burn),
  n_mcmc = as.integer(cfg$n_mcmc),
  thin = as.integer(cfg$thin),
  verbose = TRUE,
  progress_every = 100L,
  init_from_vb = FALSE,
  store_latent_draws = FALSE,
  store_rhs_draws = FALSE,
  conditioning = list(mode = "diag_scale", intercept_column = 1L),
  precision_beta = exdqlm::exal_make_precision_beta_control("recommended")
)
set.seed(as.integer(cfg$seed))
started <- proc.time()[["elapsed"]]
fit <- exdqlm::exal_mcmc_fit(
  y = y_fit,
  X = X_fit,
  p0 = as.numeric(cfg$tau),
  gamma_bounds = c(exdqlm:::L.fn(as.numeric(cfg$tau)), exdqlm:::U.fn(as.numeric(cfg$tau))),
  likelihood_family = "exal",
  beta_prior_obj = prior,
  prior_sigma = list(a = 1, b = 1),
  prior_gamma = list(mu0 = 0, s20 = 10),
  mcmc_control = control,
  init = init
)
elapsed <- proc.time()[["elapsed"]] - started

beta_draws <- as.matrix(fit$samp.beta)
draws <- data.frame(
  iter = seq_len(nrow(beta_draws)),
  sigma = as.numeric(fit$samp.sigma),
  gamma = as.numeric(fit$samp.gamma),
  rhs_tau = as.numeric(fit$samp.tau),
  rhs_c2 = as.numeric(fit$samp.c2),
  beta_l2 = sqrt(rowSums(beta_draws * beta_draws)),
  stringsAsFactors = FALSE
)
saveRDS(list(beta = beta_draws, scalar = draws), file.path(out, "posterior_draws.rds"), compress = "xz")

beta_mean <- colMeans(beta_draws)
prediction_rows <- list()
for (split in c("val", "test")) {
  X_new <- read_matrix(file.path(adapter, paste0("X_", split, ".csv")))
  row_new <- utils::read.csv(file.path(adapter, paste0("rows_", split, ".csv")), stringsAsFactors = FALSE)
  use <- if (identical(cfg$component, "horizon_1_24")) row_new$horizon >= 1L & row_new$horizon <= 24L else rep(TRUE, nrow(row_new))
  prediction_rows[[split]] <- data.frame(
    id = cfg$id, component = cfg$component, chain = as.integer(cfg$chain), split = split,
    origin_id = row_new$origin_id[use], horizon = row_new$horizon[use], tau = as.numeric(cfg$tau),
    pred_scaled = as.numeric(X_new[use, , drop = FALSE] %*% beta_mean), stringsAsFactors = FALSE
  )
}
utils::write.csv(do.call(rbind, prediction_rows), file.path(out, "posterior_mean_predictions.csv"), row.names = FALSE)
utils::write.csv(draws, gzfile(file.path(out, "scalar_draws.csv.gz")), row.names = FALSE)
summary <- list(
  status = "completed", id = cfg$id, component = cfg$component, tau = as.numeric(cfg$tau),
  chain = as.integer(cfg$chain), seed = as.integer(cfg$seed), n_train = nrow(X_fit),
  n_features = ncol(X_fit), n_burn = as.integer(cfg$n_burn), n_mcmc = nrow(beta_draws),
  elapsed_seconds = as.numeric(elapsed), init_from_vb = FALSE,
  finite_draws = all(is.finite(beta_draws)) && all(is.finite(as.matrix(draws[, -1L]))),
  registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE
)
writeLines(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), file.path(out, "job_summary.json"))
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")
