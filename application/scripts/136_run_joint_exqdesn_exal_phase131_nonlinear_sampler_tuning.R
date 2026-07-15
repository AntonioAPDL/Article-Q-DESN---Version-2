#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_trace_tools.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase131_nonlinear_tau025_sampler_tuning_20260713",
  phase130_dir = "application/cache/joint_qdesn_phase130_joint_exqdesn_targeted_long_chains_20260713",
  phase122_dir = "application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711",
  phase124c_dir = "application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  child_script = "application/scripts/134_run_joint_exqdesn_exal_gamma_width4_packet.R",
  scenario_id = "nonlinear_reservoir_friendly",
  target_tau = "0.25",
  variants = "baseline_w4_s100:4::100,target_w8_s100:4:8:100,target_w12_s100:4:12:100,target_w8_s300:4:8:300,target_w12_s300:4:12:300",
  n_chains = "6",
  mcmc_n_iter = "6000",
  mcmc_burn = "1500",
  mcmc_thin = "1",
  n_cores = "12",
  vb_n_cores = "2",
  mcmc_seed_offset = "13100",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  gamma_init_mode = "vb_jittered",
  gamma_jitter_fraction = "0.10",
  trace_write_stride = "25",
  save_rdata = "false",
  run_variants = "true",
  skip_existing = "true"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_bool <- function(x) {
  tolower(as.character(x)[[1L]]) %in% c("true", "t", "yes", "y", "1")
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", x), call. = FALSE)
  out
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (is.na(out)) stop(sprintf("Expected numeric value, got '%s'.", x), call. = FALSE)
  out
}

resolve_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

