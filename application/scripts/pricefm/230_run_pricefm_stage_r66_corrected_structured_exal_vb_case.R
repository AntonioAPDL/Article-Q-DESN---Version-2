#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(yaml))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}

find_repo_root <- function() {
  current <- normalizePath(getwd(), mustWork = TRUE)
  candidates <- c(
    current,
    normalizePath(file.path(current, ".."), mustWork = FALSE),
    normalizePath(file.path(current, "..", ".."), mustWork = FALSE),
    normalizePath(file.path(current, "..", "..", ".."), mustWork = FALSE)
  )
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "application", "config", "pricefm_data_pipeline.yaml"))) {
      return(candidate)
    }
  }
  stop("Could not locate the Article-Q-DESN repository root.", call. = FALSE)
}

repo_root <- find_repo_root()
source(file.path(repo_root, "application/scripts/pricefm/pricefm_stage_r66_vb_helpers.R"), local = TRUE)

config_path <- get_arg("--case-config")
force <- tolower(get_arg("--force", "false")) %in% c("1", "true", "yes", "y")
preflight_only <- tolower(get_arg("--preflight-only", "false")) %in% c("1", "true", "yes", "y")
if (is.null(config_path)) stop("--case-config is required.", call. = FALSE)
config_path <- normalizePath(config_path, mustWork = TRUE)
payload <- yaml::read_yaml(config_path)
cfg <- payload$pricefm_desn_smoke
r66 <- payload$pricefm_stage_r66
if (is.null(cfg) || is.null(r66)) stop("Config must contain PriceFM smoke and R66 blocks.", call. = FALSE)

