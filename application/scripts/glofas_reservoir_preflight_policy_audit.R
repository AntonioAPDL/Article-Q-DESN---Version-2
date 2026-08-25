#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/model_contract.R"))

args <- app_parse_args(list(
  output_root = "",
  audit_root = "",
  relative_rank_reject = 0.05,
  saturation_reject = 0.30,
  dead_fraction_reject = 0.30,
  condition_z_reject = 1.0e6,
  condition_cov_reject = 1.0e12
))
if (!nzchar(as.character(args$output_root %||% ""))) {
  stop("--output_root is required.", call. = FALSE)
}
output_root <- app_resolve_path(args$output_root, must_work = TRUE)
audit_root <- if (nzchar(as.character(args$audit_root %||% ""))) {
  app_resolve_path(args$audit_root, must_work = FALSE)
} else {
  file.path(output_root, "reservoir_preflight_policy_audit")
}
app_ensure_dir(audit_root)
manifest <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
required <- c(
  "candidate_id", "candidate_role", "reservoir_preflight_enabled",
  "reservoir_preflight_summary_path"
)
missing <- setdiff(required, names(manifest))
if (length(missing)) {
  stop(sprintf("Runtime manifest lacks preflight fields: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}
enabled <- app_as_bool_vec(manifest$reservoir_preflight_enabled)
manifest <- manifest[enabled, , drop = FALSE]

state_rows <- list()
seed_rows <- list()
for (i in seq_len(nrow(manifest))) {
  table_dir <- dirname(as.character(manifest$reservoir_preflight_summary_path[[i]]))
  state_path <- file.path(table_dir, "reservoir_screening_state_diagnostics.csv")
  seed_path <- file.path(table_dir, "reservoir_screening_seed_reports.csv")
  if (!file.exists(state_path) || !file.exists(seed_path)) next
  state <- app_read_csv(state_path)
  state$candidate_id <- as.character(manifest$candidate_id[[i]])
  state$candidate_role <- as.character(manifest$candidate_role[[i]])
  state$source_path <- state_path
  state$source_sha256 <- app_sha256_file(state_path)
  state_rows[[length(state_rows) + 1L]] <- state
  seed <- app_read_csv(seed_path)
  seed$candidate_id <- as.character(manifest$candidate_id[[i]])
  seed$candidate_role <- as.character(manifest$candidate_role[[i]])
  seed$source_path <- seed_path
  seed$source_sha256 <- app_sha256_file(seed_path)
  seed_rows[[length(seed_rows) + 1L]] <- seed
}
states <- app_bind_rows_fill(state_rows)
seeds <- app_bind_rows_fill(seed_rows)
if (!nrow(states) || !nrow(seeds)) stop("No completed reservoir preflight evidence was found.", call. = FALSE)

states$effective_rank_entropy_reconstructed <- as.numeric(states$relative_effective_rank_entropy) *
  pmin(as.numeric(states$n_samples_after_washout), as.numeric(states$n_features_after_dead_removal))
states$effective_rank_participation_reconstructed <- as.numeric(states$relative_effective_rank_participation) *
  pmin(as.numeric(states$n_samples_after_washout), as.numeric(states$n_features_after_dead_removal))
control <- states[grepl("control", states$candidate_role, ignore.case = TRUE), , drop = FALSE]
control_reference <- if (nrow(control)) {
  stats::aggregate(
    cbind(
      effective_rank_entropy_reconstructed,
      effective_rank_participation_reconstructed
    ) ~ semantic_block,
    control,
    stats::median,
    na.rm = TRUE
  )
} else data.frame()
if (nrow(control_reference)) {
  states$control_effective_rank_entropy <- control_reference$effective_rank_entropy_reconstructed[
    match(states$semantic_block, control_reference$semantic_block)
  ]
  states$effective_rank_entropy_ratio_to_control <- states$effective_rank_entropy_reconstructed /
    states$control_effective_rank_entropy
} else {
  states$control_effective_rank_entropy <- NA_real_
  states$effective_rank_entropy_ratio_to_control <- NA_real_
}

candidate_rows <- lapply(split(states, states$candidate_id), function(x) {
  seed <- seeds[seeds$candidate_id == x$candidate_id[[1L]], , drop = FALSE]
  low_rank <- any(
    is.finite(as.numeric(x$relative_effective_rank_entropy)) &
      as.numeric(x$relative_effective_rank_entropy) < as.numeric(args$relative_rank_reject)
  )
  saturation <- any(
    is.finite(as.numeric(x$saturation_fraction)) &
      as.numeric(x$saturation_fraction) > as.numeric(args$saturation_reject)
  )
  dead <- any(
    is.finite(as.numeric(x$dead_fraction)) &
      as.numeric(x$dead_fraction) > as.numeric(args$dead_fraction_reject)
  )
  conditioning <- any(
    !is.finite(as.numeric(x$condition_z)) |
      as.numeric(x$condition_z) > as.numeric(args$condition_z_reject) |
      !is.finite(as.numeric(x$condition_cov)) |
      as.numeric(x$condition_cov) > as.numeric(args$condition_cov_reject)
  )
  other_hard_reject <- saturation || dead || conditioning
  v1_decision <- if (nrow(seed)) as.character(seed$decision[[1L]]) else "unknown"
  prospective_v2 <- if (other_hard_reject) {
    "reject"
  } else if (low_rank || identical(v1_decision, "repair")) {
    "repair"
  } else {
    v1_decision
  }
  data.frame(
    candidate_id = x$candidate_id[[1L]],
    candidate_role = x$candidate_role[[1L]],
    v1_decision = v1_decision,
    v1_low_relative_rank_reject = low_rank,
    v1_saturation_reject = saturation,
    v1_dead_state_reject = dead,
    v1_conditioning_reject = conditioning,
    v1_rank_only_reject = identical(v1_decision, "reject") && low_rank && !other_hard_reject,
    prospective_v2_decision = prospective_v2,
    min_relative_effective_rank_entropy = min(as.numeric(x$relative_effective_rank_entropy), na.rm = TRUE),
    min_absolute_effective_rank_entropy = min(x$effective_rank_entropy_reconstructed, na.rm = TRUE),
    min_rank_ratio_to_control = if (any(is.finite(x$effective_rank_entropy_ratio_to_control))) {
      min(x$effective_rank_entropy_ratio_to_control, na.rm = TRUE)
    } else NA_real_,
    cheap_validation_ran = nrow(seed) && any(is.finite(as.numeric(seed$cheap_validation_score))),
    stringsAsFactors = FALSE
  )
})
candidate_audit <- app_bind_rows_fill(candidate_rows)
cause_counts <- data.frame(
  cause = c(
    "rank_only", "saturation_only", "rank_and_saturation",
    "dead_states", "conditioning", "combined_or_other"
  ),
  candidates = c(
    sum(candidate_audit$v1_rank_only_reject),
    sum(candidate_audit$v1_saturation_reject & !candidate_audit$v1_low_relative_rank_reject),
    sum(candidate_audit$v1_saturation_reject & candidate_audit$v1_low_relative_rank_reject),
    sum(candidate_audit$v1_dead_state_reject),
    sum(candidate_audit$v1_conditioning_reject),
    sum(
      candidate_audit$v1_decision == "reject" &
        !candidate_audit$v1_rank_only_reject &
        !candidate_audit$v1_saturation_reject &
        !candidate_audit$v1_dead_state_reject &
        !candidate_audit$v1_conditioning_reject
    )
  ),
  stringsAsFactors = FALSE
)
policy <- data.frame(
  policy_version = c("reservoir_preflight_v1_frozen", "reservoir_preflight_v2_proposed"),
  low_relative_rank_action = c("reject", "repair"),
  absolute_effective_rank_reported = c(FALSE, TRUE),
  anchor_relative_rank_reported = c(FALSE, TRUE),
  chronological_cheap_validation = c(FALSE, TRUE),
  applies_to_current_campaign = c(TRUE, FALSE),
  interpretation = c(
    "Preserve every recorded decision without reinterpretation.",
    "Prospective policy: low relative rank alone requests repair; saturation, dead states, conditioning, forgetting, and nonfinite failures remain hard gates."
  ),
  stringsAsFactors = FALSE
)

outputs <- list(
  state_diagnostics_augmented = states,
  candidate_policy_audit = candidate_audit,
  hard_reject_cause_counts = cause_counts,
  control_rank_reference = control_reference,
  prospective_policy = policy
)
for (name in names(outputs)) {
  app_write_csv(outputs[[name]], file.path(audit_root, paste0(name, ".csv")))
}
paths <- file.path(audit_root, paste0(names(outputs), ".csv"))
app_write_csv(data.frame(
  path = paths,
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(audit_root, "audit_manifest.csv"))
app_write_csv(data.frame(
  status = "completed",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  candidates_audited = nrow(candidate_audit),
  v1_rejections = sum(candidate_audit$v1_decision == "reject"),
  v1_rank_only_rejections = sum(candidate_audit$v1_rank_only_reject),
  v2_is_prospective_only = TRUE,
  current_decisions_changed = FALSE,
  stringsAsFactors = FALSE
), file.path(audit_root, "audit_status.csv"))

cat(file.path(audit_root, "candidate_policy_audit.csv"), "\n")