parse_variants <- function(x) {
  x <- trimws(as.character(x)[[1L]])
  if (!nzchar(x)) stop("At least one Phase131 variant is required.", call. = FALSE)
  parts <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  parts <- parts[nzchar(parts)]
  rows <- lapply(parts, function(part) {
    fields <- strsplit(part, ":", fixed = TRUE)[[1L]]
    if (length(fields) != 4L) {
      stop("Variant specs must use label:base_width_multiplier:target_width_multiplier:gamma_slice_max_steps.", call. = FALSE)
    }
    label <- gsub("[^A-Za-z0-9_]+", "_", fields[[1L]])
    base_width <- suppressWarnings(as.numeric(fields[[2L]]))
    target_width <- if (nzchar(fields[[3L]])) suppressWarnings(as.numeric(fields[[3L]])) else NA_real_
    steps <- suppressWarnings(as.integer(as.numeric(fields[[4L]])))
    if (!nzchar(label) || !is.finite(base_width) || base_width <= 0 ||
        is.na(steps) || steps <= 0L ||
        (!is.na(target_width) && (!is.finite(target_width) || target_width <= 0))) {
      stop(sprintf("Invalid Phase131 variant spec: '%s'.", part), call. = FALSE)
    }
    data.frame(
      variant_label = label,
      base_width_multiplier = base_width,
      target_width_multiplier = target_width,
      gamma_slice_max_steps = steps,
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$variant_label)) stop("Phase131 variant labels must be unique.", call. = FALSE)
  out
}

read_csv_if_exists <- function(path) {
  if (!file.exists(path)) return(data.frame())
  app_read_csv(path)
}

verify_manifest_file <- function(dir, manifest_name = "artifact_manifest.csv") {
  manifest_path <- file.path(dir, manifest_name)
  if (!file.exists(manifest_path)) {
    return(data.frame(status = "missing_manifest", n_rows = 0L, n_pass = 0L, stringsAsFactors = FALSE))
  }
  manifest <- app_read_csv(manifest_path)
  if (!all(c("relative_path", "sha256") %in% names(manifest))) {
    return(data.frame(status = "malformed_manifest", n_rows = nrow(manifest), n_pass = 0L, stringsAsFactors = FALSE))
  }
  actual <- vapply(manifest$relative_path, function(rel) {
    path <- file.path(dir, rel)
    if (!file.exists(path)) return(NA_character_)
    app_sha256_file(path)
  }, character(1L))
  pass <- !is.na(actual) & identical(length(actual), length(manifest$sha256)) & actual == manifest$sha256
  data.frame(
    status = if (all(pass)) "pass" else "fail",
    n_rows = nrow(manifest),
    n_pass = sum(pass),
    stringsAsFactors = FALSE
  )
}

extract_target_rows <- function(dir, variant_label, target_tau) {
  case_assessment <- read_csv_if_exists(file.path(dir, "case_assessment.csv"))
  rhat <- read_csv_if_exists(file.path(dir, "mcmc_rhat_ess_summary.csv"))
  gap <- read_csv_if_exists(file.path(dir, "chain_mean_gap_summary.csv"))
  ac <- read_csv_if_exists(file.path(dir, "autocorrelation_summary.csv"))
  runtime <- read_csv_if_exists(file.path(dir, "runtime_summary.csv"))
  failures <- list(
    case_prep = read_csv_if_exists(file.path(dir, "case_preparation_failures.csv")),
    chain = read_csv_if_exists(file.path(dir, "chain_worker_failures.csv"))
  )
  manifest <- verify_manifest_file(dir)
  target_rhat <- rhat[abs(as.numeric(rhat$tau) - target_tau) <= 1.0e-8 &
                        rhat$parameter %in% c("gamma", "sigma"), , drop = FALSE]
  target_gap <- gap[abs(as.numeric(gap$tau) - target_tau) <= 1.0e-8 &
                      gap$parameter %in% c("gamma", "sigma", "exal_lambda"), , drop = FALSE]
  target_ac <- ac[abs(as.numeric(ac$tau) - target_tau) <= 1.0e-8 &
                    ac$parameter %in% c("gamma", "sigma", "exal_lambda") &
                    ac$lag %in% c(1L, 5L, 10L, 25L, 50L), , drop = FALSE]
  ac_summary <- if (nrow(target_ac)) {
    stats::aggregate(autocorrelation ~ scenario_id + parameter + lag, target_ac, function(x) max(x, na.rm = TRUE))
  } else {
    data.frame()
  }
  names(ac_summary)[names(ac_summary) == "autocorrelation"] <- "max_autocorrelation"
  lag1_gamma <- ac_summary$max_autocorrelation[ac_summary$parameter == "gamma" & ac_summary$lag == 1L]
  lag1_sigma <- ac_summary$max_autocorrelation[ac_summary$parameter == "sigma" & ac_summary$lag == 1L]
  chain_seconds <- if (nrow(runtime) && "elapsed_seconds" %in% names(runtime)) runtime$elapsed_seconds[runtime$runtime_component == "mcmc_chain"] else numeric()
  data.frame(
    variant_label = variant_label,
    manifest_status = manifest$status[[1L]],
    manifest_pass = sprintf("%s/%s", manifest$n_pass[[1L]], manifest$n_rows[[1L]]),
    case_gate_status = if (nrow(case_assessment)) paste(unique(case_assessment$case_gate_status), collapse = ";") else "missing",
    prep_failures = nrow(failures$case_prep),
    chain_failures = nrow(failures$chain),
    target_tau = target_tau,
    max_target_rhat = if (nrow(target_rhat)) max(target_rhat$rhat, na.rm = TRUE) else NA_real_,
    min_target_ess = if (nrow(target_rhat)) min(target_rhat$rough_ess_total, na.rm = TRUE) else NA_real_,
    gamma_target_rhat = if (nrow(target_rhat[target_rhat$parameter == "gamma", , drop = FALSE])) target_rhat$rhat[target_rhat$parameter == "gamma"][[1L]] else NA_real_,
    sigma_target_rhat = if (nrow(target_rhat[target_rhat$parameter == "sigma", , drop = FALSE])) target_rhat$rhat[target_rhat$parameter == "sigma"][[1L]] else NA_real_,
    gamma_target_ess = if (nrow(target_rhat[target_rhat$parameter == "gamma", , drop = FALSE])) target_rhat$rough_ess_total[target_rhat$parameter == "gamma"][[1L]] else NA_real_,
    sigma_target_ess = if (nrow(target_rhat[target_rhat$parameter == "sigma", , drop = FALSE])) target_rhat$rough_ess_total[target_rhat$parameter == "sigma"][[1L]] else NA_real_,
    max_gamma_chain_mean_gap = if (nrow(target_gap[target_gap$parameter == "gamma", , drop = FALSE])) max(target_gap$chain_mean_gap[target_gap$parameter == "gamma"], na.rm = TRUE) else NA_real_,
    max_sigma_chain_mean_gap = if (nrow(target_gap[target_gap$parameter == "sigma", , drop = FALSE])) max(target_gap$chain_mean_gap[target_gap$parameter == "sigma"], na.rm = TRUE) else NA_real_,
    max_lambda_chain_mean_gap = if (nrow(target_gap[target_gap$parameter == "exal_lambda", , drop = FALSE])) max(target_gap$chain_mean_gap[target_gap$parameter == "exal_lambda"], na.rm = TRUE) else NA_real_,
    max_gamma_lag1_ac = if (length(lag1_gamma)) max(lag1_gamma, na.rm = TRUE) else NA_real_,
    max_sigma_lag1_ac = if (length(lag1_sigma)) max(lag1_sigma, na.rm = TRUE) else NA_real_,
    mean_chain_seconds = if (length(chain_seconds)) mean(chain_seconds) else NA_real_,
    max_chain_seconds = if (length(chain_seconds)) max(chain_seconds) else NA_real_,
    stringsAsFactors = FALSE
  )
}

make_recommendation <- function(summary) {
  if (!nrow(summary)) return(data.frame())
  x <- summary
  x$implementation_gate <- ifelse(
    x$manifest_status == "pass" & x$prep_failures == 0L & x$chain_failures == 0L &
      is.finite(x$max_target_rhat) & is.finite(x$min_target_ess),
    "pass", "fail"
  )
  x$mixing_gate <- ifelse(
    x$implementation_gate != "pass", "fail",
    ifelse(x$max_target_rhat <= 1.2 & x$min_target_ess >= 100, "pass", "review")
  )
  x$rank_score <- x$max_target_rhat +
    0.001 * pmax(0, 500 - x$min_target_ess) +
    0.05 * pmax(0, x$max_gamma_lag1_ac - 0.98) * 100
  x <- x[order(x$implementation_gate != "pass", x$mixing_gate != "pass", x$rank_score, x$max_gamma_chain_mean_gap), , drop = FALSE]
  x$rank <- seq_len(nrow(x))
  best <- x[1L, , drop = FALSE]
  action <- if (identical(best$implementation_gate[[1L]], "fail")) {
    "fix_implementation_before_more_mcmc"
  } else if (identical(best$mixing_gate[[1L]], "pass")) {
    "promote_variant_for_long_confirmation"
  } else if (is.finite(best$max_target_rhat[[1L]]) && best$max_target_rhat[[1L]] < 1.3) {
    "rerun_best_variant_longer_or_with_joint_gamma_sigma_move"
  } else {
    "implement_joint_gamma_sigma_update_before_longer_runs"
  }
  data.frame(
    recommended_variant = best$variant_label,
    recommendation = action,
    implementation_gate = best$implementation_gate,
    mixing_gate = best$mixing_gate,
    max_target_rhat = best$max_target_rhat,
    min_target_ess = best$min_target_ess,
    max_gamma_chain_mean_gap = best$max_gamma_chain_mean_gap,
    max_gamma_lag1_ac = best$max_gamma_lag1_ac,
    rationale = paste(
      "Ranked by target tau gamma/sigma Rhat, ESS, chain-mean separation, and autocorrelation.",
      "Pass does not require perfect autocorrelation; high AC remains diagnostic review evidence."
    ),
    stringsAsFactors = FALSE
  )
}

out_dir <- resolve_path(arg_value("output_dir"), must_work = FALSE)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "variant_logs"))
app_ensure_dir(file.path(out_dir, "variants"))

