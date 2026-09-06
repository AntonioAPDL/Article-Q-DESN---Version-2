#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}
`%||%` <- function(x, y) if (is.null(x)) y else x
task_path <- get_arg("--task-config")
code_root <- get_arg("--code-root")
if (is.null(task_path) || is.null(code_root)) stop("--task-config and --code-root are required.", call. = FALSE)
task_path <- normalizePath(task_path, mustWork = TRUE)
code_root <- normalizePath(code_root, mustWork = TRUE)
task <- jsonlite::read_json(task_path, simplifyVector = TRUE)
output <- normalizePath(task$output_dir, mustWork = FALSE)
dir.create(output, recursive = TRUE, showWarnings = FALSE)

atomic_json <- function(value, path) {
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  cat(jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n", file = tmp)
  if (!file.rename(tmp, path)) stop("Atomic JSON rename failed.", call. = FALSE)
}
atomic_csv <- function(value, path) {
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  utils::write.csv(value, tmp, row.names = FALSE)
  if (!file.rename(tmp, path)) stop("Atomic CSV rename failed.", call. = FALSE)
}
sha256 <- function(path) {
  text <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(text[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
pinball <- function(y, prediction, tau) mean(pmax(tau * (y - prediction), (tau - 1) * (y - prediction)))

atomic_json(list(status = "started", task_id = task$task_id, pid = Sys.getpid(), test_loaded = FALSE),
            file.path(output, "started.json"))

run_probe <- function() {
  blocked <- c("test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized",
               "joint_model_authorized", "mcmc_authorized")
  if (!identical(task$stage, "R75_PROBE") || !isTRUE(task$probe_only) ||
      any(vapply(blocked, function(name) isTRUE(task[[name]]), logical(1L)))) {
    stop("R75 probe firewall violation.", call. = FALSE)
  }
  manifest <- jsonlite::read_json(task$runtime_manifest, simplifyVector = TRUE)
  if (!identical(manifest$status, "installed_pricefm_local_large_n_gig_repair") ||
      !identical(manifest$base_tarball_sha256,
                 "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e")) {
    stop("R75 runtime manifest is invalid.", call. = FALSE)
  }
  if (!identical(sha256(task$runtime_manifest), task$runtime_manifest_sha256) ||
      !identical(sha256(task$al_beta_path), task$al_beta_sha256) ||
      !identical(sha256(task$al_parameter_path), task$al_parameter_sha256)) {
    stop("R75 source hash changed.", call. = FALSE)
  }
  source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"), local = TRUE)
  source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R"), local = TRUE)
  source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r75_large_n_gig_adapter.R"), local = TRUE)
  package <- r75_assert_repair_package(task$r_library)
  adapter <- normalizePath(task$adapter_dir, mustWork = TRUE)
  forbidden <- file.path(adapter, c("X_test.csv", "y_test.csv", "rows_test.csv"))
  if (any(file.exists(forbidden))) stop("R75 adapter test firewall violation.", call. = FALSE)
  X_all <- read_matrix(file.path(adapter, "X_train.csv"))
  y_all <- read_vector(file.path(adapter, "y_train.csv"))
  count <- min(as.integer(task$probe_rows), nrow(X_all))
  index <- unique(as.integer(round(seq(1, nrow(X_all), length.out = count))))
  X <- X_all[index, , drop = FALSE]
  y <- y_all[index]
  rm(X_all, y_all); gc(verbose = FALSE)
  beta_frame <- utils::read.csv(task$al_beta_path)
  beta <- as.numeric(beta_frame$beta_mean)
  parameter <- utils::read.csv(task$al_parameter_path)
  sigma <- as.numeric(parameter$sigma[[1L]])
  if (length(beta) != ncol(X) || any(!is.finite(beta)) || !is.finite(sigma) || sigma <= 0) {
    stop("R75 AL warm start is invalid.", call. = FALSE)
  }
  rhs <- list(
    tau0 = task$rhs_tau0, init_tau = task$rhs_init_tau,
    freeze_tau_iters = task$rhs_freeze_tau_iters,
    freeze_tau_warmup_iters = task$rhs_freeze_tau_warmup_iters,
    shrink_intercept = FALSE
  )
  qcfg <- list(
    max_iter = task$max_iter, tol = task$tol, n_samp = task$n_samp,
    n_samp_xi = task$n_samp_xi, verbose = FALSE,
    prior_sigma = list(a = 1, b = 1), prior_gamma = list(mu0 = 0, s20 = 10)
  )
  profile <- list(
    factorization = "structured", structured_grid_size = task$structured_grid_size,
    structured_span_sd = task$structured_span_sd,
    freeze_warmup_iters = task$sigmagam_freeze_warmup_iters,
    force_after_warmup = TRUE, postwarmup_damping = task$postwarmup_damping,
    postwarmup_damping_iters = task$postwarmup_damping_iters,
    min_postwarmup_updates = task$min_postwarmup_updates
  )
  fit <- r75_fit_quantile(
    task$r_library, X, y, task$tau, rhs, qcfg, profile,
    init = list(beta = beta, sigma = sigma, gamma = 0), seed = task$seed
  )
  exal_beta <- as.numeric(fit$qbeta$m)
  exal_sigma <- as.numeric(fit$qsiggam$sigma_mean)
  exal_gamma <- as.numeric(fit$qsiggam$gamma_mean)
  trace <- as.data.frame(fit$diagnostics$vb_trace)
  spd <- as.data.frame(fit$diagnostics$spd_factorization %||% data.frame())
  grid <- as.data.frame(fit$qsiggam$structured$grid %||% data.frame())
  updates <- as.integer(fit$diagnostics$ld_block$sigmagam$update_count %||% 0L)
  helper <- get(".pricefm_log_bessel_k", envir = loadNamespace("exdqlm"), inherits = FALSE)
  backend_probe <- helper(sqrt((2 * nrow(X)) * (5 * nrow(X))), -(1 + 1.5 * nrow(X)))
  al_prediction <- as.numeric(X %*% beta)
  exal_prediction <- as.numeric(X %*% exal_beta)
  required_trace <- intersect(
    c("sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"),
    names(trace)
  )
  values <- c(exal_beta, exal_sigma, exal_gamma, unlist(trace[required_trace]))
  if (any(!is.finite(values))) stop("R75 probe produced non-finite outputs.", call. = FALSE)
  probe <- data.frame(
    task_id = task$task_id, case_id = task$case_id, region = task$region,
    fold = task$fold, tau = task$tau, n_probe = nrow(X), p = ncol(X),
    iter = fit$iter, converged = isTRUE(fit$converged), structured_updates = updates,
    al_sigma = sigma, exal_sigma = exal_sigma, exal_gamma = exal_gamma,
    al_beta_l2 = sqrt(sum(beta^2)), exal_beta_l2 = sqrt(sum(exal_beta^2)),
    beta_l2_ratio = sqrt(sum(exal_beta^2)) / max(sqrt(sum(beta^2)), 1e-12),
    sigma_ratio = exal_sigma / sigma,
    al_train_probe_AQL = pinball(y, al_prediction, task$tau),
    exal_train_probe_AQL = pinball(y, exal_prediction, task$tau),
    train_AQL_ratio = pinball(y, exal_prediction, task$tau) / max(pinball(y, al_prediction, task$tau), 1e-12),
    delta_s_nonzero = any(trace$delta_s > 0),
    large_n_bessel_backend = as.character(attr(backend_probe, "backend")),
    elapsed_seconds = as.numeric(attr(fit, "r75_elapsed_seconds")),
    test_loaded = FALSE, binary_model_artifact_written = FALSE,
    stringsAsFactors = FALSE
  )
  atomic_csv(probe, file.path(output, "probe_summary.csv"))
  atomic_csv(trace, file.path(output, "vb_trace.csv"))
  atomic_csv(spd, file.path(output, "spd_factorization_trace.csv"))
  atomic_csv(grid, file.path(output, "structured_grid.csv"))
  files <- c("probe_summary.csv", "vb_trace.csv", "spd_factorization_trace.csv", "structured_grid.csv")
  hashes <- setNames(lapply(file.path(output, files), sha256), files)
  atomic_json(list(
    status = "completed", task_id = task$task_id, artifact_sha256 = hashes,
    package = package, test_loaded = FALSE, binary_model_artifacts_written = FALSE,
    registry_mutated = FALSE, article_mutated = FALSE
  ), file.path(output, "terminal.json"))
}

tryCatch(run_probe(), error = function(error) {
  atomic_json(list(status = "failed", task_id = task$task_id,
                   error_message = conditionMessage(error), test_loaded = FALSE),
              file.path(output, "terminal.json"))
  stop(error)
})
