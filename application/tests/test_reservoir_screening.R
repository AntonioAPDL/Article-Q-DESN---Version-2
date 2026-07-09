cfg_screen <- app_reservoir_diagnostic_config()
stopifnot(identical(app_validate_screening_decision("pass"), "pass"))
bad_decision_msg <- tryCatch(
  {
    app_validate_screening_decision("maybe")
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("Invalid reservoir screening decision", bad_decision_msg, fixed = TRUE))

diag_report <- app_compute_layer_stability_diagnostics(
  recurrent_matrices = list(diag(c(0.2, -0.5))),
  leak_rates = 1,
  target_spectral_radii = 0.5,
  config = cfg_screen
)[[1L]]
stopifnot(inherits(diag_report, "app_layer_stability_report"))
stopifnot(abs(diag_report$actual_spectral_radius - 0.5) < 1.0e-10)
stopifnot(isTRUE(diag_report$spectral_radius_pass))

W <- diag(c(0.2, 0.4))
leak_report <- app_compute_layer_stability_diagnostics(
  recurrent_matrices = list(W),
  leak_rates = 0.5,
  target_spectral_radii = 0.4,
  config = cfg_screen
)[[1L]]
expected_leaky <- max(abs(diag((1 - 0.5) * diag(2L) + 0.5 * W)))
stopifnot(abs(leak_report$leaky_effective_spectral_radius - expected_leaky) < 1.0e-10)

nan_report <- app_compute_state_matrix_diagnostics(matrix(c(1, 2, NA, 4), ncol = 2L), config = cfg_screen)
stopifnot(identical(nan_report$decision, "reject"))
stopifnot(!isTRUE(nan_report$finite_pass))

dead_mat <- cbind(active = rnorm(30), dead = rep(3, 30), intercept = rep(1, 30))
dead_report <- app_compute_state_matrix_diagnostics(dead_mat, config = cfg_screen)
stopifnot(dead_report$n_intercept_like_features == 1L)
stopifnot(dead_report$n_dead_features == 1L)

sat_cfg <- app_reservoir_diagnostic_config(saturation_fraction_reject = 0.20)
sat_report <- app_compute_state_matrix_diagnostics(matrix(rep(0.999, 100), ncol = 5L), config = sat_cfg)
stopifnot(identical(sat_report$decision, "reject"))
stopifnot(sat_report$saturation_fraction > 0.20)

dup_x <- rnorm(80)
dup_mat <- cbind(dup_x, dup_x, rnorm(80), rnorm(80))
dup_report <- app_compute_state_matrix_diagnostics(dup_mat, config = cfg_screen)
stopifnot(is.finite(dup_report$near_duplicate_fraction))
stopifnot(dup_report$near_duplicate_fraction > 0)

set.seed(1)
ind_mat <- matrix(rnorm(200 * 5), 200, 5)
ind_report <- app_compute_state_matrix_diagnostics(ind_mat, config = cfg_screen)
stopifnot(ind_report$high_corr_fractions[["0.995"]] == 0)

selected <- app_prune_correlated_states(dup_mat, threshold = 0.95, prefer = "original_order")
stopifnot(length(selected) < ncol(dup_mat))
stopifnot(identical(selected, app_prune_correlated_states(dup_mat, threshold = 0.95, prefer = "original_order")))

rank_hi <- app_compute_state_matrix_diagnostics(matrix(rnorm(100 * 8), 100, 8), config = cfg_screen)
rank_lo <- app_compute_state_matrix_diagnostics(cbind(dup_x, dup_x, dup_x), config = cfg_screen)
stopifnot(rank_hi$relative_effective_rank_entropy > rank_lo$relative_effective_rank_entropy)

ill_base <- rnorm(100)
ill_mat <- cbind(ill_base, ill_base + rnorm(100) * 1.0e-8)
ill_cfg <- app_reservoir_diagnostic_config(condition_z_warn = 10, condition_z_reject = 100)
ill_report <- app_compute_state_matrix_diagnostics(ill_mat, config = ill_cfg)
stopifnot(ill_report$condition_z > 10)

seed_report <- app_evaluate_precomputed_states(
  states = ind_mat,
  config = cfg_screen,
  recurrent_matrices = list(diag(0.5, 5L)),
  leak_rates = 0.5,
  target_spectral_radii = 0.5,
  metadata = list(spec_id = "toy", seed = 101L)
)
stopifnot(inherits(seed_report, "app_seed_diagnostic_report"))
stopifnot(identical(seed_report$spec_id, "toy"))
stopifnot(length(seed_report$layer_reports) == 1L)

json_txt <- app_reservoir_report_to_json(seed_report)
stopifnot(grepl("\"spec_id\"", json_txt, fixed = TRUE))

fake_runner <- function(cfg, panel, model_row, cutoff_row, seed) {
  set.seed(seed)
  X <- matrix(rnorm(60 * 4), 60, 4)
  if (seed == 3L) X[1L, 1L] <- NA_real_
  list(
    X = X,
    y_fit = rnorm(60),
    reservoir = list(
      W = list(diag(0.4, 4L)),
      alpha = 0.5,
      rho = 0.4,
      seed = seed
    ),
    states = list(H_all = list(X)),
    meta = list()
  )
}
arch <- app_screen_reservoir_architecture(
  cfg = list(reservoir = list(seed = 1L)),
  panel = data.frame(y = rnorm(60)),
  model_row = data.frame(fit_id = "fake_fit", reservoir_seed = 1L),
  seeds = 1:3,
  runner = fake_runner,
  config = cfg_screen,
  metadata = list(spec_id = "fake_fit")
)
stopifnot(inherits(arch, "app_architecture_screening_report"))
stopifnot(arch$n_seeds == 3L)
stopifnot(arch$fail_rate > 0)
stopifnot(3L %in% arch$rejected_seeds)

arch_row <- app_reservoir_report_to_data_frame(arch)
stopifnot(nrow(arch_row) == 1L)
stopifnot(identical(arch_row$spec_id[[1L]], "fake_fit"))

set.seed(11)
two_block_design <- list(
  two_block_design = TRUE,
  X_core_beta = matrix(rnorm(80 * 4), 80, 4),
  X_core_alpha = matrix(rnorm(80 * 4), 80, 4),
  X_beta = cbind(1, matrix(rnorm(80 * 4), 80, 4)),
  X_alpha = cbind(1, matrix(rnorm(80 * 4), 80, 4)),
  beta_index = 1:5,
  alpha_index = 6:10,
  fit_id = "two_block_fake",
  model_id = "two_block_fake_model",
  qfit = list(y_fit = rnorm(80), reservoir = list(seed = 20260512L))
)
two_report <- app_evaluate_qdesn_design_object(
  two_block_design,
  config = cfg_screen,
  matrix_role = "both",
  metadata = list(spec_id = "two_block_fake", fit_id = "two_block_fake")
)
stopifnot(inherits(two_report, "app_seed_diagnostic_report"))
stopifnot(length(two_report$semantic_state_reports) == 4L)
stopifnot(all(c("reference_reservoir", "discrepancy_reservoir", "reference_readout", "discrepancy_readout") %in% names(two_report$semantic_state_reports)))
two_state_rows <- app_state_report_rows(two_report)
stopifnot(nrow(two_state_rows) == 4L)
stopifnot(all(c("reference", "discrepancy") %in% stats::na.omit(unique(two_state_rows$semantic_block))))

layer_cfg <- list(
  reservoir = list(
    D = 1L,
    n = 4L,
    n_tilde = integer(0),
    m = 2L,
    alpha = 0.5,
    rho = 0.4,
    pi_w = 1,
    pi_in = 1,
    act_f = "identity",
    act_k = "identity",
    seed = 11L
  )
)
layer_only <- app_evaluate_reservoir_layers_only(layer_cfg, seed = 11L, config = cfg_screen)
stopifnot(inherits(layer_only, "app_seed_diagnostic_report"))
stopifnot(identical(layer_only$state_report$matrix_role, "layers_only"))
stopifnot(length(layer_only$layer_reports) == 1L)

set.seed(42)
rep1 <- app_compute_state_matrix_diagnostics(matrix(rnorm(100), 20, 5), config = cfg_screen)
set.seed(42)
rep2 <- app_compute_state_matrix_diagnostics(matrix(rnorm(100), 20, 5), config = cfg_screen)
stopifnot(identical(rep1$decision, rep2$decision))
stopifnot(isTRUE(all.equal(rep1$condition_z, rep2$condition_z)))

toy_input <- matrix(0, 30, 1L)
toy_reservoir <- list(
  D = 1L,
  n = 1L,
  W = list(matrix(0.2, 1L, 1L)),
  Win = list(matrix(c(0, 0), nrow = 1L)),
  alpha = 0.5,
  act_f = "identity",
  act_k = "identity"
)
forget <- app_empirical_initial_condition_forgetting_test(
  input_matrix = toy_input,
  reservoir = toy_reservoir,
  meta = list(),
  config = app_reservoir_diagnostic_config(initial_forgetting_ratio_max = 0.2)
)
stopifnot(inherits(forget, "app_initial_condition_forgetting_report"))
stopifnot(isTRUE(forget$ran))
