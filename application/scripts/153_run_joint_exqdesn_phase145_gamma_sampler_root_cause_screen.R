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
source(app_path("application/R/joint_exqdesn_phase136_gamma_kernel_packet.R"))
source(app_path("application/R/joint_exqdesn_phase145_gamma_sampler_root_cause.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase145_gamma_sampler_root_cause_student_t_20260723",
  phase135_screening_dir = "application/cache/joint_qdesn_phase135_matched_exal_screening_20260715",
  phase135_audit_dir = "application/cache/joint_qdesn_phase135_matched_exal_screening_20260715/phase135_result_audit",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  case_ids = "student_t_location_scale__joint_exqdesn_rhs_vb",
  phase145_variant_ids = "",
  n_chains = "8",
  mcmc_n_iter = "10000",
  mcmc_burn = "3000",
  mcmc_thin = "2",
  mcmc_seed_offset = "14500",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "32",
  vb_n_cores = "6",
  trace_write_stride = "50",
  save_rdata = "false",
  dry_run = "false"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(trimws(x))) return(character())
  vals <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  vals[nzchar(vals)]
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

parse_bool <- function(x) {
  tolower(as.character(x)[[1L]]) %in% c("true", "t", "yes", "y", "1")
}

result <- app_joint_exqdesn_run_phase145_gamma_sampler_root_cause_screen(
  out_dir = arg_value("output_dir"),
  phase135_screening_dir = arg_value("phase135_screening_dir"),
  phase135_audit_dir = arg_value("phase135_audit_dir"),
  fixture_dir = arg_value("fixture_dir"),
  case_ids = parse_csv(arg_value("case_ids")),
  phase145_variant_ids = parse_csv(arg_value("phase145_variant_ids")),
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin")),
  mcmc_seed_offset = parse_integer(arg_value("mcmc_seed_offset")),
  chain_seed_stride = parse_integer(arg_value("chain_seed_stride")),
  sigma_upper_multiplier = parse_number(arg_value("sigma_upper_multiplier")),
  distance_pass = parse_number(arg_value("distance_pass")),
  chain_pass = parse_number(arg_value("chain_pass")),
  n_cores = parse_integer(arg_value("n_cores")),
  vb_n_cores = parse_integer(arg_value("vb_n_cores")),
  trace_write_stride = parse_integer(arg_value("trace_write_stride")),
  save_rdata = parse_bool(arg_value("save_rdata")),
  dry_run = parse_bool(arg_value("dry_run"))
)

cat(sprintf("Phase145 gamma sampler root-cause artifacts written to %s\n", result$out_dir))
cat(sprintf("Gate status: %s\n", result$decision$gate_status[[1L]]))
cat(sprintf("Recommendation: %s\n", result$decision$recommendation[[1L]]))
if (!is.null(result$phase136$run_config)) {
  print(result$phase136$run_config[, c("n_cases", "n_case_variants", "total_chain_jobs", "n_cores", "dry_run")], row.names = FALSE)
}
if (!is.null(result$phase136$assessment)) {
  print(table(result$phase136$assessment$phase136_gate_status))
}
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
