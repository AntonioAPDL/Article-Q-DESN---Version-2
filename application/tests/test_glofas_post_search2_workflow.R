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
stopifnot(ref$seed == 20260512L, disc$seed == 20261521L)
stopifnot(ref$state_scaling == "train_zscore", disc$state_scaling == "train_zscore")
stopifnot(is.na(ref$rhs_zeta2_fixed), disc$rhs_zeta2_fixed == 16)
ref_slab <- app_glofas_post_search2_quantile_slab(ref)
disc_slab <- app_glofas_post_search2_quantile_slab(disc)
stopifnot(ref_slab$policy == "learned", !ref_slab$slab_fixed, ref_slab$zeta2 == 2)
stopifnot(disc_slab$policy == "fixed", disc_slab$slab_fixed, disc_slab$zeta2 == 16)
stopifnot(joint$ref_output_lag_max == 540L, joint$disc_covariate_lag_max == 360L)

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
unlink(c(path, bad_path))

message("GloFAS post-Search-II workflow tests passed.")