phase130_dir <- resolve_path(arg_value("phase130_dir"), must_work = TRUE)
phase122_dir <- resolve_path(arg_value("phase122_dir"), must_work = TRUE)
phase124c_dir <- resolve_path(arg_value("phase124c_dir"), must_work = TRUE)
fixture_dir <- resolve_path(arg_value("fixture_dir"), must_work = TRUE)
child_script <- resolve_path(arg_value("child_script"), must_work = TRUE)
scenario_id <- as.character(arg_value("scenario_id"))[[1L]]
target_tau <- parse_number(arg_value("target_tau"))
variants <- parse_variants(arg_value("variants"))
run_variants <- parse_bool(arg_value("run_variants"))
skip_existing <- parse_bool(arg_value("skip_existing"))

base_child_args <- function(variant_dir, variant) {
  child_args <- c(
    child_script,
    "--output-dir", variant_dir,
    "--phase122-dir", phase122_dir,
    "--phase124c-dir", phase124c_dir,
    "--fixture-dir", fixture_dir,
    "--scenario-ids", scenario_id,
    "--width-multiplier", as.character(variant$base_width_multiplier),
    "--n-chains", as.character(arg_value("n_chains")),
    "--mcmc-n-iter", as.character(arg_value("mcmc_n_iter")),
    "--mcmc-burn", as.character(arg_value("mcmc_burn")),
    "--mcmc-thin", as.character(arg_value("mcmc_thin")),
    "--mcmc-seed-offset", as.character(arg_value("mcmc_seed_offset")),
    "--chain-seed-stride", as.character(arg_value("chain_seed_stride")),
    "--sigma-upper-multiplier", as.character(arg_value("sigma_upper_multiplier")),
    "--n-cores", as.character(arg_value("n_cores")),
    "--vb-n-cores", as.character(arg_value("vb_n_cores")),
    "--gamma-init-mode", as.character(arg_value("gamma_init_mode")),
    "--gamma-jitter-fraction", as.character(arg_value("gamma_jitter_fraction")),
    "--gamma-slice-max-steps", as.character(variant$gamma_slice_max_steps),
    "--trace-write-stride", as.character(arg_value("trace_write_stride")),
    "--save-rdata", as.character(arg_value("save_rdata"))
  )
  if (is.finite(variant$target_width_multiplier)) {
    child_args <- c(
      child_args,
      "--target-tau", as.character(target_tau),
      "--target-width-multiplier", as.character(variant$target_width_multiplier)
    )
  }
  child_args
}

