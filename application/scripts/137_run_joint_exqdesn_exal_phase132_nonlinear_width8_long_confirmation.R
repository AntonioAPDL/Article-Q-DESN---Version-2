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

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase132_nonlinear_tau025_width8_long_confirmation_20260714",
  scenario_ids = "nonlinear_reservoir_friendly",
  width_multiplier = "4",
  target_tau = "0.25",
  target_width_multiplier = "8",
  gamma_slice_max_steps = "100",
  n_chains = "12",
  mcmc_n_iter = "16000",
  mcmc_burn = "4000",
  mcmc_thin = "1",
  n_cores = "24",
  vb_n_cores = "2",
  gamma_init_mode = "vb_jittered",
  gamma_jitter_fraction = "0.10",
  trace_write_stride = "100",
  save_rdata = "false",
  phase122_dir = "application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711",
  phase124c_dir = "application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  phase131_dir = "application/cache/joint_qdesn_phase131_nonlinear_tau025_sampler_tuning_20260713",
  vb_max_iter_override = "",
  adaptive_vb_max_iter_grid_override = "",
  child_script = "application/scripts/134_run_joint_exqdesn_exal_gamma_width4_packet.R",
  dry_run = "false"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_bool <- function(x) {
  tolower(as.character(x)[[1L]]) %in% c("true", "t", "yes", "y", "1")
}

resolve_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

child_script <- arg_value("child_script")
child_path <- if (grepl("^/", child_script)) child_script else app_path(child_script)
child_path <- normalizePath(child_path, mustWork = TRUE)

phase131_dir <- resolve_path(arg_value("phase131_dir"), must_work = FALSE)
phase131_recommendation <- file.path(phase131_dir, "phase131_recommendation.csv")
if (file.exists(phase131_recommendation)) {
  rec <- app_read_csv(phase131_recommendation)
  expected <- nrow(rec) == 1L &&
    identical(rec$recommended_variant[[1L]], "target_w8_s100") &&
    identical(rec$recommendation[[1L]], "promote_variant_for_long_confirmation")
  if (!isTRUE(expected)) {
    stop("Phase132 expected Phase131 to recommend target_w8_s100 for long confirmation.", call. = FALSE)
  }
} else {
  warning("Phase131 recommendation was not found; continuing because Phase132 controls are explicit.")
}

child_args <- c(
  child_path,
  "--output-dir", arg_value("output_dir"),
  "--phase122-dir", arg_value("phase122_dir"),
  "--phase124c-dir", arg_value("phase124c_dir"),
  "--fixture-dir", arg_value("fixture_dir"),
  "--scenario-ids", arg_value("scenario_ids"),
  "--width-multiplier", arg_value("width_multiplier"),
  "--target-tau", arg_value("target_tau"),
  "--target-width-multiplier", arg_value("target_width_multiplier"),
  "--gamma-slice-max-steps", arg_value("gamma_slice_max_steps"),
  "--n-chains", arg_value("n_chains"),
  "--mcmc-n-iter", arg_value("mcmc_n_iter"),
  "--mcmc-burn", arg_value("mcmc_burn"),
  "--mcmc-thin", arg_value("mcmc_thin"),
  "--n-cores", arg_value("n_cores"),
  "--vb-n-cores", arg_value("vb_n_cores"),
  "--gamma-init-mode", arg_value("gamma_init_mode"),
  "--gamma-jitter-fraction", arg_value("gamma_jitter_fraction"),
  "--trace-write-stride", arg_value("trace_write_stride"),
  "--save-rdata", arg_value("save_rdata")
)
if (nzchar(trimws(arg_value("vb_max_iter_override")))) {
  child_args <- c(child_args, "--vb-max-iter-override", arg_value("vb_max_iter_override"))
}
if (nzchar(trimws(arg_value("adaptive_vb_max_iter_grid_override")))) {
  child_args <- c(child_args, "--adaptive-vb-max-iter-grid-override", arg_value("adaptive_vb_max_iter_grid_override"))
}

cat("Launching Phase132 nonlinear tau-0.25 width-8 long confirmation via:\n")
cat(file.path(R.home("bin"), "Rscript"), paste(shQuote(child_args), collapse = " "), "\n")
if (parse_bool(arg_value("dry_run"))) quit(status = 0L, save = "no")

status <- system2(file.path(R.home("bin"), "Rscript"), child_args)
if (!identical(status, 0L)) {
  quit(status = if (is.numeric(status)) as.integer(status) else 1L, save = "no")
}
