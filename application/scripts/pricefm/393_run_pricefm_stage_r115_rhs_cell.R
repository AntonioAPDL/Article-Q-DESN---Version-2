#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
arg <- function(flag) {
  where <- match(flag, args)
  if (is.na(where) || where == length(args)) stop("missing ", flag, call. = FALSE)
  args[[where + 1L]]
}
sha256 <- function(path) {
  value <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(value[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
read_f64 <- function(path, n) {
  handle <- file(path, open = "rb"); on.exit(close(handle), add = TRUE)
  value <- readBin(handle, "double", n = n, size = 8L, endian = "little")
  if (length(value) != n || any(!is.finite(value))) stop("invalid binary: ", path, call. = FALSE)
  value
}
write_json <- function(value, path) {
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
}

contract_path <- normalizePath(arg("--contract"), mustWork = TRUE)
contract <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
if (!identical(contract$stage, "R115") || !identical(contract$phase, "normal_rhs_pruning") ||
    !(contract$readout_mode %in% c("state_horizon", "state_only")) ||
    !identical(contract$selection_split, "BG_fold1_training_nested_temporal_only") ||
    isTRUE(contract$test_access_authorized) || isTRUE(contract$registry_mutation_authorized) ||
    isTRUE(contract$article_mutation_authorized)) stop("R115 RHS firewall violation", call. = FALSE)
output_dir <- normalizePath(contract$output_dir, mustWork = FALSE)
if (file.exists(file.path(output_dir, "terminal.json"))) {
  existing <- jsonlite::read_json(file.path(output_dir, "terminal.json"), simplifyVector = TRUE)
  if (identical(existing$status, "completed_r115_rhs_cell") &&
      identical(existing$task_contract_sha256, contract$task_contract_sha256)) {
    cat(jsonlite::toJSON(existing, auto_unbox = TRUE, pretty = TRUE), "\n"); quit(status = 0L)
  }
}
if (!identical(sha256(contract$stats_manifest_path), contract$stats_manifest_sha256)) {
  stop("R115 RHS statistic manifest changed", call. = FALSE)
}
meta <- jsonlite::read_json(contract$stats_manifest_path, simplifyVector = TRUE)
for (name in names(meta$files)) {
  path <- file.path(dirname(contract$stats_manifest_path), name)
  if (!identical(sha256(path), meta$files[[name]]$sha256)) stop("R115 statistic changed: ", name, call. = FALSE)
}
p <- as.integer(meta$p); n <- as.integer(meta$n); n_eval <- as.integer(meta$n_eval)
root <- dirname(contract$stats_manifest_path)
stats_value <- list(
  n = n, p = p,
  XtX = matrix(read_f64(file.path(root, "XtX.bin"), p * p), nrow = p, byrow = TRUE),
  Xty = read_f64(file.path(root, "Xty.bin"), p),
  yty = read_f64(file.path(root, "yty.bin"), 1L)
)
X_eval <- matrix(read_f64(file.path(root, "X_eval.bin"), n_eval * p), nrow = n_eval, byrow = TRUE)
y_eval <- read_f64(file.path(root, "y_eval.bin"), n_eval)
source(normalizePath(contract$helper_path, mustWork = TRUE), local = .GlobalEnv)
pkgload::load_all(normalizePath(contract$package_path, mustWork = TRUE), quiet = TRUE, export_all = TRUE)
beta_prior_factory <- get("beta_prior", envir = asNamespace("exdqlm"), inherits = FALSE)
started <- proc.time()[["elapsed"]]
fit <- app_pricefm_fit_rhs_stats(
  stats_value, tau0 = as.numeric(contract$tau0), beta_prior_factory = beta_prior_factory,
  max_iter = as.integer(contract$max_iter), min_iter = as.integer(contract$min_iter),
  tol = as.numeric(contract$tol)
)
elapsed <- proc.time()[["elapsed"]] - started
if (!isTRUE(fit$converged)) stop("R115 RHS cell did not converge", call. = FALSE)
location <- as.numeric(X_eval %*% fit$beta$mean)
variance <- pmax(
  as.numeric(fit$omega2$b / fit$omega2$a) + rowSums((X_eval %*% fit$beta$cov) * X_eval),
  .Machine$double.eps
)
taus <- c(0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
prediction <- sapply(taus, function(tau) location + sqrt(variance) * stats::qnorm(tau))
error <- matrix(y_eval, nrow = n_eval, ncol = length(taus)) - prediction
loss <- pmax(sweep(error, 2L, taus, `*`), sweep(error, 2L, taus - 1, `*`))
if (n_eval %% 96L != 0L) stop("R115 evaluation rows are not horizon aligned", call. = FALSE)
horizon <- rep(seq_len(96L), each = as.integer(n_eval / 96L))
late <- horizon >= 49L
metric <- data.frame(
  candidate_id = contract$candidate_id, readout_mode = contract$readout_mode,
  inner_fold = as.integer(contract$inner_fold), tau_multiplier = as.numeric(contract$tau_multiplier),
  tau0 = as.numeric(contract$tau0), p = p,
  AQL_scaled = mean(loss), AQL_original = mean(loss) * as.numeric(contract$response_scale),
  late_AQL_scaled = mean(loss[late, , drop = FALSE]),
  coverage_10_90 = mean(y_eval >= prediction[, 1L] & y_eval <= prediction[, 7L]),
  width_10_90_scaled = mean(prediction[, 7L] - prediction[, 1L]),
  converged = TRUE, iterations = nrow(fit$trace), train_seconds = elapsed,
  selection_split = contract$selection_split, test_opened = FALSE,
  stringsAsFactors = FALSE
)
parent <- dirname(output_dir); dir.create(parent, recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output_dir), ".tmp."), tmpdir = parent); dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
utils::write.csv(metric, file.path(temporary, "metric_summary.csv"), row.names = FALSE)
utils::write.csv(fit$trace, file.path(temporary, "vb_trace.csv"), row.names = FALSE)
terminal <- list(
  stage = "R115", status = "completed_r115_rhs_cell", task_id = contract$task_id,
  task_contract_sha256 = contract$task_contract_sha256, candidate_id = contract$candidate_id,
  readout_mode = contract$readout_mode, inner_fold = as.integer(contract$inner_fold),
  tau_multiplier = as.numeric(contract$tau_multiplier), tau0 = as.numeric(contract$tau0),
  p = p, n = n, n_eval = n_eval, converged = TRUE, iterations = nrow(fit$trace),
  selection_split = contract$selection_split, test_opened = FALSE,
  registry_mutated = FALSE, article_mutated = FALSE
)
write_json(terminal, file.path(temporary, "terminal.json"))
if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output_dir)) stop("failed to install R115 RHS output", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
