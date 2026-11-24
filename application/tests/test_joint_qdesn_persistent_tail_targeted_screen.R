#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts", "_joint_qdesn_persistent_tail_targeted_bootstrap.R"))

contract <- app_joint_pht_read_contract()
axes <- app_joint_pht_read_axes()
registry <- app_joint_pht_registry(contract)
stopifnot(
  contract$scenario_count == 1L,
  identical(contract$scenario_id, "persistent_heavy_tail"),
  contract$candidate_count == 1536L,
  contract$candidate_count == contract$anchor_count + contract$local_count +
    contract$supercritical_count + contract$global_count,
  contract$max_workers == 30L,
  identical(contract$required_hostname, "jerez.be.ucsc.edu"),
  contract$protected_selection_forbidden,
  contract$stop_after_median,
  !contract$automatic_downstream_launch,
  identical(axes$rho_range, c(0.1, 1.2)),
  max(axes$state_budget) == 600L,
  max(axes$response_lags) == 360L,
  max(axes$depth) == 8L,
  nrow(registry) == 1L
)

candidates <- app_joint_pht_candidate_registry(contract, axes, registry)
stopifnot(
  nrow(candidates) == 1536L,
  !anyDuplicated(candidates$candidate_id),
  !anyDuplicated(candidates$structural_signature),
  all(candidates$scenario_id == "persistent_heavy_tail"),
  sum(candidates$candidate_role == "supercritical_rho") == 512L,
  all(candidates$rho_requested_max > 0),
  max(candidates$rho_requested_max) <= 1.2,
  any(candidates$rho_requested_max > 1),
  all(app_as_bool_vec(candidates$allow_supercritical_rho[candidates$rho_requested_max >= 1])),
  all(!app_as_bool_vec(candidates$enforce_leaky_radius[candidates$rho_requested_max >= 1])),
  all(!app_as_bool_vec(candidates$allow_supercritical_rho[candidates$rho_requested_max < 1]))
)

base_cfg <- list(reservoir = list(
  D = 1L, n = 20L, n_tilde = integer(), m = 2L,
  alpha = 0.2, rho = 1.1, pi_w = 0.5, pi_in = 1,
  w_dist = "uniform", in_dist = "uniform", act_f = "tanh", act_k = "identity"
))
rejected <- try(app_qdesn_generate_article_reservoir(base_cfg, seed = 17L, m_input = 2L), silent = TRUE)
stopifnot(inherits(rejected, "try-error"))
base_cfg$reservoir$allow_supercritical_rho <- TRUE
base_cfg$reservoir$rho_upper_bound <- 1.2
base_cfg$reservoir$enforce_leaky_radius <- FALSE
accepted <- app_qdesn_generate_article_reservoir(base_cfg, seed = 17L, m_input = 2L)
actual_rho <- app_qdesn_spectral_radius(accepted$W[[1L]])
stopifnot(
  isTRUE(accepted$allow_supercritical_rho),
  !isTRUE(accepted$enforce_leaky_radius),
  abs(actual_rho - 1.1) < 1e-7
)
base_cfg$reservoir$rho <- 1.2001
rejected_upper <- try(app_qdesn_generate_article_reservoir(base_cfg, seed = 17L, m_input = 2L), silent = TRUE)
stopifnot(inherits(rejected_upper, "try-error"))

probe <- candidates[seq_len(500L), , drop = FALSE]
authority <- candidates[grepl("anchor_authoritative_v3", candidates$candidate_role), , drop = FALSE]
supercritical <- candidates[candidates$rho_requested_max >= 1, , drop = FALSE][seq_len(120L), ]
probe <- app_bind_rows_fill(list(authority, supercritical, probe))
probe <- probe[!duplicated(probe$candidate_id), , drop = FALSE]
probe$finite_fraction <- 1
probe$protected_rows_loaded_max <- 0L
probe$max_state_saturation <- 0.01
probe$calibration_acrps_mean <- seq_len(nrow(probe)) / nrow(probe)
probe$calibration_acrps_worst <- probe$calibration_acrps_mean + 0.01
probe$calibration_acrps_sd <- 0.001
selected <- app_joint_pht_select_candidates(probe, 128L, 32L, 0.25)
stopifnot(
  nrow(selected) == 128L,
  sum(selected$rho_requested_max >= 1) >= 32L,
  any(grepl("anchor_authoritative_v3", selected$candidate_role))
)

launcher <- paste(readLines(file.path(repo_root, "application/scripts",
  "launch_joint_qdesn_persistent_tail_targeted_stage.sh"), warn = FALSE), collapse = "\n")
stopifnot(
  grepl("jerez.be.ucsc.edu", launcher, fixed = TRUE),
  grepl("1-30 reviewed physical-core CPU IDs", launcher, fixed = TRUE),
  grepl("free_gib >= 80", launcher, fixed = TRUE),
  grepl("available_gib >= 128", launcher, fixed = TRUE),
  grepl("taskset -c", launcher, fixed = TRUE),
  grepl("git status --porcelain", launcher, fixed = TRUE),
  grepl("$2 ~ /^(R|Rscript)$/", launcher, fixed = TRUE),
  grepl("Another model Rscript is active", launcher, fixed = TRUE),
  !grepl("finalize_joint_qdesn_persistent_tail", launcher, fixed = TRUE)
)
worker_script <- paste(readLines(file.path(repo_root, "application/scripts",
  "run_joint_qdesn_persistent_tail_targeted_worker.R"), warn = FALSE), collapse = "\n")
check_script <- paste(readLines(file.path(repo_root, "application/scripts",
  "check_joint_qdesn_persistent_tail_targeted_screen.R"), warn = FALSE), collapse = "\n")
stopifnot(
  grepl("worker %d failed", worker_script, fixed = TRUE),
  grepl("health$failed > 0L", check_script, fixed = TRUE)
)

cat("Persistent-heavy-tail targeted screening tests passed.\n")
