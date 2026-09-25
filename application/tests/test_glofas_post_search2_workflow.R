if (!exists("app_glofas_dec25_contract", mode = "function")) {
  source(app_path("application/R/glofas_dec25_final_refit_workflow.R"))
}
if (!exists("app_glofas_post_search2_read_selection", mode = "function")) {
  source(app_path("application/R/glofas_post_search2_workflow.R"))
}

selection <- data.frame(
  component = c("reference", "discrepancy"),
  candidate_id = c("search2_ref_008", "search2_dis_009"),
  canonical_seed = c(20260512L, 20261521L),
  D = 1L, n_vector = "1500", n_state_features = 1500L,
  m = 540L, output_lag_max = 540L, covariate_lag_max = c(90L, 360L),
  washout = 500L, alpha = c(0.75, 0.95), rho = c(0.60, 0.30),
  pi_w = c(0.10, 0.005), pi_in = 0.10, effective_input_gain = 0.50,
  standardize_inputs = TRUE, state_scaling = "train_zscore",
  input_bound = "none", act_f = "tanh",
  prior_id = c("cal_m025_learned", "cal_m100_fixed16"),
  prior_mode = "calibrated_m0", m0 = c(25, 100),
  rhs_zeta2_fixed = c(NA_real_, 16), rhs_a_zeta = 2, rhs_b_zeta = 4,
  mean_primary_crps = c(0.1667, 0.1353), worst_primary_crps = c(0.4828, 0.2785),
  n_folds = 6L, n_seeds = 4L, converged_cells = 24L,
  adoption_status = "adopted", stringsAsFactors = FALSE
)
path <- tempfile(fileext = ".csv")
app_write_csv(selection, path)
selected <- app_glofas_post_search2_read_selection(path)
ref <- app_glofas_post_search2_component_row(selected, "reference")
disc <- app_glofas_post_search2_component_row(selected, "discrepancy")
joint <- app_glofas_post_search2_joint_candidate(selected)
date_contract <- app_glofas_post_search2_final_design_contract(selected)
stopifnot(date_contract$panel_rows == 12995L)
stopifnot(date_contract$effective_drop == 540L)
stopifnot(date_contract$design_rows == 12455L, date_contract$stacked_rows == 24910L)
stopifnot(date_contract$design_start == as.Date("1988-11-19"))
stopifnot(date_contract$design_end == as.Date("2022-12-25"))
stopifnot(
  length(app_glofas_post_search2_validate_final_dates(
    date_contract$expected_dates,
    selected,
    "test Search-II final design"
  )$train_idx) == 12455L
)
stopifnot(ref$seed == 20260512L, disc$seed == 20261521L)
stopifnot(ref$rhs_max_iter == 200L, ref$rhs_min_iter == 200L, ref$rhs_min_beta_updates == 180L)
stopifnot(ref$state_scaling == "train_zscore", disc$state_scaling == "train_zscore")
stopifnot(ref$act_f == "tanh", ref$act_k == "identity")
stopifnot(is.na(ref$rhs_zeta2_fixed), disc$rhs_zeta2_fixed == 16)
ref_slab <- app_glofas_post_search2_quantile_slab(ref)
disc_slab <- app_glofas_post_search2_quantile_slab(disc)
stopifnot(ref_slab$policy == "learned", !ref_slab$slab_fixed, ref_slab$zeta2 == 2)
stopifnot(disc_slab$policy == "fixed", disc_slab$slab_fixed, disc_slab$zeta2 == 16)
stopifnot(joint$ref_output_lag_max == 540L, joint$disc_covariate_lag_max == 360L)
stopifnot(joint$rhs_max_iter == 200L, joint$rhs_min_iter == 200L, joint$rhs_min_beta_updates == 180L)
stopifnot(joint$ref_act_k == "identity", joint$disc_act_k == "identity")
stopifnot(!app_glofas_post_search2_needs_calibration("part1_fit", "normal_ridge"))
stopifnot(!app_glofas_post_search2_needs_calibration("part1_forecast", "normal_ridge"))
stopifnot(app_glofas_post_search2_needs_calibration("part1_fit", "normal_rhs_vb"))
stopifnot(app_glofas_post_search2_needs_calibration("part1_forecast", "normal_rhs_vb"))

ref_ridge <- list(sigma2_mean = 0.64)
disc_ridge <- list(sigma2_mean = 0.25)
calibration <- app_glofas_post_search2_calibration_record(
  selected, ref_ridge, disc_ridge,
  p_reference = 1501L, p_discrepancy = 1501L,
  n_reference = 12000L, n_discrepancy = 12000L
)
expected_ref <- 25 / (1500 - 25) * 0.8 / sqrt(12000)
expected_disc <- 100 / (1500 - 100) * 0.5 / sqrt(12000)
stopifnot(abs(calibration$rhs_tau0[calibration$component == "reference"] - expected_ref) < 1.0e-14)
stopifnot(abs(calibration$rhs_tau0[calibration$component == "discrepancy"] - expected_disc) < 1.0e-14)
joint <- app_glofas_post_search2_apply_calibration(joint, calibration)
stopifnot(joint$rhs_tau0_reference > 0, joint$rhs_tau0_discrepancy > 0)

bad <- selection
bad$canonical_seed[bad$component == "reference"] <- 99L
bad_path <- tempfile(fileext = ".csv")
app_write_csv(bad, bad_path)
stopifnot(inherits(try(app_glofas_post_search2_read_selection(bad_path), silent = TRUE), "try-error"))

search3 <- selection
search3$candidate_id <- c("search3_ref_001", "search3_dis_007")
search3$n_vector <- c("1500", "1000")
search3$n_state_features <- c(1500L, 1000L)
search3$m <- search3$output_lag_max <- c(540L, 180L)
search3$covariate_lag_max <- c(90L, 180L)
search3$alpha <- c(0.75, 0.85)
search3$rho <- c(0.60, 0.20)
search3$pi_w <- c(0.10, 0.003)
search3$effective_input_gain <- c(0.50, 0.35)
search3$prior_id <- c("search3_ref_m040_learned", "search3_dis_m060_fixed16")
search3$m0 <- c(40, 60)
search3$selection_program <- "search3_rainy_season"
search3$selection_schema_version <- "1"
search3$scientific_gate_pass <- TRUE
search3$adoption_action <- c("retain_search2_incumbent", "adopt_search3_challenger")
search3$source_head <- "fixture"
search3$candidate_manifest_sha256 <- "fixture"
search3$confirmation_aggregate_sha256 <- "fixture"
search3$adoption_decision_sha256 <- "fixture"
search3_path <- tempfile(fileext = ".csv")
app_write_csv(search3, search3_path)
selected3 <- app_glofas_post_search2_read_selection(search3_path)
stopifnot(identical(attr(selected3, "selection_program"), "search3_rainy_season"))
stopifnot(app_glofas_post_search2_component_row(selected3, "discrepancy")$n_state_features == 1000L)
stopifnot(app_glofas_post_search2_final_design_contract(selected3)$effective_drop == 540L)

bad3 <- search3
bad3$scientific_gate_pass[bad3$component == "discrepancy"] <- FALSE
bad3_path <- tempfile(fileext = ".csv")
app_write_csv(bad3, bad3_path)
stopifnot(inherits(try(app_glofas_post_search2_read_selection(bad3_path), silent = TRUE), "try-error"))
unlink(c(path, bad_path, search3_path, bad3_path))

message("GloFAS post-Search-II workflow tests passed.")
