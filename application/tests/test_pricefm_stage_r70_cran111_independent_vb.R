args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)

runtime_root <- paste0(
  "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/",
  "runtime_libraries/exdqlm_cran_1p1p1"
)
runtime_manifest <- file.path(runtime_root, "pricefm_r67_cran111_install_manifest.json")
runner <- file.path(root, "application/scripts/pricefm/238_run_pricefm_stage_r70_cran111_independent_vb_case.R")
stopifnot(file.exists(runtime_manifest), file.exists(runner))

tmp <- tempfile("pricefm_r70_preflight_")
dir.create(tmp)
config <- file.path(tmp, "case.yaml")
yaml::write_yaml(list(
  pricefm_desn_smoke = list(
    data_config = file.path(tmp, "data.yaml"),
    python_bin = "/usr/bin/python3.11",
    r_library = runtime_root,
    runtime_manifest = runtime_manifest,
    runtime_adapter_script = file.path(root, "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"),
    package_authority = "exact_CRAN_exdqlm_1.1.1_public_API",
    region = "AA",
    fold = 1L,
    splits = c("train", "val"),
    horizons = c(1L, 2L),
    quantiles = c(0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90),
    feature_policy = "target_only",
    adapter = list(output_dir = file.path(tmp, "adapter"), feature_map = "window_reservoir_v1"),
    run = list(output_dir = file.path(tmp, "model"), seed = 70L),
    rhs_ns = list(tau0 = 0.001, shrink_intercept = FALSE),
    qdesn_vb = list(
      likelihoods = c("al", "exal"),
      public_api = "exalStaticLDVB",
      max_iter = 5L,
      tol = 1e-4,
      n_samp = 5L,
      n_samp_xi = 5L,
      fork_only_namespace_calls_authorized = FALSE,
      sigmagam = list(
        factorization = "structured",
        structured_grid_size = 21L,
        structured_span_sd = 3,
        freeze_warmup_iters = 1L,
        force_after_warmup = TRUE,
        postwarmup_damping = 0.2,
        postwarmup_damping_iters = 2L,
        min_postwarmup_updates = 1L
      )
    )
  ),
  pricefm_stage_r69b = list(
    stage = "R69B",
    tag = "fixture",
    case_id = "case_fixture",
    selected_family_anchor = "exal",
    refit_priority = "priority_0_near_miss",
    method_ids = list(
      al = "qdesn_al_rhs_ns_cran111_r69b",
      exal = "qdesn_exal_rhs_ns_cran111_r69b"
    ),
    launch_authorized = FALSE,
    launcher_invoked_by_prep = FALSE,
    test_access_authorized = FALSE,
    registry_mutation_authorized = FALSE,
    article_mutation_authorized = FALSE,
    joint_model_authorized = FALSE,
    mcmc_authorized = FALSE
  )
), config)

out <- system2(
  "Rscript",
  c(runner, "--case-config", config, "--preflight-only", "true"),
  stdout = TRUE,
  stderr = TRUE
)
status <- attr(out, "status")
if (!is.null(status) && status != 0L) {
  cat(out, sep = "\n")
  stop("R70 preflight runner failed.", call. = FALSE)
}
payload <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = TRUE)
stopifnot(
  identical(as.character(payload$status), "r70_case_preflight_passed"),
  identical(as.character(payload$package_version), "1.1.1"),
  identical(as.character(payload$package_repository), "CRAN"),
  identical(as.character(payload$public_api), "exalStaticLDVB"),
  identical(isTRUE(payload$test_loaded), FALSE),
  identical(isTRUE(payload$binary_model_artifacts_written), FALSE)
)

cat("PriceFM Stage-R70 CRAN 1.1.1 preflight test passed.\n")
