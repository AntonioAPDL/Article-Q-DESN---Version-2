#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
arg <- function(flag) {
  where <- match(flag, args)
  if (is.na(where) || where == length(args)) stop("missing ", flag, call. = FALSE)
  args[[where + 1L]]
}
records <- function(value) {
  if (is.data.frame(value)) lapply(seq_len(nrow(value)), function(i) as.list(value[i, , drop = FALSE])) else value
}
sha256 <- function(path) {
  value <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(value[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
read_f64 <- function(path, n) {
  handle <- file(path, open = "rb")
  on.exit(close(handle), add = TRUE)
  value <- readBin(handle, what = "double", n = n, size = 8L, endian = "little")
  if (length(value) != n || any(!is.finite(value))) stop("invalid float64 artifact: ", path, call. = FALSE)
  value
}
write_f64 <- function(path, value, row_major = FALSE) {
  handle <- file(path, open = "wb")
  on.exit(close(handle), add = TRUE)
  payload <- if (row_major) as.double(t(value)) else as.double(value)
  writeBin(payload, handle, size = 8L, endian = "little")
}
write_json <- function(value, path) {
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
}

contract_path <- normalizePath(arg("--contract"), mustWork = TRUE)
contract <- jsonlite::read_json(contract_path, simplifyVector = FALSE)
if (!identical(contract$stage, "R111B") ||
    !(contract$phase %in% c("median_arm_screen", "final_al_readout")) ||
    !identical(contract$region, "BG") ||
    !(contract$arm %in% c("teacher_recent", "recursive_mean", "mixed_equal")) ||
    !identical(contract$family, "al") ||
    isTRUE(contract$test_access_authorized) || isTRUE(contract$joint_model_authorized) ||
    isTRUE(contract$mcmc_authorized)) {
  stop("R111B AL-readout firewall violation", call. = FALSE)
}
if (abs(as.numeric(contract$tau0) - 1e-4) > 1e-15 ||
    (identical(contract$phase, "median_arm_screen") && abs(as.numeric(contract$tau) - 0.5) > 1e-12)) {
  stop("R111B frozen AL/RHS contract changed", call. = FALSE)
}
output_dir <- normalizePath(contract$output_dir, mustWork = FALSE)
terminal_path <- file.path(output_dir, "terminal.json")
if (file.exists(terminal_path)) {
  terminal <- jsonlite::read_json(terminal_path, simplifyVector = FALSE)
  if (identical(terminal$status, "completed_r111b_al_readout") &&
      identical(terminal$task_contract_sha256, contract$task_contract_sha256)) {
    cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(status = 0L)
  }
}

read_block <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  terminal <- jsonlite::read_json(file.path(path, "terminal.json"), simplifyVector = FALSE)
  meta <- jsonlite::read_json(file.path(path, "design.json"), simplifyVector = FALSE)
  if (!identical(terminal$status, "completed_r111b_exposure_design") ||
      !identical(terminal$test_opened, FALSE)) stop("invalid R111B exposure block", call. = FALSE)
  for (record in records(terminal$artifacts)) {
    if (!identical(sha256(file.path(path, record$path)), record$sha256)) {
      stop("changed R111B exposure artifact", call. = FALSE)
    }
  }
  n <- as.integer(meta$n); p <- as.integer(meta$p)
  list(
    teacher = matrix(read_f64(file.path(path, "X_teacher.bin"), n * p), nrow = n, byrow = TRUE),
    recursive = matrix(read_f64(file.path(path, "X_recursive_mean.bin"), n * p), nrow = n, byrow = TRUE),
    y = read_f64(file.path(path, "y.bin"), n), n = n, p = p,
    terminal_sha256 = sha256(file.path(path, "terminal.json")), path = path
  )
}
arm_design <- function(block, arm) {
  if (identical(arm, "teacher_recent")) return(list(X = block$teacher, y = block$y))
  if (identical(arm, "recursive_mean")) return(list(X = block$recursive, y = block$y))
  list(X = rbind(block$teacher, block$recursive), y = c(block$y, block$y))
}

blocks <- lapply(records(contract$training_block_dirs), function(path) read_block(as.character(path)))
if (!length(blocks)) stop("R111B AL fit has no training blocks", call. = FALSE)
p <- blocks[[1L]]$p
if (any(vapply(blocks, function(x) x$p != p, logical(1L)))) stop("R111B block width changed", call. = FALSE)
parts <- lapply(blocks, function(block) arm_design(block, contract$arm))
X <- do.call(rbind, lapply(parts, `[[`, "X"))
y <- unlist(lapply(parts, `[[`, "y"), use.names = FALSE)
if (nrow(X) != length(y) || any(!is.finite(X)) || any(!is.finite(y))) {
  stop("R111B AL training design is invalid", call. = FALSE)
}

for (record in records(contract$adapters)) {
  if (!identical(sha256(record$path), record$sha256)) stop("R111B fit adapter changed", call. = FALSE)
  source(record$path, local = TRUE)
}
runtime_manifest <- jsonlite::read_json(contract$runtime_manifest, simplifyVector = FALSE)
if (!identical(sha256(contract$runtime_manifest), contract$runtime_manifest_sha256) ||
    !identical(runtime_manifest$version, "1.1.1.9005") ||
    !identical(runtime_manifest$test_opened, FALSE)) stop("R111B runtime provenance mismatch", call. = FALSE)
expected_repair <- paste0(
  "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-",
  "plus-structured-plugin-init-plus-coherent-al-latent-init"
)
options(
  pricefm.expected_exdqlm_version = "1.1.1.9005",
  pricefm.expected_exdqlm_repair = expected_repair
)
package <- r75_assert_repair_package(contract$runtime_library)

initializer_policy <- as.character(contract$initializer_policy)
initializer_terminal_sha256 <- NULL
if (identical(contract$phase, "median_arm_screen")) {
  if (!identical(initializer_policy, "neutral_training_only")) {
    stop("R111B screen initializer must be neutral", call. = FALSE)
  }
  sigma_init <- stats::sd(y)
  if (!is.finite(sigma_init) || sigma_init <= 0) sigma_init <- 1
  init <- list(beta = rep(0, p), sigma = sigma_init)
} else {
  if (!identical(initializer_policy, "matching_R103_AL_same_fold_tau")) {
    stop("R111B final initializer policy changed", call. = FALSE)
  }
  initializer_dir <- normalizePath(contract$initializer_dir, mustWork = TRUE)
  initializer_terminal <- jsonlite::read_json(file.path(initializer_dir, "terminal.json"), simplifyVector = FALSE)
  if (!identical(initializer_terminal$status, "completed_recursive_quantile_atom") ||
      !identical(initializer_terminal$family, "al") ||
      abs(as.numeric(initializer_terminal$tau) - as.numeric(contract$tau)) > 1e-12 ||
      !isTRUE(initializer_terminal$numerical_gate_passed) ||
      !identical(initializer_terminal$test_opened, FALSE) ||
      as.integer(initializer_terminal$p) != p) {
    stop("R111B matching R103 initializer is invalid", call. = FALSE)
  }
  beta_init <- read_f64(file.path(initializer_dir, "beta_mean.bin"), p)
  parameters_init <- jsonlite::read_json(file.path(initializer_dir, "parameter_summary.json"), simplifyVector = FALSE)
  init <- list(beta = beta_init, sigma = as.numeric(parameters_init$sigma))
  initializer_terminal_sha256 <- sha256(file.path(initializer_dir, "terminal.json"))
}

rhs <- lapply(contract$rhs, function(value) if (length(value) == 1L) unlist(value) else value)
qcfg <- lapply(contract$qdesn_vb, function(value) if (length(value) == 1L) unlist(value) else value)
prior_sigma <- qcfg$prior_sigma %||% list(a = 1, b = 1)
fit_once <- function(max_iter) {
  fit_qcfg <- qcfg
  fit_qcfg$max_iter <- as.integer(max_iter)
  control <- r67_vb_control(NULL, fit_qcfg, "al", NULL)
  set.seed(as.integer(contract$seed))
  do.call(getExportedValue("exdqlm", "exalStaticLDVB"), list(
    y = y, X = X, p0 = as.numeric(contract$tau),
    beta_prior = "rhs_ns", beta_prior_controls = r72_rhs_controls(rhs),
    a_sigma = as.numeric(prior_sigma$a %||% 1), b_sigma = as.numeric(prior_sigma$b %||% 1),
    init = init, dqlm.ind = TRUE, n.samp = as.integer(qcfg$n_samp %||% 200L),
    vb_control = control, verbose = FALSE
  ))
}
configured_max <- as.integer(qcfg$max_iter %||% 500L)
started <- proc.time()[["elapsed"]]
fit <- fit_once(configured_max)
effective_max <- configured_max
if (!isTRUE(fit$converged) && configured_max < 750L) {
  effective_max <- 750L
  fit <- fit_once(effective_max)
}
elapsed <- proc.time()[["elapsed"]] - started
beta <- as.numeric(fit$qbeta$m)
covariance <- as.matrix(fit$qbeta$V)
sigma <- as.numeric(fit$qsig$E_sigma %||% fit$qsiggam$sigma_mean %||% NA_real_)[1L]
trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
finite <- length(beta) == p && all(is.finite(beta)) && all(dim(covariance) == c(p, p)) &&
  all(is.finite(covariance)) && all(diag(covariance) > 0) && is.finite(sigma) && sigma > 0
if (!isTRUE(fit$converged) || !finite) stop("R111B AL readout failed numerical gate", call. = FALSE)

screen_metric <- NULL
if (identical(contract$phase, "median_arm_screen")) {
  eval_block <- read_block(as.character(contract$evaluation_block_dir))
  if (eval_block$p != p) stop("R111B screen evaluation width changed", call. = FALSE)
  prediction <- as.numeric(eval_block$recursive %*% beta)
  error <- eval_block$y - prediction
  loss <- pmax(as.numeric(contract$tau) * error, (as.numeric(contract$tau) - 1) * error)
  screen_metric <- data.frame(
    task_id = contract$task_id, arm = contract$arm,
    holdout_inner_fold = as.integer(contract$holdout_inner_fold), tau = as.numeric(contract$tau),
    n_fit_rows = nrow(X), n_eval_rows = length(error), AQL_scaled = mean(loss),
    MAE_scaled = mean(abs(error)), converged = TRUE,
    selection_split = "fold1_training_crossfit_holdout", test_opened = FALSE
  )
}

parent <- dirname(output_dir)
dir.create(parent, recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output_dir), ".tmp."), tmpdir = parent)
dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
write_f64(file.path(temporary, "beta_mean.bin"), beta)
write_f64(file.path(temporary, "beta_cov.bin"), covariance, row_major = TRUE)
if (nrow(trace)) utils::write.csv(trace, file.path(temporary, "vb_trace.csv"), row.names = FALSE)
if (!is.null(screen_metric)) utils::write.csv(screen_metric, file.path(temporary, "metric_summary.csv"), row.names = FALSE)
write_json(list(
  family = "al", tau = as.numeric(contract$tau), tau0 = as.numeric(contract$tau0),
  arm = contract$arm, sigma = sigma, n = nrow(X), p = p,
  train_seconds = as.numeric(elapsed), iterations = as.integer(fit$iter %||% nrow(trace)),
  configured_max_iter = configured_max, effective_max_iter = effective_max,
  formal_converged = TRUE, init_source = initializer_policy,
  initialization_only = TRUE, prior_center_from_initializer = FALSE
), file.path(temporary, "parameter_summary.json"))
names <- list.files(temporary, full.names = FALSE)
artifacts <- lapply(names, function(name) list(
  path = name, bytes = file.info(file.path(temporary, name))$size,
  sha256 = sha256(file.path(temporary, name))
))
terminal <- list(
  stage = "R111B", status = "completed_r111b_al_readout", task_id = contract$task_id,
  phase = contract$phase, task_contract_sha256 = contract$task_contract_sha256,
  posterior_target_sha256 = contract$posterior_target_sha256,
  region = "BG", outer_fold = as.integer(contract$outer_fold), arm = contract$arm,
  family = "al", tau = as.numeric(contract$tau), tau0 = as.numeric(contract$tau0),
  n = nrow(X), p = p, converged = TRUE,
  initialization_only = TRUE, prior_center_from_initializer = FALSE,
  initializer_policy = initializer_policy,
  initializer_terminal_sha256 = initializer_terminal_sha256,
  training_block_terminal_sha256 = lapply(blocks, `[[`, "terminal_sha256"),
  package = package, artifacts = artifacts, test_opened = FALSE,
  test_access_authorized = FALSE, registry_mutated = FALSE, article_mutated = FALSE,
  joint_model_fitted = FALSE, mcmc_fitted = FALSE
)
write_json(terminal, file.path(temporary, "terminal.json"))
if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output_dir)) stop("failed to install R111B AL output", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
