screen_base_cfg <- list(
  reservoir = list(
    D = 1L,
    n = 300L,
    n_tilde = integer(0),
    m = 360L,
    washout = 500L,
    alpha = 0.1,
    rho = 0.95,
    pi_w = 0.03,
    pi_in = 1.0,
    win_scale_global = 0.18,
    win_scale_bias = 0.18,
    seed = 20260512L,
    standardize_inputs = TRUE,
    add_bias = TRUE
  ),
  feature_contract = list(
    version = "0.3",
    two_block_design = TRUE,
    reservoir_input = list(
      output_lags = list(range = c(1L, 360L)),
      covariates = list(
        ppt = list(range = c(0L, 359L)),
        soil = list(range = c(0L, 359L))
      )
    ),
    readout = list(
      add_intercept = TRUE,
      include_reservoir_state = TRUE,
      include_input_block = FALSE,
      include_horizon_scaled = FALSE
    ),
    blocks = list(discrepancy = list(reservoir_seed_offset = 1009L))
  ),
  inference = list(vb_ld = list(rhs_tau0 = 0.1, rhs_alpha_tau0 = 0.001))
)

stopifnot(identical(
  app_qdesn_block_config(screen_base_cfg, "reference")$reservoir$alpha,
  screen_base_cfg$reservoir$alpha
))
stopifnot(app_qdesn_block_seed(data.frame(), screen_base_cfg, "reference") == 20260512L)
stopifnot(app_qdesn_block_seed(data.frame(), screen_base_cfg, "discrepancy") == 20261521L)

