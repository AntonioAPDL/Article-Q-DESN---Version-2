#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/latent_path_runtime_backend.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_constrained_median_screening.R"))

args <- app_parse_args(list(
  stage_a_output_root = "local_trackers/runtime_configs/glofas_p50_linked_d1d2_stage_a_20260811",
  full_space = "application/config/glofas_p50_linked_d1d2_full_space_20260811.yaml",
  top_k = 20L,
  output_space = "",
  authorize_launch = FALSE
))

resolve_path <- function(path, must_work = FALSE) {
  if (grepl("^/", path)) normalizePath(path, mustWork = must_work) else app_resolve_path(path, must_work = must_work)
}

stage_a_root <- resolve_path(args$stage_a_output_root, must_work = TRUE)
ranking_path <- file.path(stage_a_root, "constrained_median_ranking.csv")
runtime_path <- file.path(stage_a_root, "runtime_manifest.csv")
manifest_path <- file.path(stage_a_root, "candidate_manifest.csv")
for (path in c(ranking_path, runtime_path, manifest_path)) {
  if (!file.exists(path)) stop(sprintf("Stage-A continuation requires %s.", path), call. = FALSE)
}

ranking <- app_read_csv(ranking_path)
runtime <- app_read_csv(runtime_path)
stage_a_manifest <- app_read_csv(manifest_path)
complete <- file.exists(file.path(runtime$run_dir, ".fit_recovery_complete"))
if (!all(complete)) {
  stop(sprintf("Stage A is incomplete: %d/%d candidates have completion markers.", sum(complete), length(complete)), call. = FALSE)
}

selected <- app_glofas_median_screen_select_balanced_stage_b(ranking, top_k = args$top_k)
selected <- merge(
  selected,
  runtime[, c("candidate_id", "config_path", "run_dir"), drop = FALSE],
  by = "candidate_id",
  all.x = TRUE,
  sort = FALSE
)
selected <- selected[order(selected$stage_b_selection_order), , drop = FALSE]

source_fit_path <- function(config_path, run_dir) {
  cfg <- app_read_config(config_path)
  grid <- app_read_csv(cfg$paths$model_grid)
  row <- grid[grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Expected one p50 Q-DESN row in %s.", cfg$paths$model_grid), call. = FALSE)
  path <- file.path(run_dir, "objects", paste0(row$fit_id[[1L]], ".rds"))
  if (!file.exists(path)) stop(sprintf("Stage-A source fit is missing: %s.", path), call. = FALSE)
  embedded <- app_latent_path_warm_start_contract_from_fit(path)
  if (is.null(embedded)) stop(sprintf("Stage-A source fit lacks a semantic warm-start contract: %s.", path), call. = FALSE)
  normalizePath(path, mustWork = TRUE)
}
selected$source_fit_object <- vapply(seq_len(nrow(selected)), function(i) {
  source_fit_path(selected$config_path[[i]], selected$run_dir[[i]])
}, character(1L))

full_space_path <- resolve_path(args$full_space, must_work = TRUE)
full_space <- app_glofas_median_screen_space(full_space_path)
if (app_as_bool(full_space$launch_authorized %||% FALSE)) {
  stop("The tracked full-space definition must remain launch-inert.", call. = FALSE)
}
full_manifest <- app_glofas_median_screen_candidate_manifest(full_space)
parameter_columns <- intersect(app_glofas_median_screen_parameters(), names(full_manifest))
match_fields <- c(
  "architecture_profile", "reservoir_memory_profile", "direct_memory_profile",
  "reference.alpha", "reference.rho"
)
current_prior <- "tau_current_b1em1_d1em3"
prior_ids <- setdiff(unique(as.character(full_manifest$prior_profile)), current_prior)
if (length(prior_ids) != 8L) stop("The full-space definition must contain eight non-anchor prior profiles.", call. = FALSE)

explicit <- list()
for (i in seq_len(nrow(selected))) {
  anchor <- selected[i, , drop = FALSE]
  matched <- rep(TRUE, nrow(full_manifest))
  for (field in match_fields) matched <- matched & as.character(full_manifest[[field]]) == as.character(anchor[[field]])
  variants <- full_manifest[matched & full_manifest$prior_profile %in% prior_ids, , drop = FALSE]
  variants <- variants[match(prior_ids, variants$prior_profile), , drop = FALSE]
  if (nrow(variants) != 8L || anyNA(variants$candidate_id)) {
    stop(sprintf("Could not recover eight deterministic prior variants for %s.", anchor$candidate_id), call. = FALSE)
  }
  for (j in seq_len(nrow(variants))) {
    parameters <- as.list(variants[j, parameter_columns, drop = FALSE])
    parameters <- lapply(parameters, function(x) x[[1L]])
    explicit[[length(explicit) + 1L]] <- list(
      set_id = "linked_stage_b_tau",
      candidate_label = paste(anchor$candidate_id, variants$prior_profile[[j]], sep = "__"),
      parameters = parameters,
      metadata = list(
        source_candidate_id = as.character(anchor$candidate_id),
        warm_start_source_fit_object = as.character(anchor$source_fit_object),
        warm_start_source_config = normalizePath(anchor$config_path, mustWork = TRUE)
      )
    )
  }
}

stage_b_space <- full_space
stage_b_space$version <- "1.2"
stage_b_space$screen_id <- "glofas_p50_linked_d1d2_stage_b_tau_20260811"
stage_b_space$launch_authorized <- app_as_bool(args$authorize_launch)
stage_b_space$output_root <- file.path("local_trackers", "runtime_configs", stage_b_space$screen_id)
stage_b_space$linked_factorial <- NULL
stage_b_space$candidate_sets <- list()
stage_b_space$explicit_candidates <- explicit
stage_b_space$execution$expected_candidates <- length(explicit)
stage_b_space$execution$max_candidates <- length(explicit)

output_space_value <- as.character(args$output_space %||% "")
if (!nzchar(output_space_value)) {
  continuation_root <- file.path(stage_a_root, "continuation")
  app_ensure_dir(continuation_root)
  output_space <- file.path(continuation_root, "glofas_p50_linked_d1d2_stage_b_tau_20260811.yaml")
} else {
  output_space <- resolve_path(output_space_value, must_work = FALSE)
  app_ensure_dir(dirname(output_space))
}

app_write_csv(selected, file.path(dirname(output_space), "stage_b_selected_anchors.csv"))
app_write_yaml(stage_b_space, output_space)
round_trip <- app_glofas_median_screen_candidate_manifest(app_read_yaml(output_space))
if (nrow(round_trip) != length(explicit)) stop("Stage-B YAML round-trip changed candidate cardinality.", call. = FALSE)

cat(output_space, "\n")
cat(sprintf(
  "Prepared %d prior variants from %d score-balanced Stage-A anchors; launch_authorized=%s.\n",
  nrow(round_trip), nrow(selected), app_as_bool(stage_b_space$launch_authorized)
))