variant_registry <- variants
variant_registry$scenario_id <- scenario_id
variant_registry$target_tau <- target_tau
variant_registry$output_dir <- file.path(out_dir, "variants", variant_registry$variant_label)
variant_registry$log_path <- file.path(out_dir, "variant_logs", paste0(variant_registry$variant_label, ".log"))
variant_registry$run_status <- "not_run"
variant_registry$exit_status <- NA_integer_

if (run_variants) {
  for (ii in seq_len(nrow(variant_registry))) {
    variant_dir <- variant_registry$output_dir[[ii]]
    log_path <- variant_registry$log_path[[ii]]
    if (skip_existing && file.exists(file.path(variant_dir, "artifact_manifest.csv"))) {
      variant_registry$run_status[[ii]] <- "skipped_existing_manifest"
      variant_registry$exit_status[[ii]] <- 0L
      next
    }
    app_ensure_dir(variant_dir)
    child_args <- base_child_args(variant_dir, variant_registry[ii, , drop = FALSE])
    writeLines(c(
      sprintf("Phase131 variant: %s", variant_registry$variant_label[[ii]]),
      sprintf("Command: Rscript %s", paste(shQuote(child_args), collapse = " "))
    ), log_path, useBytes = TRUE)
    status <- system2(file.path(R.home("bin"), "Rscript"), child_args, stdout = log_path, stderr = log_path, wait = TRUE)
    status <- status %||% 0L
    variant_registry$run_status[[ii]] <- if (identical(as.integer(status), 0L)) "completed" else "failed"
    variant_registry$exit_status[[ii]] <- as.integer(status)
  }
}

baseline_phase130 <- extract_target_rows(phase130_dir, "phase130_long_width4_reference", target_tau)
variant_summaries <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(variant_registry)), function(ii) {
  row <- variant_registry[ii, , drop = FALSE]
  if (!dir.exists(row$output_dir)) {
    return(data.frame(
      variant_label = row$variant_label,
      manifest_status = "missing_variant_dir",
      manifest_pass = "0/0",
      case_gate_status = "missing",
      prep_failures = NA_integer_,
      chain_failures = NA_integer_,
      target_tau = target_tau,
      max_target_rhat = NA_real_,
      min_target_ess = NA_real_,
      gamma_target_rhat = NA_real_,
      sigma_target_rhat = NA_real_,
      gamma_target_ess = NA_real_,
      sigma_target_ess = NA_real_,
      max_gamma_chain_mean_gap = NA_real_,
      max_sigma_chain_mean_gap = NA_real_,
      max_lambda_chain_mean_gap = NA_real_,
      max_gamma_lag1_ac = NA_real_,
      max_sigma_lag1_ac = NA_real_,
      mean_chain_seconds = NA_real_,
      max_chain_seconds = NA_real_,
      stringsAsFactors = FALSE
    ))
  }
  extract_target_rows(row$output_dir, row$variant_label, target_tau)
}))

