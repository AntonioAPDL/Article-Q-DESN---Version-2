source("application/R/00_packages.R")
app_set_repo_root(getwd())
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/glofas_part4_ensemble_likelihood_contract.R"))

part4_toy_cfg <- list(
  paths = list(
    schema = "application/manifests/expected_schema.yaml",
    input_manifest = "application/manifests/input_manifest_TEMPLATE.csv",
    cutoffs = "application/config/cutoffs_dec25.csv",
    quantile_grid = "application/config/quantile_grid.csv",
    model_grid = "application/config/model_grid_latent_path_al_vb_dec25_d3n500_tau1e3_slab1_main.csv",
    cache = "application/cache",
    runs = "application/runs",
    logs = "application/logs",
    generated_outputs = "application/outputs"
  ),
  application_model = list(contract = "latent_path_ensemble_likelihood"),
  data = list(transform = list(response = "identity", forecast = "identity")),
  covariates = list(enabled = TRUE, variables = c("ppt", "soil"), source_policy = "realized_prism_era5_only"),
  prediction = list(
    q_g_source = "posterior_model_quantile",
    prediction_unit = "posterior_draw",
    beyond_issued_horizon = "disabled"
  ),
  feature_contract = list(
    version = "0.3",
    two_block_design = TRUE,
    readout = list(
      add_intercept = TRUE,
      include_reservoir_state = TRUE,
      include_input_block = FALSE
    )
  ),
  reservoir = list(
    D = 1L,
    n = 8L,
    n_tilde = integer(0),
    m = 8L,
    washout = 4L,
    alpha = 0.2,
    rho = 0.9,
    pi_w = 0.03,
    pi_in = 1.0,
    seed = 20260512L
  ),
  inference = list(
    likelihood_family = "al",
    default_method = "vb_ld",
    vb_ld = list(
      rhs_tau0 = 0.1,
      rhs_alpha_tau0 = 0.001,
      max_iter = 3L,
      min_iter = 2L,
      tol = 0
    )
  )
)

part4_anchors <- data.frame(
  role = c("reference_anchor", "discrepancy_anchor", "historical_joint_anchor"),
  stage = c("G1", "G2", "G3"),
  candidate_id = c("g1_ref_winner", "g2_disc_winner", "g3_joint_winner"),
  source_runtime_root = c("rt_g1", "rt_g2", "rt_g3"),
  score_path = c("score_g1.csv", "score_g2.csv", "score_g3.csv"),
  method = c("normal_rhs_vb", "normal_rhs_vb", "normal_rhs_vb_joint"),
  status = c("completed", "completed", "completed"),
  n_vector = c("12", "10 x 2", "6"),
  m = c(5L, 6L, 6L),
  output_lag_max = c(5L, 6L, 6L),
  covariate_lag_max = c(3L, 4L, 4L),
  washout = c(4L, 4L, 4L),
  alpha = c("0.2", "0.3", "0.25"),
  rho = c("0.9", "0.85", "0.88"),
  seed = c(101L, 202L, 303L),
  rhs_tau0 = c(0.1, 0.001, 0.01),
  rhs_tau0_reference = c(NA, NA, 0.1),
  rhs_tau0_discrepancy = c(NA, NA, 0.001),
  design_hash = c("refhash", "dischash", "jointhash"),
  feature_hash = c("reffhash", "discfhash", "jointfhash"),
  frozen = c(TRUE, TRUE, TRUE),
  stringsAsFactors = FALSE
)

families <- app_glofas_part4_model_families()
stopifnot(nrow(families) == 6L)
stopifnot(identical(app_glofas_part4_quantile_grid(), c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)))

anchors_valid <- app_glofas_part4_validate_anchor_manifest(part4_anchors)
stopifnot(nrow(anchors_valid) == 3L)
stopifnot(identical(app_glofas_part4_parse_int_vector("10 x 2", "n"), c(10L, 10L)))

unfrozen <- part4_anchors
unfrozen$frozen[[2L]] <- FALSE
blocked_unfrozen <- tryCatch({
  app_glofas_part4_validate_anchor_manifest(unfrozen)
  FALSE
}, error = function(e) TRUE)
stopifnot(isTRUE(blocked_unfrozen))

