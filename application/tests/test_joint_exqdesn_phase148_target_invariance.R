repo_root <- normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_validation.R",
  "joint_exqdesn_phase148_target_invariance.R"
)) source(app_path("application/R", path))

identity <- app_joint_exqdesn_phase148_identity_audit(c(0.10, 0.50, 0.90))
stopifnot(nrow(identity) == 3L)
stopifnot(all(identity$sigma_identity_status == "pass"))
stopifnot(all(identity$gamma_identity_status == "pass"))

state <- app_joint_exqdesn_phase148_state(0.5, seed = 148L, n = 8L)
grid <- app_joint_exqdesn_phase148_grid(state, n_log_sigma = 31L, n_eta = 41L)
stopifnot(all(is.finite(grid$weight)), abs(sum(grid$weight) - 1) < 1e-10)

out_dir <- tempfile("phase148_")
result <- app_joint_exqdesn_run_phase148_target_invariance(
  out_dir = out_dir,
  sampler_tau_grid = 0.5,
  n_iter = 1200L,
  burn = 200L,
  thin = 2L,
  sampler_review_tolerance = 1
)
stopifnot(result$assessment$gate_status[[1L]] != "fail")
manifest <- app_read_csv(file.path(out_dir, "artifact_manifest.csv"))
stopifnot(nrow(manifest) == 7L)
stopifnot(all(file.exists(file.path(out_dir, manifest$relative_path))))
stopifnot(all(vapply(file.path(out_dir, manifest$relative_path), app_sha256_file, character(1L)) == manifest$sha256))

cat("Joint exQDESN Phase148 target-invariance tests passed.\n")
