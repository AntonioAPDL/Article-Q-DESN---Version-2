# Generated-only reader and admission checks. No retained payload is read and no
# scientific model is fit.
local({
  source("scripts/glofas_global_path_native_reader.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  reject <- function(expr, pattern = NULL) {
    error <- tryCatch({ force(expr); NULL }, error = function(e) e)
    ok(inherits(error, "error"))
    if (!is.null(pattern)) ok(grepl(pattern, conditionMessage(error), fixed = TRUE))
  }
  pin <- function(path, size = 100, sha = strrep("a", 64L))
    list(path = path, size_bytes = size, sha256 = sha)

  controls <- jsonlite::read_json(
    "scripts/diagnostics/glofas_global_path_native_controls.json",
    simplifyVector = FALSE)
  ok(isTRUE(ggrr_controls(controls)))
  bad_controls <- controls
  bad_controls$execution$authorized <- FALSE
  bad_controls$execution$reason <- ""
  reject(ggrr_controls(bad_controls), "explicit frozen execution admission")

  root <- "/generated/source"
  source_pins <- lapply(ggrr_sources(), function(path)
    pin(file.path(root, path)))
  source_paths <- vapply(source_pins, function(x) x$path, character(1L))
  controls_path <- file.path(root,
    "scripts/diagnostics/glofas_global_path_native_controls.json")
  budget_path <- file.path(root,
    "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json")
  controls_pin <- source_pins[[match(controls_path, source_paths)]]
  budget_pin <- source_pins[[match(budget_path, source_paths)]]
  yes <- c("allow_original_reads", "allow_prior_metadata_read",
    "allow_fresh_source_feature_replay", "allow_fixed_parameter_diagnostic",
    "allow_metadata_serialization")
  no <- c("allow_generated_RDS_read", "allow_saved_callbacks",
    "allow_parameter_optimization", "allow_model_fit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes",
    "allow_publication", "allow_authority_replacement")
  purpose <- list(schema_version = "glofas_global_path_native_purpose_v1",
    purpose = "MEDIAN_AL_FIXED_PARAMETER_GLOBAL_PATH_NO_FIT_NO_TRUTH",
    operation = "measure", nonce = strrep("a", 32L),
    expires_utc = "2100-01-01T00:00:00Z", source_root = root,
    source_commit = strrep("a", 40L), source_tree = strrep("b", 40L),
    source_files = source_pins, expected_identity = gsc_identity(),
    collection = pin("/generated/accepted_producers.json"),
    input_manifest = pin("/generated/input_manifest.csv", sha =
      gsc_identity()$input_manifest_sha256),
    design = pin("/generated/shared_truth_free_design.rds", 4014834693,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    median_model = pin("/generated/fit.rds", 137820489,
      "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881"),
    prior_receipt = pin("/generated/NATIVE_PRIOR_CONFIG_READ_RECEIPT.json"),
    acceptance_budget = budget_pin, controls = controls_pin,
    measurement_receipt = pin("/generated/GLOBAL_PATH_RECEIPT.json",
      sha = controls$authentic_measurement$receipt_sha256),
    read_budget = list(max_payload_hash_bytes = 8305310364,
      max_deserialization_bytes = 4152655182,
      max_RDS_deserializations = 2L, max_generated_RDS_deserializations = 0L,
      max_metadata_bytes = 64 * 1024^2,
      max_diagnostic_output_bytes = 48 * 1024^2),
    limits = list(cpu_seconds = 14400L, wall_seconds = 14400L,
      memory_bytes = 32 * 1024^3, output_bytes = 64 * 1024^2,
      logical_cpu = 26L), output_root = file.path(root, "local_trackers/measure"),
    metadata_scratch_root = "/generated/scratch",
    metadata_serialization = list(max_files = 64L,
      max_file_bytes = 4 * 1024^2, max_total_bytes = 32 * 1024^2),
    execution_controls = controls$execution)
  for (field in yes) purpose[[field]] <- TRUE
  for (field in no) purpose[[field]] <- FALSE
  ok(isTRUE(ggrr_scope(purpose)))
  cost <- ggrr_cost(purpose)
  ok(cost$original_RDS_deserializations == 2L &&
    cost$payload_hash_bytes == 8305310364)
  bad <- purpose
  bad$allow_truth_read <- TRUE
  reject(ggrr_scope(bad), "diagnostic-only purpose")
  bad <- purpose
  bad$read_budget$max_RDS_deserializations <- 3L
  reject(ggrr_scope(bad), "two-original")
  bad <- purpose
  bad$source_files <- bad$source_files[-1L]
  reject(ggrr_scope(bad), "source closure")

  H <- 3L
  callback <- function(path) list(reference_location = .1 + .2 * path,
    ensemble_location = -.1 + .3 * path)
  contracts <- gffd_grid("generated", .5, matrix(seq(-.2, .2, length.out = 6L),
    H, 2L), .8, .4, rep(0, H), diag(H), "generated-parameters",
    "generated-features")
  built <- list(mean = rep(0, H), covariance = diag(c(.4, .5, .6)^2),
    adapter = list(contracts = contracts, callback = callback))
  measurement <- ggrr_measure(built, controls)
  ok(nrow(measurement) == 12L && all(is.finite(measurement$total_log_density)))
  locked <- purpose$execution_controls
  locked$authorized <- FALSE
  reject(ggrr_execute(built, locked, 10L), "do not authorize execution")

  paths <- matrix(seq(-.3, .3, length.out = 12L), 4L, H)
  draw <- list(status = "REFERENCE_GATE_PASS",
    diagnostic_thresholds_passed = TRUE, evaluations = 4L,
    effective_sample_size = 4, maximum_weight = .25,
    normalized_entropy = 1, elapsed_seconds = .01,
    weights = rep(.25, 4L), log_target = rep(-1, 4L),
    log_proposal = rep(-1, 4L), paths = paths)
  result <- list(references = list(generated = list(contract = contracts[[1L]],
    importance = draw, tempered = NULL)))
  output <- ggrr_reference_outputs(result)
  ok(all(c("paths_generated__importance.csv", "reference_summary.csv") %in%
    names(output)) && all(vapply(output, is.raw, logical(1L))))
  ok(length(ggrr_sources()) == length(unique(ggrr_sources())) &&
    all(file.exists(ggrr_sources())))
  launcher <- readLines("scripts/launch_glofas_global_path_native.sh", warn = FALSE)
  ok(any(grepl("--kill-after=1s", launcher, fixed = TRUE)) &&
    any(grepl("--fsize=", launcher, fixed = TRUE)) &&
    any(grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE)))
  cat(sprintf(paste0("GLOFAS_GLOBAL_PATH_NATIVE_READER_GENERATED_PASS checks=%d ",
    "authentic_reads=0 model_runs=0\n"), checks))
})