cfg <- app_glofas_part4_config_from_anchors(
  part4_toy_cfg,
  part4_anchors,
  quantile = 0.50,
  run_label = "part4_toy_p50"
)
stopifnot(identical(app_application_model_contract(cfg), "latent_path_ensemble_likelihood"))
stopifnot(isTRUE(cfg$feature_contract$two_block_design))
stopifnot(identical(cfg$feature_contract$blocks$reference$input_stream, "reference"))
stopifnot(identical(cfg$feature_contract$blocks$discrepancy$input_stream, "discrepancy"))
stopifnot(identical(as.integer(cfg$feature_contract$blocks$reference$reservoir$n), 12L))
stopifnot(identical(as.integer(cfg$feature_contract$blocks$discrepancy$reservoir$n), c(10L, 10L)))
stopifnot(identical(as.integer(cfg$feature_contract$blocks$discrepancy$reservoir$n_tilde), 10L))
stopifnot(isFALSE(cfg$feature_contract$readout$include_input_block))
stopifnot(cfg$inference$vb_ld$rhs_tau0 == 0.1)
stopifnot(cfg$inference$vb_ld$rhs_alpha_tau0 == 0.001)

contract_checks <- app_glofas_part4_validate_no_forecast_contract(cfg)
stopifnot(all(contract_checks$status == "pass"))

bad_cfg <- cfg
bad_cfg$covariates$source_policy <- "realized_history_and_blended_gefs_forecast"
bad_source <- tryCatch({
  app_glofas_part4_validate_no_forecast_contract(bad_cfg)
  FALSE
}, error = function(e) TRUE)
stopifnot(isTRUE(bad_source))

manifest_empty <- app_glofas_part4_launch_manifest(run_label = "toy_no_anchors")
stopifnot(nrow(manifest_empty) == 18L)
stopifnot(all(grepl("^blocked", manifest_empty$status)))

manifest_ready <- app_glofas_part4_launch_manifest(
  run_label = "toy_ready",
  selected_anchor_manifest = part4_anchors,
  base_cfg = part4_toy_cfg
)
stopifnot(nrow(manifest_ready) == 18L)
stopifnot(sum(manifest_ready$status == "ready_after_operator_launch_approval") == 1L)
stopifnot(manifest_ready$status[manifest_ready$part4_family == "independent_al_rhs_vb" & manifest_ready$quantile == "0.50"] == "ready_after_operator_launch_approval")
stopifnot(sum(manifest_ready$status == "blocked_until_p50_canary_passes") == 6L)

tmp_root <- file.path(tempdir(), "glofas_part4_toy_bundle")
if (dir.exists(tmp_root)) unlink(tmp_root, recursive = TRUE)
tmp_cfg_path <- file.path(tempdir(), "part4_toy_base.yaml")
tmp_anchor_path <- file.path(tempdir(), "part4_toy_anchors.csv")
app_write_yaml(part4_toy_cfg, tmp_cfg_path)
app_write_csv(part4_anchors, tmp_anchor_path)
bundle <- app_glofas_part4_prepare_bundle(
  base_config_path = tmp_cfg_path,
  anchor_manifest_path = tmp_anchor_path,
  run_label = "part4_toy_bundle",
  runtime_root = tmp_root
)
stopifnot(file.exists(bundle$manifest_path))
stopifnot(file.exists(bundle$launch_path))
stopifnot(bundle$metadata$ready_rows == 1L)
stopifnot(bundle$metadata$blocked_rows == 17L)
health <- app_glofas_part4_check_bundle(tmp_root)
stopifnot(health$summary$value[health$summary$metric == "manifest_rows"] == 18L)
stopifnot(health$summary$value[health$summary$metric == "ready_after_operator_launch_approval"] == 1L)
stopifnot(health$summary$value[health$summary$metric == "configured_independent_al_rows"] == 7L)

script_status <- system2("bash", c("-n", shQuote(bundle$launch_path)))
stopifnot(identical(script_status, 0L))