variant_summary <- merge(
  variant_registry,
  variant_summaries,
  by = "variant_label",
  all.x = TRUE,
  sort = FALSE
)
recommendation <- make_recommendation(variant_summary)

run_config <- data.frame(
  run_id = "joint_qdesn_phase131_nonlinear_tau025_sampler_tuning",
  output_dir = out_dir,
  phase130_dir = phase130_dir,
  phase122_dir = phase122_dir,
  phase124c_dir = phase124c_dir,
  fixture_dir = fixture_dir,
  child_script = child_script,
  scenario_id = scenario_id,
  target_tau = target_tau,
  variants = as.character(arg_value("variants")),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin")),
  n_cores = parse_integer(arg_value("n_cores")),
  vb_n_cores = parse_integer(arg_value("vb_n_cores")),
  run_variants = run_variants,
  skip_existing = skip_existing,
  validation_contract = "targeted_joint_exqdesn_exal_gamma_sigma_sampler_tuning_no_article_mutation",
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Phase131 Joint exQDESN exAL-RHS Nonlinear Tau-0.25 Sampler Tuning",
  "",
  "This artifact targets the remaining Phase130 mixing weakness for the nonlinear reservoir-friendly scenario.",
  "It does not mutate article outputs. It compares bounded gamma-slice tuning variants around the tau-0.25 gamma/sigma ridge.",
  "",
  sprintf("- Scenario: `%s`", scenario_id),
  sprintf("- Target tau: `%s`", target_tau),
  sprintf("- Phase130 reference: `%s`", phase130_dir),
  sprintf("- Child runner: `%s`", child_script),
  sprintf("- Variant count: `%s`", nrow(variant_registry)),
  sprintf("- Chains/iter/burn/thin per variant: `%s/%s/%s/%s`",
          run_config$n_chains, run_config$mcmc_n_iter, run_config$mcmc_burn, run_config$mcmc_thin),
  "",
  "Gate interpretation:",
  "",
  "- `fail`: missing manifests, worker failures, or non-finite target diagnostics.",
  "- `review`: implementation-clean but target Rhat/ESS or autocorrelation remains weak.",
  "- `pass`: implementation-clean with target gamma/sigma Rhat <= 1.2 and ESS >= 100.",
  "",
  "Recommended action is recorded in `phase131_recommendation.csv`."
), readme_path, useBytes = TRUE)

paths <- c(
  run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
  variant_registry = app_joint_qvp_write_csv(variant_registry, file.path(out_dir, "variant_registry.csv")),
  phase130_target_reference = app_joint_qvp_write_csv(baseline_phase130, file.path(out_dir, "phase130_target_reference.csv")),
  variant_summary = app_joint_qvp_write_csv(variant_summary, file.path(out_dir, "variant_summary.csv")),
  phase131_recommendation = app_joint_qvp_write_csv(recommendation, file.path(out_dir, "phase131_recommendation.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE)
)

variant_manifests <- file.path(variant_registry$output_dir, "artifact_manifest.csv")
variant_manifests <- variant_manifests[file.exists(variant_manifests)]
if (length(variant_manifests)) {
  names(variant_manifests) <- paste0("variant_manifest_", app_joint_exqdesn_trace_safe_id(basename(dirname(variant_manifests))))
  paths <- c(paths, variant_manifests)
}

manifest_info <- app_joint_exqdesn_trace_manifest(paths, out_dir)

cat(sprintf("Phase131 nonlinear sampler tuning written to %s\n", normalizePath(out_dir, mustWork = TRUE)))
cat("Variant run statuses:\n")
print(variant_registry[, c("variant_label", "run_status", "exit_status", "output_dir")], row.names = FALSE)
cat("Target summary:\n")
print(variant_summary[, c("variant_label", "case_gate_status", "manifest_status", "max_target_rhat", "min_target_ess", "max_gamma_chain_mean_gap", "max_gamma_lag1_ac")], row.names = FALSE)
cat("Recommendation:\n")
print(recommendation, row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", manifest_info$manifest_path))
