#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_vb_spec_screening.R",
  "joint_qdesn_calibration_screening.R", "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  freeze_dir = "application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802",
  output_dir = "local_trackers/joint_exqdesn_phase157b_worker_preflight_20260802",
  n_iter = "12", burn = "4", thin = "2"
))

value <- function(name) args[[gsub("_", "-", name, fixed = TRUE)]] %||% args[[name]]
path <- function(name, must = FALSE) {
  x <- as.character(value(name))[[1L]]
  normalizePath(if (grepl("^/", x)) x else app_path(x), mustWork = must)
}
int <- function(name) as.integer(as.character(value(name))[[1L]])

freeze_dir <- path("freeze_dir", TRUE)
out_dir <- path("output_dir")
n_iter <- int("n_iter")
burn <- int("burn")
thin <- int("thin")
if (n_iter <= burn || thin <= 0L || ((n_iter - burn) %% thin) != 0L) {
  stop("Preflight controls require n_iter > burn and an integer retained-draw count.", call. = FALSE)
}
if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE, no.. = TRUE))) {
  stop(sprintf("Preflight output directory is not empty: %s", out_dir), call. = FALSE)
}
app_ensure_dir(out_dir)

run_one <- function(run_id) {
  run_dir <- file.path(out_dir, run_id)
  preflight_freeze <- file.path(run_dir, "freeze")
  worker_dir <- file.path(run_dir, "worker")
  failure_dir <- file.path(run_dir, "failures")
  app_ensure_dir(run_dir)
  app_joint_exqdesn_phase157b_make_preflight_freeze(
    freeze_dir = freeze_dir,
    out_dir = preflight_freeze,
    worker_output_dir = worker_dir,
    n_iter = n_iter,
    burn = burn,
    thin = thin
  )
  worker <- app_joint_exqdesn_run_phase157_worker(
    freeze_dir = preflight_freeze,
    worker_id = 1L,
    reuse_completed = FALSE,
    failure_dir = failure_dir
  )
  score <- app_joint_exqdesn_phase157b_preflight_score(preflight_freeze)
  draw_path <- file.path(worker_dir, "posterior_draws.csv.gz")
  data.frame(
    run_id = run_id,
    worker_status = worker$status,
    score,
    canonical_draw_sha256 = app_joint_exqdesn_phase157b_canonical_draw_hash(draw_path),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

run_summary <- app_joint_qdesn_bind_rows(list(run_one("run_a"), run_one("run_b")))
stable_hash <- data.frame(
  artifact = "canonical_uncompressed_posterior_draw_table",
  run_a_sha256 = run_summary$canonical_draw_sha256[run_summary$run_id == "run_a"],
  run_b_sha256 = run_summary$canonical_draw_sha256[run_summary$run_id == "run_b"],
  identical = length(unique(run_summary$canonical_draw_sha256)) == 1L,
  stringsAsFactors = FALSE
)

failure_probe_dir <- file.path(out_dir, "failure_probe")
failure_probe_freeze <- file.path(failure_probe_dir, "freeze")
failure_probe_worker <- file.path(failure_probe_dir, "worker")
failure_probe_orchestration <- file.path(failure_probe_dir, "orchestration")
app_joint_exqdesn_phase157b_make_preflight_freeze(
  freeze_dir = freeze_dir,
  out_dir = failure_probe_freeze,
  worker_output_dir = failure_probe_worker,
  n_iter = n_iter,
  burn = burn,
  thin = thin
)
receipt <- app_joint_exqdesn_phase157_failure_receipt(
  freeze_dir = failure_probe_freeze,
  worker_id = 1L,
  stage = "injected_preflight_failure",
  condition = simpleError("intentional lifecycle-preflight failure"),
  failure_dir = file.path(failure_probe_orchestration, "failures")
)
failure_health <- app_joint_exqdesn_phase157_health(failure_probe_freeze, failure_probe_orchestration)
failure_audit <- data.frame(
  injected_stage = receipt$receipt$stage,
  worker_failure_receipt_exists = file.exists(file.path(failure_probe_worker, "failure_receipt.csv")),
  orchestration_failure_receipt_exists = file.exists(file.path(failure_probe_orchestration, "failures", "worker_001.csv")),
  health_state = failure_health$inventory$state[[1L]],
  status = if (
    file.exists(file.path(failure_probe_worker, "failure_receipt.csv")) &&
      file.exists(file.path(failure_probe_orchestration, "failures", "worker_001.csv")) &&
      identical(failure_health$inventory$state[[1L]], "failed")
  ) "pass" else "fail",
  stringsAsFactors = FALSE
)

source_verification <- app_joint_qdesn_bind_rows(list(
  app_joint_qdesn_phase108_manifest_verify(freeze_dir, "phase156b_recovery_freeze"),
  app_joint_qdesn_phase108_manifest_verify(file.path(out_dir, "run_a", "freeze"), "run_a_preflight_freeze"),
  app_joint_qdesn_phase108_manifest_verify(file.path(out_dir, "run_a", "worker"), "run_a_worker"),
  app_joint_qdesn_phase108_manifest_verify(file.path(out_dir, "run_b", "freeze"), "run_b_preflight_freeze"),
  app_joint_qdesn_phase108_manifest_verify(file.path(out_dir, "run_b", "worker"), "run_b_worker")
))

expected_keep <- as.integer((n_iter - burn) / thin)
gate_checks <- data.frame(
  check_id = c(
    "both_workers_completed", "expected_retained_draws", "finite_draws",
    "positive_sigma", "finite_fit_score", "zero_contract_crossings",
    "worker_manifests_verified", "deterministic_draw_hash", "failure_receipts_observable",
    "all_source_manifests_verified"
  ),
  passed = c(
    all(run_summary$worker_status == "completed"),
    all(run_summary$n_keep == expected_keep),
    all(run_summary$all_finite),
    all(run_summary$sigma_positive),
    all(is.finite(run_summary$fit_truth_mae)),
    all(run_summary$contract_crossing_pairs == 0L),
    all(run_summary$worker_manifest_verified),
    stable_hash$identical[[1L]],
    failure_audit$status[[1L]] == "pass",
    nrow(source_verification) > 0L && all(source_verification$status == "pass")
  ),
  stringsAsFactors = FALSE
)
assessment <- data.frame(
  phase_id = "phase157b_real_fixture_worker_lifecycle_preflight",
  scenario_id = run_summary$scenario_id[[1L]],
  repeated_runs = nrow(run_summary),
  n_iter = n_iter,
  burn = burn,
  thin = thin,
  expected_keep = expected_keep,
  checks_passed = sum(gate_checks$passed),
  checks_total = nrow(gate_checks),
  gate_status = if (all(gate_checks$passed)) "pass" else "fail",
  scope = "implementation_lifecycle_only_not_statistical_evidence",
  stringsAsFactors = FALSE
)

readme <- file.path(out_dir, "README.md")
writeLines(c(
  "# Phase157b real-fixture worker lifecycle preflight", "",
  "This bounded preflight executes the production worker twice against one real frozen fixture and seed.",
  "It validates draw serialization, deserialization, scoring, deterministic content, artifact hashes, and explicit failure receipts.",
  "The short chains are implementation checks only and carry no statistical or article-evidence interpretation.", "",
  sprintf("- Source freeze: `%s`", freeze_dir),
  sprintf("- Scenario: `%s`", run_summary$scenario_id[[1L]]),
  sprintf("- Controls: n_iter=%d, burn=%d, thin=%d", n_iter, burn, thin),
  sprintf("- Gate: `%s` (%d/%d checks)", assessment$gate_status[[1L]], assessment$checks_passed[[1L]], assessment$checks_total[[1L]])
), readme, useBytes = TRUE)

paths <- c(
  preflight_run_summary = app_joint_qvp_write_csv(run_summary, file.path(out_dir, "preflight_run_summary.csv")),
  stable_hash_comparison = app_joint_qvp_write_csv(stable_hash, file.path(out_dir, "stable_hash_comparison.csv")),
  failure_observability_audit = app_joint_qvp_write_csv(failure_audit, file.path(out_dir, "failure_observability_audit.csv")),
  gate_checks = app_joint_qvp_write_csv(gate_checks, file.path(out_dir, "preflight_gate_checks.csv")),
  source_manifest_verification = app_joint_qvp_write_csv(source_verification, file.path(out_dir, "source_manifest_verification.csv")),
  preflight_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "preflight_assessment.csv")),
  run_a_worker_manifest = normalizePath(file.path(out_dir, "run_a", "worker", "artifact_manifest.csv"), mustWork = TRUE),
  run_b_worker_manifest = normalizePath(file.path(out_dir, "run_b", "worker", "artifact_manifest.csv"), mustWork = TRUE),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme, mustWork = TRUE)
)
manifest <- app_joint_exqdesn_trace_manifest(paths, out_dir)
verification <- app_joint_qdesn_phase108_manifest_verify(out_dir, "phase157b_worker_preflight")
if (assessment$gate_status[[1L]] != "pass" || any(verification$status != "pass")) {
  stop("Phase157b real-fixture worker lifecycle preflight failed.", call. = FALSE)
}

cat(sprintf("Phase157b preflight: %s\n", out_dir))
cat(sprintf("Scenario/runs: %s/%d\n", assessment$scenario_id[[1L]], assessment$repeated_runs[[1L]]))
cat(sprintf("Gate: %s (%d/%d checks)\n", assessment$gate_status[[1L]], assessment$checks_passed[[1L]], assessment$checks_total[[1L]]))
cat(sprintf("Manifest entries verified: %d/%d\n", sum(verification$status == "pass"), nrow(verification)))
