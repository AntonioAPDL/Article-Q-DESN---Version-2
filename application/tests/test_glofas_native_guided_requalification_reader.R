local({
  source("scripts/glofas_native_guided_requalification_reader.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(x, pattern = NULL) {
    error <- tryCatch({ force(x); NULL }, error = function(e) e)
    ok(inherits(error, "error"))
    if (!is.null(pattern)) ok(grepl(pattern, conditionMessage(error), fixed = TRUE))
  }
  pin <- function(path, size = 100, sha = strrep("a", 64L))
    list(path = path, size_bytes = size, sha256 = sha)

  root <- "/generated/source"
  sources <- lapply(gngrr_sources(), function(path)
    pin(file.path(root, path)))
  paths <- vapply(sources, function(x) x$path, character(1L))
  acceptance_path <- file.path(root,
    "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json")
  guide_path <- file.path(root,
    "scripts/diagnostics/glofas_native_guided_requalification_budget.json")
  acceptance_pin <- sources[[match(acceptance_path, paths)]]
  guide_pin <- sources[[match(guide_path, paths)]]
  yes <- c("allow_original_reads", "allow_prior_metadata_read",
    "allow_fresh_source_feature_replay", "allow_target_qualification",
    "allow_metadata_serialization")
  no <- c("allow_generated_RDS_read", "allow_saved_callbacks",
    "allow_parameter_optimization", "allow_model_fit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes",
    "allow_publication", "allow_stage_f_launch",
    "allow_derived_context_serialization")
  s <- list(
    schema_version = "glofas_native_guided_requalification_purpose_v1",
    purpose = "MEDIAN_AL_GUIDED_NATIVE_REQUALIFICATION_NO_FIT_NO_TRUTH",
    nonce = strrep("a", 32L), expires_utc = "2100-01-01T00:00:00Z",
    source_root = root, source_commit = strrep("a", 40L),
    source_tree = strrep("b", 40L), source_files = sources,
    expected_identity = gsc_identity(),
    collection = pin("/generated/accepted_producers.json"),
    input_manifest = pin("/generated/runtime/manifests/input_manifest.csv",
      sha = gsc_identity()$input_manifest_sha256),
    design = pin("/generated/runtime/objects/shared_truth_free_design.rds",
      4014834693,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    median_model = pin("/generated/runtime/results/gft-al-p050/fit.rds",
      137820489,
      "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881"),
    prior_receipt = pin("/generated/NATIVE_PRIOR_CONFIG_READ_RECEIPT.json"),
    acceptance_budget = acceptance_pin, guide_budget = guide_pin,
    read_budget = list(max_payload_hash_bytes = 8305310364,
      max_deserialization_bytes = 4152655182,
      max_RDS_deserializations = 2L, max_generated_RDS_deserializations = 0L,
      max_metadata_bytes = 64 * 1024^2,
      max_qualification_output_bytes = 24 * 1024^2),
    limits = list(cpu_seconds = 28800L, wall_seconds = 28800L,
      memory_bytes = 32 * 1024^3, output_bytes = 64 * 1024^2,
      logical_cpu = 26L),
    output_root = file.path(root, "local_trackers/guided_requalification"),
    metadata_scratch_root = "/generated/scratch",
    metadata_serialization = list(max_files = 64L,
      max_file_bytes = 4 * 1024^2, max_total_bytes = 32 * 1024^2))
  for (field in yes) s[[field]] <- TRUE
  for (field in no) s[[field]] <- FALSE

  ok(isTRUE(gngrr_scope(s)))
  base <- gngrr_stage_e_view(s)
  ok(isTRUE(gnser_scope(base)))
  ok(identical(base$schema_version, "glofas_native_stage_e_purpose_v1") &&
    identical(base$purpose,
      "MEDIAN_AL_NATIVE_OPERATIONS_PRECISION_COST_NO_FIT_NO_TRUTH"))
  ok(length(base$source_files) == length(gnser_sources()) &&
    length(s$source_files) == length(gngrr_sources()))
  cost <- gnser_cost(base)
  ok(cost$original_RDS_deserializations == 2L &&
    cost$payload_hash_bytes == 8305310364)
  for (field in no) {
    bad <- s; bad[[field]] <- TRUE
    reject(gngrr_scope(bad), "qualification-only")
  }
  bad <- s; bad$allow_target_qualification <- FALSE
  reject(gngrr_scope(bad), "qualification-only")
  bad <- s; bad$read_budget$max_RDS_deserializations <- 3L
  reject(gngrr_scope(bad), "two-original")
  bad <- s; bad$limits$wall_seconds <- 28801L
  reject(gngrr_scope(bad), "eight-hour")
  bad <- s; bad$guide_budget$sha256 <- strrep("f", 64L)
  reject(gngrr_scope(bad), "frozen tracked source pin")
  bad <- s; bad$source_files <- bad$source_files[-1L]
  reject(gngrr_scope(bad), "Stage E base")
  bad <- s; bad$unexpected <- FALSE
  reject(gngrr_scope(bad), "exact guided requalification purpose")
  ok(length(gngrr_sources()) == length(unique(gngrr_sources())) &&
    all(file.exists(gngrr_sources())))
  cat(sprintf(paste0("GLOFAS_NATIVE_GUIDED_REQUALIFICATION_READER_",
    "GENERATED_PASS checks=%d authentic_reads=0 model_runs=0\n"), n))
})
