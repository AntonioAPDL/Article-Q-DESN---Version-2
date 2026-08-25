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
  output_dir = "application/cache/joint_qdesn_phase130_joint_exqdesn_targeted_long_chains_20260713",
  scenario_ids = "nonlinear_reservoir_friendly,student_t_location_scale",
  width_multiplier = "4",
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
  vb_max_iter_override = "",
  adaptive_vb_max_iter_grid_override = "",
  child_script = "application/scripts/134_run_joint_exqdesn_exal_gamma_width4_packet.R"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

child_script <- arg_value("child_script")
child_path <- if (grepl("^/", child_script)) child_script else app_path(child_script)
child_path <- normalizePath(child_path, mustWork = TRUE)

child_args <- c(
  child_path,
  "--output-dir", arg_value("output_dir"),
  "--phase122-dir", arg_value("phase122_dir"),
  "--phase124c-dir", arg_value("phase124c_dir"),
  "--fixture-dir", arg_value("fixture_dir"),
  "--scenario-ids", arg_value("scenario_ids"),
  "--width-multiplier", arg_value("width_multiplier"),
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

cat("Launching Phase130 targeted long-chain Joint exQDESN exAL-RHS run via:\n")
cat(file.path(R.home("bin"), "Rscript"), paste(shQuote(child_args), collapse = " "), "\n")
status <- system2(file.path(R.home("bin"), "Rscript"), child_args)
if (!identical(status, 0L)) {
  quit(status = if (is.numeric(status)) as.integer(status) else 1L, save = "no")
}