screen_candidate <- data.frame(
  candidate_id = "fixture",
  `reference.D` = 2,
  `reference.n` = 40,
  `reference.n_tilde` = 30,
  `reference.m` = 120,
  `reference.washout` = 450,
  `reference.alpha` = 0.05,
  `reference.seed` = 11,
  `reference.rhs_tau0` = 1e-3,
  `discrepancy.D` = 3,
  `discrepancy.n` = 60,
  `discrepancy.n_tilde` = 20,
  `discrepancy.m` = 90,
  `discrepancy.washout` = 600,
  `discrepancy.alpha` = 0.2,
  `discrepancy.seed` = 29,
  `discrepancy.rhs_tau0` = 1e-4,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
screen_cfg <- app_glofas_median_screen_apply_candidate(screen_base_cfg, screen_candidate)
reference_cfg <- app_qdesn_block_config(screen_cfg, "reference")
discrepancy_cfg <- app_qdesn_block_config(screen_cfg, "discrepancy")
stopifnot(reference_cfg$reservoir$D == 2L)
stopifnot(identical(as.numeric(reference_cfg$reservoir$n), c(40, 40)))
stopifnot(identical(as.numeric(reference_cfg$reservoir$n_tilde), 30))
stopifnot(discrepancy_cfg$reservoir$D == 3L)
stopifnot(identical(as.numeric(discrepancy_cfg$reservoir$n), c(60, 60, 60)))
stopifnot(identical(as.numeric(discrepancy_cfg$reservoir$n_tilde), c(20, 20)))
stopifnot(app_qdesn_common_washout(screen_cfg) == 600L)
stopifnot(app_qdesn_block_seed(data.frame(), screen_cfg, "reference") == 11L)
stopifnot(app_qdesn_block_seed(data.frame(), screen_cfg, "discrepancy") == 29L)
stopifnot(screen_cfg$inference$vb_ld$rhs_tau0 == 1e-3)
stopifnot(screen_cfg$inference$vb_ld$rhs_alpha_tau0 == 1e-4)
stopifnot(identical(
  app_qdesn_reservoir_input_spec(reference_cfg)$output_lags,
  1:120
))
stopifnot(identical(
  app_qdesn_reservoir_input_spec(discrepancy_cfg)$covariate_lags$ppt,
  0:89
))

screen_state_root <- tempfile("median_screen_states_")
dir.create(file.path(screen_state_root, "status"), recursive = TRUE)
screen_state_runs <- file.path(screen_state_root, "runs", c("complete", "rejected", "failed"))
invisible(vapply(screen_state_runs, dir.create, logical(1L), recursive = TRUE))
file.create(file.path(screen_state_runs[[1L]], ".fit_recovery_complete"))
file.create(file.path(screen_state_runs[[2L]], ".reservoir_preflight_rejected"))
utils::write.csv(
  data.frame(status = "failed", exit_code = 1L),
  file.path(screen_state_root, "status", "failed.csv"),
  row.names = FALSE
)
screen_states <- app_glofas_median_screen_candidate_states(
  data.frame(
    candidate_id = c("complete", "rejected", "failed"),
    run_dir = screen_state_runs,
    stringsAsFactors = FALSE
  ),
  screen_state_root
)
stopifnot(identical(screen_states$state, c("completed", "preflight_rejected", "failed")))
stopifnot(identical(screen_states$terminal_for_strict_closeout, c(TRUE, TRUE, FALSE)))
unlink(screen_state_root, recursive = TRUE)

screen_retention_ranking <- data.frame(
  candidate_id = c("fit_b", "fit_a", "control"),
  screen_rank = c(2L, 1L, 3L),
  eligible_for_full7_review = c(FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)
screen_retention_manifest <- data.frame(
  candidate_id = c("fit_a", "fit_b", "control"),
  candidate_role = c("exploration", "exploration", "warm_control"),
  stringsAsFactors = FALSE
)
stopifnot(identical(
  app_glofas_median_screen_protected_candidates(
    screen_retention_ranking, screen_retention_manifest, top_n = 2L
  ),
  c("fit_a", "fit_b", "control")
))

screen_bootstrap_a <- app_glofas_median_screen_moving_block_bootstrap(
  rep(-0.1, 30L), block_length = 5L, replicates = 200L, seed = 17L
)
screen_bootstrap_b <- app_glofas_median_screen_moving_block_bootstrap(
  rep(-0.1, 30L), block_length = 5L, replicates = 200L, seed = 17L
)
stopifnot(identical(screen_bootstrap_a, screen_bootstrap_b))
stopifnot(screen_bootstrap_a$ci_upper[[1L]] < 0)

screen_space <- list(
  version = "1.0",
  screen_id = "fixture_screen",
  launch_authorized = FALSE,
  fixed = list(
    quantile_level = 0.5,
    parameters = list(
      reference = list(D = 2, n = 40, n_tilde = 30, pi_w = 0.03, pi_in = 1.0),
      discrepancy = list(D = 2, n = 40, n_tilde = 30, pi_w = 0.03, pi_in = 1.0)
    )
  ),
  candidate_sets = list(list(
    set_id = "alpha_tau",
    varying = list(
      reference = list(alpha = c(0.05, 0.1)),
      discrepancy = list(rhs_tau0 = c(1e-4, 1e-3))
    )
  )),
  execution = list(max_candidates = 10L)
)
screen_manifest <- app_glofas_median_screen_candidate_manifest(screen_space)
screen_manifest_again <- app_glofas_median_screen_candidate_manifest(screen_space)
stopifnot(nrow(screen_manifest) == 4L)
stopifnot(identical(screen_manifest$candidate_id, screen_manifest_again$candidate_id))
stopifnot(!any(screen_manifest$launch_authorized))

screen_too_large <- screen_space
screen_too_large$execution$max_candidates <- 3L
screen_limit_message <- tryCatch(
  {
    app_glofas_median_screen_candidate_manifest(screen_too_large)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("above execution.max_candidates", screen_limit_message, fixed = TRUE))

screen_unknown <- screen_space
screen_unknown$candidate_sets[[1L]]$varying$reference$unknown <- 1
screen_unknown_message <- tryCatch(
  {
    app_glofas_median_screen_validate_space(screen_unknown)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("unsupported parameters", screen_unknown_message, fixed = TRUE))

yaml_11_n_key <- list(reference = stats::setNames(list(80), "FALSE"))
yaml_11_n_key <- app_glofas_median_screen_normalize_yaml_keys(yaml_11_n_key)
stopifnot(identical(yaml_11_n_key$reference$n, 80))

source_fit_fixture <- tempfile("median_warm_source_", fileext = ".rds")
saveRDS(list(summary = list()), source_fit_fixture)
source_contract_fixture <- list(version = "1.0")
tau_only_row <- data.frame(`reference.rhs_tau0` = 1e-4, check.names = FALSE)
tau_only_cfg <- app_glofas_median_screen_apply_candidate(screen_base_cfg, tau_only_row)
exact_plan <- app_glofas_median_screen_warm_start_plan(
  screen_base_cfg, tau_only_cfg, source_fit_fixture, source_contract_fixture
)
stopifnot(isTRUE(exact_plan$enabled))
stopifnot(identical(exact_plan$compatibility_mode, "exact_design"))

screen_base_empty_list <- screen_base_cfg
screen_base_empty_list$reservoir$n_tilde <- list()
tau_only_list_cfg <- app_glofas_median_screen_apply_candidate(screen_base_empty_list, tau_only_row)
exact_list_plan <- app_glofas_median_screen_warm_start_plan(
  screen_base_empty_list, tau_only_list_cfg, source_fit_fixture, source_contract_fixture
)
stopifnot(identical(exact_list_plan$compatibility_mode, "exact_design"))

alpha_row <- data.frame(`reference.alpha` = 0.2, check.names = FALSE)
alpha_cfg <- app_glofas_median_screen_apply_candidate(screen_base_cfg, alpha_row)
coordinate_plan <- app_glofas_median_screen_warm_start_plan(
  screen_base_cfg, alpha_cfg, source_fit_fixture, source_contract_fixture
)
stopifnot(identical(coordinate_plan$compatibility_mode, "coordinate_transfer"))
stopifnot(isTRUE(coordinate_plan$requires_cold_confirmation))

size_row <- data.frame(
  `reference.D` = 2,
  `reference.n` = 50,
  `reference.n_tilde` = 50,
  check.names = FALSE
)
size_cfg <- app_glofas_median_screen_apply_candidate(screen_base_cfg, size_row)
state_plan <- app_glofas_median_screen_warm_start_plan(
  screen_base_cfg, size_cfg, source_fit_fixture, source_contract_fixture
)
stopifnot(identical(state_plan$compatibility_mode, "state_only"))
stopifnot(!isTRUE(state_plan$use_theta))
unlink(source_fit_fixture)

warm_design <- list(
  H_fixed = matrix(0, nrow = 4L, ncol = 2L, dimnames = list(NULL, c("beta__x", "alpha__x"))),
  future_key = data.frame(target_date = as.Date("2026-01-01") + 0:1, horizon = 1:2),
  p0 = 0.5,
  warm_start_design_hash = "same_design"
)
warm_contract <- app_latent_path_warm_start_contract(warm_design)
warm_design_reindexed <- warm_design
rownames(warm_design_reindexed$future_key) <- c("source_row_41", "source_row_99")
stopifnot(identical(
  warm_contract$future_key_hash,
  app_latent_path_warm_start_contract(warm_design_reindexed)$future_key_hash
))
warm_fit <- list(
  summary = list(
    theta_mean = c(0.1, 0.2),
    theta_cov = diag(2),
    y_future_mean = c(1, 2),
    y_future_cov = diag(2)
  ),
  variational_state = list(
    theta_mean = c(0.1, 0.2),
    theta_cov = diag(2),
    y_future_mean = c(1, 2),
    y_future_cov = diag(2)
  ),
  warm_start_contract = warm_contract
)
warm_fit_path <- tempfile("strict_warm_fit_", fileext = ".rds")
saveRDS(warm_fit, warm_fit_path)
stopifnot(identical(
  app_latent_path_warm_start_contract_from_fit(warm_fit_path),
  warm_contract
))
strict_warm <- app_latent_path_warm_start_prepare(
  warm_design,
  vb_args = list(warm_start = list(
    enabled = TRUE,
    fit_object = warm_fit_path,
    require_contract = TRUE,
    compatibility_mode = "exact_design",
    use_sigma = FALSE
  )),
  p = 2L,
  H_future = 2L
)
stopifnot(isTRUE(strict_warm$diagnostics$theta_used))
stopifnot(identical(strict_warm$diagnostics$compatibility_class, "exact_design"))

warm_design_mismatch <- warm_design
warm_design_mismatch$warm_start_design_hash <- "different_design"
strict_mismatch_message <- tryCatch(
  {
    app_latent_path_warm_start_prepare(
      warm_design_mismatch,
      vb_args = list(warm_start = list(
        enabled = TRUE,
        fit_object = warm_fit_path,
        require_contract = TRUE,
        compatibility_mode = "exact_design"
      )),
      p = 2L,
      H_future = 2L
    )
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("contract rejected", strict_mismatch_message, fixed = TRUE))
coordinate_warm <- app_latent_path_warm_start_prepare(
  warm_design_mismatch,
  vb_args = list(warm_start = list(
    enabled = TRUE,
    fit_object = warm_fit_path,
    require_contract = TRUE,
    compatibility_mode = "coordinate_transfer",
    use_sigma = FALSE
  )),
  p = 2L,
  H_future = 2L
)
stopifnot(isTRUE(coordinate_warm$diagnostics$theta_used))
stopifnot(identical(coordinate_warm$diagnostics$compatibility_class, "coordinate_transfer"))

nested_design <- warm_design_mismatch
nested_design$H_fixed <- matrix(
  0,
  nrow = 4L,
  ncol = 3L,
  dimnames = list(NULL, c("beta__x", "context__causal", "alpha__x"))
)
nested_warm <- app_latent_path_warm_start_prepare(
  nested_design,
  vb_args = list(warm_start = list(
    enabled = TRUE,
    fit_object = warm_fit_path,
    require_contract = TRUE,
    compatibility_mode = "nested_coordinate_transfer",
    new_coordinate_sd = 0.1,
    use_sigma = FALSE
  )),
  p = 3L,
  H_future = 2L
)
stopifnot(identical(
  nested_warm$diagnostics$compatibility_class,
  "nested_coordinate_transfer"
))
stopifnot(identical(nested_warm$theta_mean, c(beta__x = 0.1, context__causal = 0, alpha__x = 0.2)))
stopifnot(max(abs(
  unname(nested_warm$theta_cov[c(1L, 3L), c(1L, 3L)]) - diag(2)
)) < 1.0e-12)
stopifnot(abs(unname(nested_warm$theta_cov[2L, 2L]) - 0.01) < 1.0e-12)
stopifnot(all(nested_warm$theta_cov[2L, c(1L, 3L)] == 0))
stopifnot(nzchar(nested_warm$diagnostics$mapping_hash))
stopifnot(identical(nested_warm$diagnostics$new_coordinate_names, "context__causal"))

duplicate_nested_design <- nested_design
colnames(duplicate_nested_design$H_fixed)[[3L]] <- "beta__x"
duplicate_nested_error <- tryCatch(
  {
    app_latent_path_warm_start_prepare(
      duplicate_nested_design,
      vb_args = list(warm_start = list(
        enabled = TRUE,
        fit_object = warm_fit_path,
        require_contract = TRUE,
        compatibility_mode = "nested_coordinate_transfer"
      )),
      p = 3L,
      H_future = 2L
    )
    NULL
  },
  error = function(e) e
)
stopifnot(inherits(duplicate_nested_error, "error"))
unlink(warm_fit_path)

observed_fixture <- rbind(
  data.frame(candidate_id = "good", window = c("all", "last1000", "last200", "last50"), log1p_mae = c(0.061, 0.038, 0.052, 0.19)),
  data.frame(candidate_id = "bad_history", window = c("all", "last1000", "last200", "last50"), log1p_mae = c(0.08, 0.06, 0.08, 0.20))
)
forecast_fixture <- data.frame(
  candidate_id = c("good", "bad_history"),
  forecast_p50_check_loss_mean = c(0.75, 0.70),
  stringsAsFactors = FALSE
)
baseline_fixture <- list(
  forecast_p50_check_loss_mean = 0.798826956115941,
  observed_log1p_mae_all = 0.0624424466662982,
  observed_log1p_mae_last1000 = 0.0388437273850094,
  observed_log1p_mae_last200 = 0.05360828353558,
  observed_log1p_mae_last50 = 0.178787719773148
)
ranking_fixture <- app_glofas_median_screen_rank(
  observed_fixture,
  forecast_fixture,
  baseline_fixture,
  technical_status = data.frame(
    candidate_id = c("good", "bad_history"),
    technical_gate_pass = TRUE
  )
)
stopifnot(identical(ranking_fixture$candidate_id[[1L]], "good"))
stopifnot(isTRUE(ranking_fixture$eligible_for_full7_review[[1L]]))
stopifnot(identical(
  ranking_fixture$decision[ranking_fixture$candidate_id == "bad_history"],
  "reject_historical_fit_regression"
))
stopifnot(all(ranking_fixture$full7_required_for_distributional_crps))

stage_b_fixture <- data.frame(
  candidate_id = paste0("candidate_", 1:8),
  screen_rank = 1:8,
  technical_gate_pass = TRUE,
  historical_hard_gate_pass = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE),
  architecture_profile = c("d1_n250", "d1_n350", "d1_n400", "d2_n200", "d2_n300", "d1_n250", "d1_n350", "d2_n300"),
  reservoir_memory_profile = rep(c("m360", "m720"), 4),
  direct_memory_profile = rep(c("direct180", "direct360"), each = 4),
  `reference.alpha` = c(0.01, 0.10, 0.20, 0.01, 0.10, 0.20, 0.01, 0.10),
  `reference.rho` = rep(c(0.85, 0.95), 4),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
stage_b_selected <- app_glofas_median_screen_select_balanced_stage_b(stage_b_fixture, top_k = 7L)
stopifnot(nrow(stage_b_selected) == 7L)
stopifnot(!"candidate_7" %in% stage_b_selected$candidate_id)
stopifnot(length(unique(stage_b_selected$architecture_profile)) == 5L)
stopifnot(identical(stage_b_selected$stage_b_selection_order, 1:7))

template_space <- app_read_yaml(app_path("application/config/glofas_constrained_median_screen_space_TEMPLATE.yaml"))
app_glofas_median_screen_validate_space(template_space, allow_empty = TRUE)

fr09_template <- app_read_yaml(app_path("application/config/glofas_constrained_median_screen_space_FR09_TEMPLATE.yaml"))
app_glofas_median_screen_validate_space(fr09_template, allow_empty = TRUE)
stopifnot(!app_as_bool(fr09_template$launch_authorized))
stopifnot(!length(fr09_template$candidate_sets))

linked_stage_a_path <- app_path("application/config/glofas_p50_linked_d1d2_stage_a_20260811.yaml")
linked_stage_a <- app_glofas_median_screen_space(linked_stage_a_path)
linked_stage_a_manifest <- app_glofas_median_screen_candidate_manifest(linked_stage_a)
stopifnot(nrow(linked_stage_a_manifest) == 120L)
stopifnot(length(unique(linked_stage_a_manifest$candidate_id)) == 120L)
stopifnot(all(linked_stage_a_manifest$launch_authorized))
stopifnot(identical(sort(unique(linked_stage_a_manifest$architecture_profile)), c(
  "d1_n250", "d1_n350", "d1_n400", "d2_n200", "d2_n300"
)))
stopifnot(all(table(linked_stage_a_manifest$architecture_profile) == 24L))
stopifnot(all(table(linked_stage_a_manifest$reservoir_memory_profile) == 60L))
stopifnot(all(table(linked_stage_a_manifest$direct_memory_profile) == 60L))
stopifnot(all(table(linked_stage_a_manifest$reference.alpha) == 40L))
stopifnot(all(table(linked_stage_a_manifest$reference.rho) == 60L))
stopifnot(all(linked_stage_a_manifest$reference.D == linked_stage_a_manifest$discrepancy.D))
stopifnot(all(linked_stage_a_manifest$reference.n == linked_stage_a_manifest$discrepancy.n))
stopifnot(all(linked_stage_a_manifest$reference.m == linked_stage_a_manifest$discrepancy.m))
stopifnot(all(linked_stage_a_manifest$reference.alpha == linked_stage_a_manifest$discrepancy.alpha))
stopifnot(all(linked_stage_a_manifest$reference.rho == linked_stage_a_manifest$discrepancy.rho))
stopifnot(all(linked_stage_a_manifest$reference.seed == 20260512L))
stopifnot(all(linked_stage_a_manifest$discrepancy.seed == 20261521L))
stopifnot(all(linked_stage_a_manifest$reference.reservoir_output_lag_max == linked_stage_a_manifest$reference.m))
stopifnot(all(linked_stage_a_manifest$reference.reservoir_covariate_lag_max == linked_stage_a_manifest$reference.m))
stopifnot(all(linked_stage_a_manifest$reference.direct_output_lag_max == linked_stage_a_manifest$reference.direct_covariate_lag_max))
stopifnot(all(linked_stage_a_manifest$reference.rhs_tau0 == 0.1))
stopifnot(all(linked_stage_a_manifest$discrepancy.rhs_tau0 == 0.001))
stopifnot(as.integer(linked_stage_a$fixed$inference$max_iter) == 400L)
stopifnot(as.integer(linked_stage_a$fixed$inference$max_iter_hard_cap) == 400L)
stopifnot(as.integer(linked_stage_a$confirmation$authoritative_max_iter) == 400L)

d1_rows <- linked_stage_a_manifest$reference.D == 1L
d2_rows <- linked_stage_a_manifest$reference.D == 2L
stopifnot(all(is.na(linked_stage_a_manifest$reference.n_tilde[d1_rows])))
stopifnot(all(linked_stage_a_manifest$reference.n_tilde[d2_rows] == linked_stage_a_manifest$reference.n[d2_rows]))
stopifnot(all(linked_stage_a_manifest$discrepancy.n_tilde[d2_rows] == linked_stage_a_manifest$discrepancy.n[d2_rows]))

linked_full <- app_glofas_median_screen_space(
  app_path("application/config/glofas_p50_linked_d1d2_full_space_20260811.yaml")
)
linked_full_manifest <- app_glofas_median_screen_candidate_manifest(linked_full)
stopifnot(nrow(linked_full_manifest) == 1080L)
stopifnot(length(unique(linked_full_manifest$candidate_id)) == 1080L)
stopifnot(all(table(linked_full_manifest$architecture_profile) == 216L))
stopifnot(all(table(linked_full_manifest$reservoir_memory_profile) == 540L))
stopifnot(all(table(linked_full_manifest$direct_memory_profile) == 540L))
stopifnot(all(table(linked_full_manifest$prior_profile) == 120L))
stopifnot(all(table(linked_full_manifest$reference.rhs_tau0) == 360L))
stopifnot(all(table(linked_full_manifest$discrepancy.rhs_tau0) == 360L))
stopifnot(!any(linked_full_manifest$launch_authorized))

linked_wrong_count <- linked_stage_a
linked_wrong_count$execution$expected_candidates <- 121L
linked_count_message <- tryCatch(
  {
    app_glofas_median_screen_candidate_manifest(linked_wrong_count)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("not execution.expected_candidates=121", linked_count_message, fixed = TRUE))

linked_mixed <- linked_stage_a
linked_mixed$candidate_sets <- screen_space$candidate_sets
linked_mixed_message <- tryCatch(
  {
    app_glofas_median_screen_validate_space(linked_mixed)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("cannot be mixed", linked_mixed_message, fixed = TRUE))

linked_candidate_cfg <- app_glofas_median_screen_apply_candidate(
  screen_base_cfg,
  linked_stage_a_manifest[linked_stage_a_manifest$architecture_profile == "d2_n200", , drop = FALSE][1L, , drop = FALSE]
)
linked_contract <- app_glofas_median_screen_linked_desn_contract(linked_candidate_cfg)
stopifnot(isTRUE(linked_contract$pass))
stopifnot(linked_contract$reference_seed == 20260512L)
stopifnot(linked_contract$discrepancy_seed == 20261521L)

fr09_contract_path <- app_path("application/config/glofas_constrained_median_baseline_fr09.yaml")
fr09_contract <- app_glofas_median_screen_baseline_contract(fr09_contract_path)
stopifnot(identical(fr09_contract$candidate_id, "fr09_persistence_innovation"))
stopifnot(as.integer(fr09_contract$current_values$reference$n) == 300L)
stopifnot(identical(fr09_contract$engine$required_commit, "73c043f0436b508808366f312350fd44c2d06771"))
fr09_paths_available <- all(vapply(fr09_contract$artifacts, function(entry) {
  path <- as.character(entry$path %||% "")
  if (!nzchar(path)) return(FALSE)
  file.exists(if (grepl("^/", path)) path else app_path(path))
}, logical(1L)))
if (fr09_paths_available) {
  verified_fr09 <- app_glofas_median_screen_verify_baseline(fr09_contract_path)
  stopifnot(nrow(verified_fr09$audit) == 10L)
  stopifnot(all(verified_fr09$audit$verified))
  stopifnot(isTRUE(all.equal(
    as.numeric(verified_fr09$metrics$forecast_p50_check_loss_mean),
    0.798826956115941,
    tolerance = 1e-12
  )))
}

campaign_definition <- app_read_yaml(app_path(
  "application/config/glofas_p50_alpha_rho_tau_response_surface_20260819.yaml"
))
campaign_anchor_fixture <- list(
  candidate_id = "linked_stage_a_109_de5070bceb",
  ranking_path = "/tmp/ranking.csv",
  config_path = "/tmp/anchor_config.yaml",
  fit_object_path = "/tmp/anchor_fit.rds"
)
campaign_space <- app_glofas_median_campaign_space(
  campaign_definition,
  anchor = campaign_anchor_fixture
)
campaign_manifest <- app_glofas_median_screen_candidate_manifest(campaign_space)
campaign_manifest_again <- app_glofas_median_screen_candidate_manifest(campaign_space)
stopifnot(nrow(campaign_manifest) == 56L)
stopifnot(identical(campaign_manifest$candidate_id, campaign_manifest_again$candidate_id))
stopifnot(all(campaign_manifest$launch_authorized))
stopifnot(as.integer(campaign_space$fixed$inference$max_iter) == 150L)
stopifnot(as.integer(campaign_space$fixed$inference$max_iter_hard_cap) == 150L)
stopifnot(as.integer(campaign_space$scheduler$max_parallel) == 20L)
stopifnot(length(unique(as.integer(unlist(campaign_space$scheduler$cores)))) == 20L)
stopifnot(sum(campaign_manifest$warm_start_policy == "cold") == 2L)
stopifnot(all(is.na(campaign_manifest$warm_start_source_fit_object[campaign_manifest$warm_start_policy == "cold"])))
stopifnot(all(nzchar(campaign_manifest$warm_start_source_fit_object[campaign_manifest$warm_start_policy == "auto"])))
campaign_role_expected <- c(
  repeatability_canary = 2L,
  coordinate_transfer_canary = 2L,
  linked_alpha_profile = 14L,
  linked_rho_profile = 6L,
  linked_alpha_rho_interaction = 12L,
  tau0_sentinel = 8L,
  block_specific_alpha = 12L
)
campaign_role_observed <- table(campaign_manifest$candidate_role)
stopifnot(identical(
  as.integer(campaign_role_observed[names(campaign_role_expected)]),
  unname(campaign_role_expected)
))
stopifnot(all(campaign_manifest$reference.D == 2L))
stopifnot(all(campaign_manifest$discrepancy.D == 2L))
stopifnot(all(campaign_manifest$reference.n == 200L))
stopifnot(all(campaign_manifest$discrepancy.n == 200L))
stopifnot(all(campaign_manifest$reference.m == 720L))
stopifnot(all(campaign_manifest$discrepancy.m == 720L))
block_specific <- campaign_manifest$candidate_role == "block_specific_alpha"
stopifnot(all(campaign_manifest$reference.alpha[block_specific] != campaign_manifest$discrepancy.alpha[block_specific]))
stopifnot(!any(app_as_bool_vec(campaign_manifest$require_linked_desn[block_specific])))

focused_definition <- app_read_yaml(app_path(
  "application/config/glofas_p50_alpha_tau_focused_20260820.yaml"
))
focused_anchor_fixture <- list(
  candidate_id = "linked_alpha_profile_010_b20be44357",
  ranking_path = "/tmp/focused_ranking.csv",
  config_path = "/tmp/focused_anchor_config.yaml",
  fit_object_path = "/tmp/focused_anchor_fit.rds"
)
focused_space <- app_glofas_median_campaign_space(
  focused_definition,
  anchor = focused_anchor_fixture
)
focused_manifest <- app_glofas_median_screen_candidate_manifest(focused_space)
focused_manifest_again <- app_glofas_median_screen_candidate_manifest(focused_space)
stopifnot(nrow(focused_manifest) == 20L)
stopifnot(identical(focused_manifest$candidate_id, focused_manifest_again$candidate_id))
stopifnot(!anyDuplicated(focused_manifest$candidate_id))
stopifnot(sum(focused_manifest$warm_start_policy == "cold") == 2L)
stopifnot(sum(focused_manifest$candidate_role == "linked_alpha_tau_interaction") == 12L)
stopifnot(sum(focused_manifest$candidate_role == "block_specific_alpha_refinement") == 6L)
stopifnot(sum(focused_manifest$candidate_role == "cold_confirmation") == 2L)
stopifnot(all(focused_manifest$reference.rho == 0.95))
stopifnot(all(focused_manifest$discrepancy.rho == 0.95))
stopifnot(all(focused_manifest$reference.rhs_tau0 == 0.1))
stopifnot(identical(
  sort(unique(focused_manifest$discrepancy.rhs_tau0)),
  c(1e-6, 1e-4, 1e-3)
))
stopifnot(all(focused_manifest$reference.D == 2L))
stopifnot(all(focused_manifest$discrepancy.D == 2L))
stopifnot(all(focused_manifest$reference.n == 200L))
stopifnot(all(focused_manifest$discrepancy.n == 200L))
stopifnot(all(focused_manifest$reference.m == 720L))
stopifnot(all(focused_manifest$discrepancy.m == 720L))
stopifnot(as.integer(focused_space$fixed$inference$max_iter) == 150L)
stopifnot(as.integer(focused_space$fixed$inference$max_iter_hard_cap) == 150L)
stopifnot(as.integer(focused_space$scheduler$max_parallel) == 20L)
focused_block <- focused_manifest$candidate_role == "block_specific_alpha_refinement"
stopifnot(all(focused_manifest$reference.alpha[focused_block] != focused_manifest$discrepancy.alpha[focused_block]))
stopifnot(!any(app_as_bool_vec(focused_manifest$require_linked_desn[focused_block])))
stopifnot(all(is.na(focused_manifest$warm_start_source_fit_object[
  focused_manifest$warm_start_policy == "cold"
])))
stopifnot(all(nzchar(focused_manifest$warm_start_source_fit_object[
  focused_manifest$warm_start_policy == "auto"
])))

structural_definition <- app_read_yaml(app_path(
  "application/config/glofas_p50_structural_memory_geometry_20260821.yaml"
))
structural_anchor_fixture <- list(
  candidate_id = "block_alpha_refinement_019_b1b26b2d8e",
  ranking_path = "/tmp/structural_ranking.csv",
  config_path = "/tmp/structural_anchor_config.yaml",
  fit_object_path = "/tmp/structural_anchor_fit.rds"
)
structural_space <- app_glofas_median_structural_space(
  structural_definition,
  anchor = structural_anchor_fixture
)
structural_manifest <- app_glofas_median_screen_candidate_manifest(structural_space)
structural_manifest_again <- app_glofas_median_screen_candidate_manifest(structural_space)
stopifnot(nrow(structural_manifest) == 48L)
stopifnot(identical(structural_manifest$candidate_id, structural_manifest_again$candidate_id))
stopifnot(!anyDuplicated(structural_manifest$candidate_id))
stopifnot(!anyDuplicated(structural_manifest$candidate_label))
stopifnot(sum(structural_manifest$warm_start_policy == "cold") == 1L)
stopifnot(sum(structural_manifest$warm_start_policy == "auto") == 47L)
stopifnot(all(is.na(structural_manifest$warm_start_source_fit_object[
  structural_manifest$warm_start_policy == "cold"
])))
stopifnot(all(nzchar(structural_manifest$warm_start_source_fit_object[
  structural_manifest$warm_start_policy == "auto"
])))
structural_role_expected <- c(
  structural_repeatability_control = 2L,
  symmetric_memory_direct_profile = 13L,
  symmetric_architecture_profile = 14L,
  architecture_memory_interaction = 6L,
  block_specific_architecture_profile = 6L,
  block_specific_memory_profile = 7L
)
structural_role_observed <- table(structural_manifest$candidate_role)
stopifnot(identical(
  as.integer(structural_role_observed[names(structural_role_expected)]),
  unname(structural_role_expected)
))
stopifnot(as.integer(structural_space$fixed$inference$max_iter) == 150L)
stopifnot(as.integer(structural_space$fixed$inference$max_iter_hard_cap) == 150L)
stopifnot(as.integer(structural_space$scheduler$max_parallel) == 20L)
stopifnot(!any(app_as_bool_vec(structural_manifest$require_linked_desn)))
stopifnot(max(as.integer(structural_manifest$reference.D)) == 8L)
stopifnot(max(as.integer(structural_manifest$reference.n)) == 500L)
stopifnot(max(as.integer(structural_manifest$reference.m)) == 1080L)
stopifnot(all(
  as.integer(structural_manifest$reference.reservoir_output_lag_max) ==
    as.integer(structural_manifest$reference.m)
))
stopifnot(all(
  as.integer(structural_manifest$discrepancy.reservoir_covariate_lag_max) ==
    as.integer(structural_manifest$discrepancy.m)
))
for (block in c("reference", "discrepancy")) {
  D <- as.integer(structural_manifest[[paste0(block, ".D")]])
  n <- as.integer(structural_manifest[[paste0(block, ".n")]])
  n_tilde <- as.integer(structural_manifest[[paste0(block, ".n_tilde")]])
  stopifnot(all(is.na(n_tilde[D == 1L])))
  stopifnot(all(n_tilde[D > 1L] == n[D > 1L]))
}
structural_anchor_rows <- structural_manifest$candidate_role == "structural_repeatability_control"
stopifnot(all(structural_manifest$reference.alpha[structural_anchor_rows] == 0.10))
stopifnot(all(structural_manifest$discrepancy.alpha[structural_anchor_rows] == 0.075))
stopifnot(all(structural_manifest$reference.rhs_tau0[structural_anchor_rows] == 0.10))
stopifnot(all(structural_manifest$discrepancy.rhs_tau0[structural_anchor_rows] == 1e-4))
asymmetric_row <- structural_manifest[
  structural_manifest$candidate_label == "ref_d1n350_disc_d2n200",
  , drop = FALSE
]
stopifnot(nrow(asymmetric_row) == 1L)
stopifnot(as.integer(asymmetric_row$reference.D) == 1L)
stopifnot(as.integer(asymmetric_row$reference.n) == 350L)
stopifnot(as.integer(asymmetric_row$discrepancy.D) == 2L)
stopifnot(as.integer(asymmetric_row$discrepancy.n) == 200L)

cleanup_existing <- data.frame(
  candidate_id = c("a", "b"),
  path = c("/tmp/a.rds", "/tmp/b.rds"),
  action = c("delete_candidate", "keep_protected"),
  executed = c(TRUE, FALSE),
  stringsAsFactors = FALSE
)
cleanup_current <- data.frame(
  candidate_id = c("a", "c"),
  path = c("/tmp/a.rds", "/tmp/c.rds"),
  action = c("delete_candidate", "delete_candidate"),
  executed = c(FALSE, TRUE),
  stringsAsFactors = FALSE
)
cleanup_merged <- app_glofas_median_screen_merge_cleanup_reports(
  cleanup_existing,
  cleanup_current
)
stopifnot(nrow(cleanup_merged) == 3L)
stopifnot(isTRUE(cleanup_merged$executed[cleanup_merged$candidate_id == "a"][[1L]]))
stopifnot(identical(cleanup_merged$candidate_id, c("a", "b", "c")))
stopifnot(identical(
  app_glofas_median_screen_merge_cleanup_reports(data.frame(), cleanup_existing),
  cleanup_existing
))
stopifnot(identical(
  app_glofas_median_screen_merge_cleanup_reports(cleanup_existing, data.frame()),
  cleanup_existing
))

cleanup_existing_path <- tempfile("cleanup_existing_", fileext = ".rds")
cleanup_missing_path <- tempfile("cleanup_missing_", fileext = ".rds")
saveRDS(1, cleanup_existing_path)
cleanup_dry_run <- data.frame(
  candidate_id = c("kept", "deleted"),
  path = c(cleanup_existing_path, cleanup_missing_path),
  action = c("keep_protected", "delete_candidate"),
  executed = FALSE,
  stringsAsFactors = FALSE
)
cleanup_recovered <- app_glofas_median_screen_recover_cleanup_dry_run(cleanup_dry_run)
stopifnot(!cleanup_recovered$executed[cleanup_recovered$candidate_id == "kept"])
stopifnot(cleanup_recovered$executed[cleanup_recovered$candidate_id == "deleted"])
unlink(cleanup_existing_path)

finalizer_lines <- readLines(app_path(
  "application/scripts/glofas_constrained_median_screen_finalize.R"
))
artifact_source_line <- grep("artifact_hygiene[.]R", finalizer_lines)
recovery_source_line <- grep("glofas_fit_recovery[.]R", finalizer_lines)
stopifnot(length(artifact_source_line) == 1L)
stopifnot(length(recovery_source_line) == 1L)
stopifnot(artifact_source_line < recovery_source_line)
stopifnot(any(grepl("finalization_status[.]csv", finalizer_lines)))

interaction_a <- app_glofas_median_campaign_maximin_pairs(
  campaign_definition$campaign$support$alpha,
  campaign_definition$campaign$support$rho,
  0.20, 0.95, 12L
)
interaction_b <- app_glofas_median_campaign_maximin_pairs(
  campaign_definition$campaign$support$alpha,
  campaign_definition$campaign$support$rho,
  0.20, 0.95, 12L
)
stopifnot(identical(interaction_a, interaction_b))
stopifnot(nrow(interaction_a) == 12L)
stopifnot(!any(interaction_a$alpha == 0.20))
stopifnot(!any(interaction_a$rho == 0.95))

treatment_space <- screen_space
treatment_space$candidate_sets <- list()
treatment_space$explicit_candidates <- list(
  list(
    set_id = "warm",
    parameters = list(reference = list(alpha = 0.1)),
    metadata = list(warm_start_policy = "auto")
  ),
  list(
    set_id = "cold",
    parameters = list(reference = list(alpha = 0.1)),
    metadata = list(warm_start_policy = "cold")
  )
)
treatment_manifest <- app_glofas_median_screen_candidate_manifest(treatment_space)
stopifnot(nrow(treatment_manifest) == 2L)
