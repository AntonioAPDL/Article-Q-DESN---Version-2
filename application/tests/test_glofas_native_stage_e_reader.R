local({
  source("scripts/glofas_native_stage_e_reader.R", local = TRUE)
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
  sources <- lapply(gnser_sources(), function(path) pin(file.path(root, path)))
  budget_path <- file.path(root,
    "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json")
  budget_pin <- sources[[match(budget_path,
    vapply(sources, function(x) x$path, character(1L)))]]
  yes <- c("allow_original_reads", "allow_prior_metadata_read",
    "allow_fresh_source_feature_replay", "allow_target_qualification",
    "allow_metadata_serialization")
  no <- c("allow_generated_RDS_read", "allow_saved_callbacks",
    "allow_parameter_optimization", "allow_model_fit", "allow_truth_read",
    "allow_retuning", "allow_scoring", "allow_article_changes",
    "allow_publication", "allow_stage_f_launch",
    "allow_derived_context_serialization")
  s <- list(schema_version = "glofas_native_stage_e_purpose_v1",
    purpose = "MEDIAN_AL_NATIVE_OPERATIONS_PRECISION_COST_NO_FIT_NO_TRUTH",
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
    acceptance_budget = budget_pin,
    read_budget = list(max_payload_hash_bytes = 8305310364,
      max_deserialization_bytes = 4152655182,
      max_RDS_deserializations = 2L, max_generated_RDS_deserializations = 0L,
      max_metadata_bytes = 64 * 1024^2,
      max_qualification_output_bytes = 24 * 1024^2),
    limits = list(cpu_seconds = 28800L, wall_seconds = 28800L,
      memory_bytes = 32 * 1024^3, output_bytes = 64 * 1024^2,
      logical_cpu = 26L),
    output_root = file.path(root, "local_trackers/stage_e"),
    metadata_scratch_root = "/generated/scratch",
    metadata_serialization = list(max_files = 64L,
      max_file_bytes = 4 * 1024^2, max_total_bytes = 32 * 1024^2))
  for (field in yes) s[[field]] <- TRUE
  for (field in no) s[[field]] <- FALSE
  ok(isTRUE(gnser_scope(s)))
  cost <- gnser_cost(s)
  ok(cost$original_RDS_deserializations == 2L &&
    cost$payload_hash_bytes == 8305310364)
  for (field in no) {
    bad <- s; bad[[field]] <- TRUE
    reject(gnser_scope(bad), "qualification-only")
  }
  bad <- s; bad$allow_target_qualification <- FALSE
  reject(gnser_scope(bad), "qualification-only")
  bad <- s; bad$read_budget$max_RDS_deserializations <- 3L
  reject(gnser_scope(bad), "two-original")
  bad <- s; bad$limits$wall_seconds <- 28801L
  reject(gnser_scope(bad), "eight-hour")
  bad <- s; bad$acceptance_budget$sha256 <- strrep("f", 64L)
  reject(gnser_scope(bad), "frozen tracked source pin")
  generated <- tempfile("stage_e_post_hash_")
  writeBin(charToRaw("generated Stage E lifecycle fixture"), generated)
  generated_pin <- list(path = normalizePath(generated),
    size_bytes = unname(file.info(generated)$size),
    sha256 = unname(tools::sha256sum(generated)))
  opened <- gnser_append_attempt(list(), logical(), generated_pin,
    "generated_lifecycle_fixture")
  ok(length(opened$attempts) == 1L &&
    identical(opened$post_attempted, FALSE) && opened$index == 1L)
  opened$attempts[[1L]]$status <- "DESERIALIZED"
  closed <- gnser_post_hash_attempts(opened$attempts,
    opened$post_attempted)
  ok(identical(closed$post_attempted, TRUE) &&
    identical(closed$attempts[[1L]]$post_hash_status, "PASS") &&
    identical(closed$attempts[[1L]]$post_read_sha256,
      generated_pin$sha256))
  repeated <- gnser_post_hash_attempts(closed$attempts,
    closed$post_attempted)
  ok(identical(repeated, closed))
  malformed <- opened$post_attempted[-1L]
  reject(gnser_post_hash_attempts(opened$attempts, malformed),
    "consistent Stage E post-read ledger")
  unlink(generated)
  ok(length(gnser_sources()) == length(unique(gnser_sources())) &&
    all(file.exists(gnser_sources())))
  cat(sprintf("GLOFAS_NATIVE_STAGE_E_READER_GENERATED_PASS checks=%d authentic_reads=0 model_runs=0\n", n))
})
