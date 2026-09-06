source("application/R/00_packages.R")
app_set_repo_root(getwd())
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))

cfg <- list(
  data = list(transform = list(response = "identity", forecast = "identity")),
  covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
  feature_contract = list(),
  reservoir = list()
)

dates <- as.Date("2021-01-01") + 0:119
i <- seq_along(dates)
y <- sin(i / 5) + i / 100
d <- 0.15 * cos(i / 8) + 0.03 * sin(i / 3)
g <- y + d
panel <- data.frame(
  origin_date = dates,
  target_date = dates,
  horizon = 0L,
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_reference = y,
  g_glofas = g,
  y_transformed = y,
  g_transformed = g,
  split = "train",
  cutoff_id = "toy",
  ppt = cos(i / 7),
  soil = sin(i / 9),
  stringsAsFactors = FALSE
)
panel$ppt_role <- "realized_history"
panel$soil_role <- "realized_history"
timeline <- data.frame(
  date = dates,
  ppt = panel$ppt,
  soil = panel$soil,
  ppt_role = panel$ppt_role,
  soil_role = panel$soil_role,
  stringsAsFactors = FALSE
)
attr(timeline, "covariate_future_policy") <- "historical_bridge"
attr(timeline, "covariate_source_provider") <- "toy_fixture"
attr(panel, "model_covariate_timeline") <- timeline
bundle <- list(
  panel = panel,
  cutoff = data.frame(train_start = min(dates), train_end = max(dates), stringsAsFactors = FALSE)
)

winner_manifest <- data.frame(
  component = c("reference", "discrepancy"),
  stage = c("G1", "G2"),
  candidate_id = c("toy_ref_winner", "toy_disc_winner"),
  source_runtime_root = c("toy_g1", "toy_g2"),
  score_path = c("toy_g1_scores.csv", "toy_g2_scores.csv"),
  method = c("normal_rhs_vb", "normal_rhs_vb"),
  status = c("completed", "completed"),
  winner_role = c("reference", "discrepancy"),
  n_vector = c("5", "4"),
  m = c(3L, 3L),
  output_lag_max = c(3L, 3L),
  covariate_lag_max = c(2L, 2L),
  auxiliary_lag_max = c(0L, 3L),
  input_contract = c("reference_usgs_covars", "disc_covars"),
  washout = c(4L, 4L),
  alpha = c(0.2, 0.3),
  rho = c(0.9, 0.85),
  seed = c(101L, 202L),
  rhs_tau0 = c(0.1, 0.001),
  design_hash = c("refhash", "dischash"),
  frozen = c(TRUE, TRUE),
  stringsAsFactors = FALSE
)

baseline <- app_glofas_normal_part3_candidate_from_winners(
  winner_manifest,
  candidate_id = "toy_baseline",
  require_frozen = TRUE
)
baseline$validation_n <- 8L
baseline_design <- app_glofas_normal_part3_build_design(cfg, baseline, panel_bundle = bundle)
baseline_ref_inputs <- baseline_design$reference$component_design$design_meta$reservoir_input_columns
baseline_disc_inputs <- baseline_design$discrepancy$component_design$design_meta$reservoir_input_columns
stopifnot(!any(grepl("^glofas_lag_", baseline_ref_inputs)))
stopifnot(!any(grepl("^glofas_lag_", baseline_disc_inputs)))

challenger <- app_glofas_normal_part3_cross_input_challenger_candidate(
  winner_manifest,
  candidate_id = "toy_cross_input",
  require_frozen = TRUE,
  extension_seed = 909L
)
challenger$validation_n <- 8L
challenger$rhs_max_iter <- 23L
challenger$rhs_min_iter <- 1L
challenger$rhs_tol <- 1.0e9
challenger$rhs_freeze_beta_warmup_iters <- 20L
challenger$rhs_min_beta_updates <- 3L

stopifnot(identical(challenger$part3_input_contract[[1L]], app_glofas_normal_part3_cross_input_contract_id()))
stopifnot(identical(challenger$ref_input_contract[[1L]], "reference_glofas_covars"))
stopifnot(identical(challenger$disc_input_contract[[1L]], "disc_glofas_covars"))
stopifnot(challenger$ref_win_preserve_m_input[[1L]] == 9L)
stopifnot(challenger$disc_win_preserve_m_input[[1L]] == 9L)

design <- app_glofas_normal_part3_build_design(cfg, challenger, panel_bundle = bundle)
audit <- app_glofas_normal_part3_validate_cross_input_design(design, challenger)
input_info <- app_bind_rows_fill(list(
  design$reference$component_design$design_meta$reservoir_input_info[,
    c("input_block", "variable", "lag"),
    drop = FALSE
  ],
  design$discrepancy$component_design$design_meta$reservoir_input_info[,
    c("input_block", "variable", "lag"),
    drop = FALSE
  ]
))
stopifnot(nrow(audit$input_lag_audit) == 8L)
stopifnot(all(audit$win_preservation_audit$recurrent_w_preserved))
stopifnot(all(audit$win_preservation_audit$input_weight_block_preserved))
stopifnot(all(audit$reservoir_activity$finite))
stopifnot(any(design$reference$component_design$design_meta$reservoir_input_columns == "glofas_lag_1"))
stopifnot(any(design$discrepancy$component_design$design_meta$reservoir_input_columns == "glofas_lag_1"))
stopifnot(!any(grepl("discrepancy_lag_", design$reference$component_design$design_meta$reservoir_input_columns)))
stopifnot(!any(grepl("usgs_lag_", design$discrepancy$component_design$design_meta$reservoir_input_columns)))
stopifnot(!any(grepl("^direct_", as.character(design$feature_info$block))))
stopifnot(!identical(design$design_hash[["part3_stacked_full"]], baseline_design$design_hash[["part3_stacked_full"]]))
stopifnot(identical(ncol(design$H), ncol(baseline_design$H)))
stopifnot(max(abs(design$y_reference + design$d_g - design$g_retrospective)) < 1.0e-12)
stopifnot(!any(input_info$input_block %in% c("output_lag", "auxiliary_lag") & input_info$lag == 0L))

ridge <- app_glofas_normal_part3_fit_ridge(cfg, challenger, panel_bundle = bundle)
stopifnot(identical(ridge$summary$status[[1L]], "completed"))
rhs_progress <- tempfile(fileext = ".csv")
rhs <- app_glofas_normal_part3_fit_rhs(
  cfg,
  challenger,
  panel_bundle = bundle,
  warm_start = ridge$warm_start,
  progress_path = rhs_progress,
  progress_every = 1L
)
stopifnot(inherits(rhs$fit, "glofas_normal_part3_rhs_vb_fit"))
stopifnot(nrow(rhs$trace) == 23L)
stopifnot(!any(rhs$trace$beta_updated[rhs$trace$iter <= 20L]))
stopifnot(all(rhs$trace$beta_updated[rhs$trace$iter >= 21L]))
stopifnot(rhs$trace$beta_update_count[[23L]] == 3L)
stopifnot(is.finite(rhs$summary$corrected_valid_mean_crps[[1L]]))
stopifnot(file.exists(rhs_progress))

cat("test_glofas_part3_cross_input_challenger: OK\n")