if (!identical(as.character(cfg$splits), c("train", "val"))) {
  stop("R66 permits exactly train and validation splits.", call. = FALSE)
}
quantiles <- as.numeric(unlist(cfg$quantiles, use.names = FALSE))
expected_quantiles <- c(0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
if (!identical(quantiles, expected_quantiles)) {
  stop("R66 requires the ordered seven-quantile PriceFM grid.", call. = FALSE)
}
if (!identical(as.character(cfg$qdesn_vb$likelihoods), c("al", "exal"))) {
  stop("R66 requires AL parity and structured exAL.", call. = FALSE)
}

package_path <- normalizePath(cfg$package_path, mustWork = TRUE)
package_head <- system2("git", c("-C", package_path, "rev-parse", "HEAD"), stdout = TRUE)
if (!identical(as.character(package_head), as.character(r66$package$commit))) {
  stop("Pinned package commit mismatch: ", package_head, call. = FALSE)
}
if (is.null(r66$code$source_sha256) || !length(r66$code$source_sha256)) {
  stop("R66 runtime source hashes are missing.", call. = FALSE)
}
for (relative_path in names(r66$code$source_sha256)) {
  observed <- r66_sha256(file.path(repo_root, relative_path))
  expected <- as.character(r66$code$source_sha256[[relative_path]])
  if (!identical(observed, expected)) {
    stop("Pinned R66 runtime source hash mismatch for ", relative_path, call. = FALSE)
  }
}
for (relative_path in names(r66$package$source_sha256)) {
  observed <- r66_sha256(file.path(package_path, relative_path))
  expected <- as.character(r66$package$source_sha256[[relative_path]])
  if (!identical(observed, expected)) {
    stop("Pinned package source hash mismatch for ", relative_path, call. = FALSE)
  }
}
package_library <- normalizePath(r66$package$library, mustWork = TRUE)
install_manifest_path <- file.path(package_library, "pricefm_r66_install_manifest.json")
if (!file.exists(install_manifest_path)) stop("R66 package install manifest is missing.", call. = FALSE)
install_manifest <- jsonlite::read_json(install_manifest_path, simplifyVector = TRUE)
if (!identical(as.character(install_manifest$source_commit), as.character(package_head))) {
  stop("R66 installed package source commit mismatch.", call. = FALSE)
}
for (relative_path in names(r66$package$source_sha256)) {
  installed_expected <- as.character(install_manifest$source_sha256[[relative_path]])
  configured_expected <- as.character(r66$package$source_sha256[[relative_path]])
  if (!identical(installed_expected, configured_expected)) {
    stop("R66 installed package source hash mismatch for ", relative_path, call. = FALSE)
  }
}
suppressPackageStartupMessages(library("exdqlm", character.only = TRUE, lib.loc = package_library))
if (!identical(as.character(utils::packageVersion("exdqlm", lib.loc = package_library)), "1.1.1")) {
  stop("R66 installed package version is not 1.1.1.", call. = FALSE)
}
source_r65_config <- normalizePath(r66$source_r65_config, mustWork = TRUE)
if (!identical(r66_sha256(source_r65_config), as.character(r66$source_r65_config_sha256))) {
  stop("R66 source R65 config hash mismatch.", call. = FALSE)
}
if (isTRUE(r66$reuse$r65_exal_reuse_authorized)) {
  stop("R66 may not reuse any R65 exAL fit.", call. = FALSE)
}

adapter_dir <- normalizePath(cfg$adapter$output_dir, mustWork = FALSE)
if (!is.null(r66$reuse$adapter)) {
  if (!identical(normalizePath(r66$reuse$adapter$path, mustWork = TRUE), adapter_dir)) {
    stop("R66 adapter reuse path differs from the configured adapter path.", call. = FALSE)
  }
  for (name in names(r66$reuse$adapter$source_sha256)) {
    observed <- r66_sha256(file.path(adapter_dir, name))
    expected <- as.character(r66$reuse$adapter$source_sha256[[name]])
    if (!identical(observed, expected)) {
      stop("R66 reused adapter hash mismatch for ", name, call. = FALSE)
    }
  }
}
normal_reuse <- r66_external_fit_contract(
  r66$reuse$normal_anchor,
  list(
    config_sha256 = r66$source_r65_config_sha256,
    package_head = r66$reuse$source_package_commit,
    case_id = r66$case_id,
    role = "shared_normal_rhs_anchor"
  )
)
al_reuse_contracts <- lapply(seq_along(quantiles), function(index) {
  tau <- quantiles[[index]]
  contract <- r66$reuse$al_by_tau[[r66_tau_key(tau)]]
  r66_external_fit_contract(
    contract,
    list(
      config_sha256 = r66$source_r65_config_sha256,
      package_head = r66$reuse$source_package_commit,
      case_id = r66$case_id,
      tau = r66_tau_key(tau),
      method_id = contract$source_method_id %||% "qdesn_al_rhs_ns_exact_chunked_r65_parity"
    )
  )
})
names(al_reuse_contracts) <- vapply(quantiles, r66_tau_key, character(1))

if (isTRUE(preflight_only)) {
  cat(jsonlite::toJSON(list(
    status = "r66_case_preflight_passed",
    case_id = as.character(r66$case_id),
    package_head = package_head,
    package_library = package_library,
    configured_splits = as.character(cfg$splits),
    quantiles = quantiles,
    adapter_reused = !is.null(r66$reuse$adapter),
    normal_anchor_reused = !is.null(normal_reuse),
    al_components_reused = sum(!vapply(al_reuse_contracts, is.null, logical(1))),
    r65_exal_components_reused = 0L,
    test_loaded = FALSE
  ), auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(save = "no", status = 0L)
}

config_sha256 <- r66_sha256(config_path)
out_dir <- normalizePath(cfg$run$output_dir, mustWork = FALSE)
if (isTRUE(force) && dir.exists(out_dir)) unlink(out_dir, recursive = TRUE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(file.path(adapter_dir, "adapter_manifest.json"))) {
  python_bin <- path.expand(as.character(cfg$python_bin))
  if (!file.exists(python_bin)) stop("R66 Python environment is missing: ", python_bin, call. = FALSE)
  adapter_script <- file.path(repo_root, "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py")
  status <- system2(
    python_bin,
    c(adapter_script, "--smoke-config", config_path, "--force", "true")
  )
  if (!identical(status, 0L)) stop("R66 adapter build failed.", call. = FALSE)
}

for (forbidden in c("X_test.csv", "y_test.csv", "rows_test.csv")) {
  if (file.exists(file.path(adapter_dir, forbidden))) {
    stop("Test firewall violation in adapter: ", forbidden, call. = FALSE)
  }
}

read_matrix <- function(name) {
  as.matrix(utils::read.csv(file.path(adapter_dir, name), header = FALSE, check.names = FALSE))
}
read_vector <- function(name) as.numeric(read_matrix(name)[, 1L])
X_train <- read_matrix("X_train.csv")
y_train <- read_vector("y_train.csv")
X_val <- read_matrix("X_val.csv")
rows_val <- utils::read.csv(file.path(adapter_dir, "rows_val.csv"), stringsAsFactors = FALSE)
if (nrow(X_train) != length(y_train) || nrow(X_val) != nrow(rows_val) || ncol(X_train) != ncol(X_val)) {
  stop("R66 adapter dimensions are inconsistent.", call. = FALSE)
}

rhs_cfg <- cfg$rhs_ns
rhs <- list(
  tau0 = as.numeric(rhs_cfg$tau0),
  shrink_intercept = isTRUE(rhs_cfg$shrink_intercept %||% FALSE),
  freeze_tau_iters = as.integer(rhs_cfg$freeze_tau_iters %||% 0L),
  freeze_tau_warmup_iters = as.integer(rhs_cfg$freeze_tau_warmup_iters %||% 0L)
)
profile <- r66$structured_sigmagam
method_al <- as.character(r66$method_ids$al)
method_exal <- as.character(r66$method_ids$exal)
base_seed <- as.integer(cfg$run$seed)

normal_dir <- file.path(out_dir, "normal_anchor")
normal_fit_path <- file.path(normal_dir, "normal_rhs_anchor.rds")
normal_status_path <- file.path(normal_dir, "normal_rhs_anchor.json")
normal_expected <- list(
  config_sha256 = config_sha256,
  package_head = package_head,
  case_id = as.character(r66$case_id),
  role = "shared_normal_rhs_anchor"
)
normal_source <- ""
if (r66_status_is_valid(normal_status_path, normal_fit_path, normal_expected)) {
  normal_fit <- readRDS(normal_fit_path)
  normal_source <- "r66_resume_hash_valid_normal_anchor"
  normal_hash <- r66_sha256(normal_fit_path)
  normal_effective_path <- normalizePath(normal_fit_path, mustWork = TRUE)
} else if (!is.null(normal_reuse)) {
  normal_fit <- readRDS(normal_reuse$fit_path)
  normal_source <- "r65_hash_valid_normal_anchor"
  normal_hash <- normal_reuse$fit_sha256
  normal_effective_path <- normal_reuse$fit_path
  r66_atomic_write_json(list(
    role = "shared_normal_rhs_anchor",
    reuse_source = "R65",
    fit_path = normal_reuse$fit_path,
    status_path = normal_reuse$status_path,
    fit_sha256 = normal_reuse$fit_sha256,
    source_config_sha256 = r66$source_r65_config_sha256,
    source_package_head = r66$reuse$source_package_commit
  ), file.path(normal_dir, "normal_rhs_anchor_reference.json"))
} else {
  if ((file.exists(normal_status_path) || file.exists(normal_fit_path)) && !isTRUE(force)) {
    stop("Existing normal anchor failed its hash contract.", call. = FALSE)
  }
  set.seed(base_seed)
  started <- proc.time()[["elapsed"]]
  normal_fit <- exdqlm::normal_desn_fit(
    X_train,
    y_train,
    beta_prior_type = "rhs_ns",
    omega_prior = cfg$normal$omega_prior,
    rhs = rhs,
    control = cfg$normal$vb_control
  )
  attr(normal_fit, "r66_elapsed_seconds") <- as.numeric(proc.time()[["elapsed"]] - started)
  r66_atomic_save_rds(normal_fit, normal_fit_path)
  r66_atomic_write_json(c(normal_expected, list(
    fit_sha256 = r66_sha256(normal_fit_path),
    converged = isTRUE(normal_fit$converged %||% TRUE),
    elapsed_seconds = as.numeric(attr(normal_fit, "r66_elapsed_seconds"))
  )), normal_status_path)
  normal_source <- "r66_fresh_normal_anchor"
  normal_hash <- r66_sha256(normal_fit_path)
  normal_effective_path <- normalizePath(normal_fit_path, mustWork = TRUE)
}

component_rows <- list()
for (index in seq_along(quantiles)) {
  tau <- quantiles[[index]]
  component_dir <- file.path(out_dir, "components", paste0("tau=", r66_tau_slug(tau)))
  dir.create(component_dir, recursive = TRUE, showWarnings = FALSE)

  al_fit_path <- file.path(component_dir, "al_fit.rds")
  al_status_path <- file.path(component_dir, "al_status.json")
  al_expected <- list(
    config_sha256 = config_sha256,
    package_head = package_head,
    case_id = as.character(r66$case_id),
    tau = r66_tau_key(tau),
    method_id = method_al,
    init_sha256 = normal_hash
  )
  al_reuse <- al_reuse_contracts[[r66_tau_key(tau)]]
  al_reused_from_r65 <- FALSE
  al_init_components <- c("beta", "beta_state", "sigma")
  if (r66_status_is_valid(al_status_path, al_fit_path, al_expected)) {
    al_fit <- readRDS(al_fit_path)
    al_source <- "r66_resume_hash_valid_al"
    al_effective_path <- normalizePath(al_fit_path, mustWork = TRUE)
    al_hash <- r66_sha256(al_fit_path)
  } else if (!is.null(al_reuse)) {
    al_fit <- readRDS(al_reuse$fit_path)
    al_source <- "r65_hash_valid_same_tau_al"
    al_effective_path <- al_reuse$fit_path
    al_hash <- al_reuse$fit_sha256
    al_reused_from_r65 <- TRUE
    al_init_components <- "full_fit_reuse"
    r66_atomic_write_json(list(
      role = "same_tau_al_parity_and_warm_start",
      tau = r66_tau_key(tau),
      reuse_source = "R65",
      fit_path = al_reuse$fit_path,
      status_path = al_reuse$status_path,
      fit_sha256 = al_reuse$fit_sha256,
      source_config_sha256 = r66$source_r65_config_sha256,
      source_package_head = r66$reuse$source_package_commit
    ), file.path(component_dir, "al_fit_reference.json"))
  } else {
    if ((file.exists(al_status_path) || file.exists(al_fit_path)) && !isTRUE(force)) {
      stop("Existing AL component failed its hash contract at tau=", tau, call. = FALSE)
    }
    al_init <- r66_make_init(normal_fit, ncol(X_train), gamma_zero = FALSE)
    al_fit <- r66_fit_quantile(
      X_train, y_train, tau, "al", rhs, cfg$qdesn_vb, profile,
      al_init$init, base_seed + index * 100L + 1L
    )
    r66_atomic_save_rds(al_fit, al_fit_path)
    r66_atomic_write_json(c(al_expected, list(
      fit_sha256 = r66_sha256(al_fit_path),
      converged = isTRUE(al_fit$converged),
      iter = as.integer(al_fit$iter %||% NA_integer_),
      fit_state = if (isTRUE(al_fit$converged)) "completed_converged" else "terminal_nonconverged"
    )), al_status_path)
    al_source <- normal_source
    al_effective_path <- normalizePath(al_fit_path, mustWork = TRUE)
    al_hash <- r66_sha256(al_fit_path)
    al_init_components <- al_init$components
  }

  r66_atomic_write_csv(
    r66_prediction_frame(al_fit, X_val, rows_val, method_al, tau),
    file.path(component_dir, "al_predictions_scaled.csv")
  )
  r66_atomic_write_csv(
    r66_method_row(al_fit, method_al, "al", tau, nrow(X_train), ncol(X_train),
                    al_source, if (isTRUE(al_reused_from_r65)) al_hash else normal_hash, package_head),
    file.path(component_dir, "al_method_summary.csv")
  )
  r66_atomic_write_csv(
    r66_warm_row(al_fit, method_al, "al", tau, al_source,
                  al_init_components, if (isTRUE(al_reused_from_r65)) al_hash else normal_hash),
    file.path(component_dir, "al_warm_start.csv")
  )
  r66_atomic_write_csv(
    r66_parameter_row(al_fit, method_al, "al", tau),
    file.path(component_dir, "al_parameter_summary.csv")
  )
  r66_atomic_write_csv(
    r66_trace_frame(al_fit, method_al, "al", tau),
    file.path(component_dir, "al_trace.csv")
  )

  for (required in c(
    "al_predictions_scaled.csv", "al_method_summary.csv", "al_warm_start.csv",
    "al_parameter_summary.csv", "al_trace.csv"
  )) {
    if (!file.exists(file.path(component_dir, required))) {
      stop("Incomplete AL component artifact: ", required, call. = FALSE)
    }
  }

  exal_fit_path <- file.path(component_dir, "exal_fit.rds")
  exal_status_path <- file.path(component_dir, "exal_status.json")
  exal_expected <- list(
    config_sha256 = config_sha256,
    package_head = package_head,
    case_id = as.character(r66$case_id),
    tau = r66_tau_key(tau),
    method_id = method_exal,
    init_sha256 = al_hash
  )
  if (r66_status_is_valid(exal_status_path, exal_fit_path, exal_expected)) {
    exal_fit <- readRDS(exal_fit_path)
  } else {
    if ((file.exists(exal_status_path) || file.exists(exal_fit_path)) && !isTRUE(force)) {
      stop("Existing exAL component failed its hash contract at tau=", tau, call. = FALSE)
    }
    exal_init <- r66_make_init(al_fit, ncol(X_train), gamma_zero = TRUE)
    exal_fit <- r66_fit_quantile(
      X_train, y_train, tau, "exal", rhs, cfg$qdesn_vb, profile,
      exal_init$init, base_seed + index * 100L + 2L
    )
    telemetry <- r66_sigmagam_telemetry(exal_fit)
    telemetry_pass <- r66_sigmagam_telemetry_pass(
      exal_fit,
      minimum_exact_commits = as.integer(profile$minimum_exact_commits),
      minimum_boundary_margin = as.numeric(profile$minimum_gamma_relative_boundary_margin)
    )
    r66_atomic_save_rds(exal_fit, exal_fit_path)
    r66_atomic_write_csv(
      r66_prediction_frame(exal_fit, X_val, rows_val, method_exal, tau),
      file.path(component_dir, "exal_predictions_scaled.csv")
    )
    r66_atomic_write_csv(
      r66_method_row(exal_fit, method_exal, "exal", tau, nrow(X_train), ncol(X_train),
                      paste0("same_tau_al_", r66_tau_key(tau)), al_hash, package_head),
      file.path(component_dir, "exal_method_summary.csv")
    )
    r66_atomic_write_csv(
      r66_warm_row(exal_fit, method_exal, "exal", tau,
                    paste0("same_tau_al_", r66_tau_key(tau)), exal_init$components, al_hash),
      file.path(component_dir, "exal_warm_start.csv")
    )
    r66_atomic_write_csv(
      r66_parameter_row(exal_fit, method_exal, "exal", tau),
      file.path(component_dir, "exal_parameter_summary.csv")
    )
    r66_atomic_write_csv(
      r66_trace_frame(exal_fit, method_exal, "exal", tau),
      file.path(component_dir, "exal_trace.csv")
    )
    r66_atomic_write_json(c(exal_expected, list(
      fit_sha256 = r66_sha256(exal_fit_path),
      converged = isTRUE(exal_fit$converged),
      iter = as.integer(exal_fit$iter %||% NA_integer_),
      structured_telemetry_pass = telemetry_pass,
      exact_conditional_gig_moment_pass = identical(telemetry$moment_source, "conditional_gig_exact"),
      continuation_start_pass = identical(telemetry$optimizer_start_source, "eta_start") &&
        !isTRUE(telemetry$optimizer_used_fallback),
      exact_commit_count = telemetry$exact_commit_count,
      gamma_relative_boundary_margin = telemetry$gamma_relative_boundary_margin,
      sigmagam = telemetry,
      fit_state = if (isTRUE(exal_fit$converged) && telemetry_pass) {
        "completed_converged_structured"
      } else {
        "terminal_nonconverged_or_telemetry_blocked"
      }
    )), exal_status_path)
  }

  for (required in c(
    "exal_predictions_scaled.csv", "exal_method_summary.csv", "exal_warm_start.csv",
    "exal_parameter_summary.csv", "exal_trace.csv"
  )) {
    if (!file.exists(file.path(component_dir, required))) {
      stop("Incomplete exAL component artifact: ", required, call. = FALSE)
    }
  }

  exal_status <- jsonlite::read_json(exal_status_path, simplifyVector = TRUE)
  telemetry <- exal_status$sigmagam
  component_status <- list(
    case_id = as.character(r66$case_id),
    region = as.character(cfg$region),
    fold = as.integer(cfg$fold),
    tau = as.numeric(tau),
    al_converged = isTRUE(al_fit$converged),
    al_reused_from_r65 = isTRUE(al_reused_from_r65),
    al_fit_path = al_effective_path,
    al_fit_sha256 = al_hash,
    exal_converged = isTRUE(exal_status$converged),
    structured_telemetry_pass = isTRUE(exal_status$structured_telemetry_pass),
    exact_conditional_gig_moment_pass = isTRUE(exal_status$exact_conditional_gig_moment_pass),
    continuation_start_pass = isTRUE(exal_status$continuation_start_pass),
    exact_commit_count = as.integer(exal_status$exact_commit_count %||% 0L),
    moment_source = as.character(telemetry$moment_source %||% NA_character_),
    optimizer_start_source = as.character(telemetry$optimizer_start_source %||% NA_character_),
    optimizer_used_fallback = isTRUE(telemetry$optimizer_used_fallback),
    gamma = as.numeric(telemetry$gamma %||% NA_real_),
    sigma = as.numeric(telemetry$sigma %||% NA_real_),
    gamma_relative_boundary_margin = as.numeric(exal_status$gamma_relative_boundary_margin %||% NA_real_),
    exal_fit_path = normalizePath(exal_fit_path, mustWork = TRUE),
    exal_fit_sha256 = r66_sha256(exal_fit_path),
    terminal = TRUE,
    selection_eligible = isTRUE(al_fit$converged) && isTRUE(exal_status$converged) &&
      isTRUE(exal_status$structured_telemetry_pass)
  )
  r66_atomic_write_json(component_status, file.path(component_dir, "component_terminal.json"))
  component_rows[[length(component_rows) + 1L]] <- component_status
}

component_dirs <- file.path(out_dir, "components", paste0("tau=", vapply(quantiles, r66_tau_slug, character(1))))
read_many <- function(names) {
  do.call(rbind, unlist(lapply(seq_along(component_dirs), function(i) {
    lapply(names, function(name) utils::read.csv(file.path(component_dirs[[i]], name), stringsAsFactors = FALSE))
  }), recursive = FALSE))
}

r66_atomic_write_csv(
  read_many(c("al_predictions_scaled.csv", "exal_predictions_scaled.csv")),
  file.path(out_dir, "model_predictions_scaled.csv")
)
r66_atomic_write_csv(
  read_many(c("al_method_summary.csv", "exal_method_summary.csv")),
  file.path(out_dir, "model_method_summary.csv")
)
r66_atomic_write_csv(
  read_many(c("al_warm_start.csv", "exal_warm_start.csv")),
  file.path(out_dir, "warm_start_diagnostics.csv")
)
r66_atomic_write_csv(
  read_many(c("al_parameter_summary.csv", "exal_parameter_summary.csv")),
  file.path(out_dir, "model_parameter_summary.csv")
)
r66_atomic_write_csv(
  read_many(c("al_trace.csv", "exal_trace.csv")),
  file.path(out_dir, "model_trace_summary.csv")
)

component_frame <- do.call(rbind, lapply(component_rows, function(row) {
  as.data.frame(row, stringsAsFactors = FALSE)
}))
r66_atomic_write_csv(component_frame, file.path(out_dir, "r66_component_status.csv"))
r66_atomic_write_csv(
  component_frame[, c(
    "case_id", "region", "fold", "tau", "al_reused_from_r65", "al_fit_path",
    "al_fit_sha256", "exal_fit_path", "exal_fit_sha256"
  )],
  file.path(out_dir, "checkpoint_provenance.csv")
)
r66_atomic_write_json(list(
  status = if (all(component_frame$selection_eligible)) {
    "completed_all_components_eligible"
  } else {
    "completed_with_quarantined_components"
  },
  case_id = as.character(r66$case_id),
  region = as.character(cfg$region),
  fold = as.integer(cfg$fold),
  quantiles = quantiles,
  terminal_components = nrow(component_frame),
  eligible_components = sum(component_frame$selection_eligible),
  reused_r65_al_components = sum(component_frame$al_reused_from_r65),
  corrected_exal_components = nrow(component_frame),
  test_loaded = FALSE,
  registry_mutation_authorized = FALSE,
  article_mutation_authorized = FALSE
), file.path(out_dir, "r66_case_fit_summary.json"))
r66_atomic_write_json(list(
  stage = "R66",
  case_id = as.character(r66$case_id),
  config = config_path,
  config_sha256 = config_sha256,
  source_r65_config = source_r65_config,
  source_r65_config_sha256 = r66$source_r65_config_sha256,
  adapter_dir = adapter_dir,
  adapter_source_sha256 = if (!is.null(r66$reuse$adapter)) {
    r66$reuse$adapter$source_sha256
  } else {
    setNames(
      vapply(
        c("adapter_manifest.json", "feature_manifest.json", "X_train.csv", "y_train.csv", "X_val.csv", "rows_train.csv", "rows_val.csv"),
        function(name) r66_sha256(file.path(adapter_dir, name)),
        character(1)
      ),
      c("adapter_manifest.json", "feature_manifest.json", "X_train.csv", "y_train.csv", "X_val.csv", "rows_train.csv", "rows_val.csv")
    )
  },
  output_dir = out_dir,
  package_path = package_path,
  package_library = package_library,
  package_head = package_head,
  package_source_sha256 = r66$package$source_sha256,
  runtime_source_sha256 = r66$code$source_sha256,
  method_ids = r66$method_ids,
  structured_sigmagam = profile,
  quantiles = quantiles,
  configured_splits = c("train", "val"),
  evaluation_splits = c("val"),
  normal_anchor_sha256 = normal_hash,
  normal_anchor_path = normal_effective_path,
  normal_anchor_source = normal_source,
  adapter_reused_from_r65 = !is.null(r66$reuse$adapter),
  reused_r65_al_components = sum(component_frame$al_reused_from_r65),
  reused_r65_exal_components = 0L,
  test_loaded = FALSE
), file.path(out_dir, "run_manifest.json"))

cat(out_dir, "\n")
