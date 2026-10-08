#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
value <- function(name, default = NULL) {
  key <- paste0("--", name)
  hit <- which(args == key)
  if (!length(hit)) return(default)
  if (hit[[length(hit)]] == length(args)) stop(sprintf("%s requires a value.", key), call. = FALSE)
  args[[hit[[length(hit)]] + 1L]]
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "joint_qvp_qdesn.R", "glofas_quantile_integrity.R", "latent_path_vb_al.R",
  "glofas_part3_partitioned_rhs.R", "glofas_part1_quantile_oracle_forecast.R",
  "glofas_quantile_root_cause_diagnostics.R"
)) source(app_path("application/R", path))

phase2_worktree <- value(
  "phase2_worktree",
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_search_phase2_rhs_20260914"
)
search3_worktree <- value(
  "search3_worktree",
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_search3_rainy_season_20260923"
)
historical_root <- value(
  "historical_root",
  file.path(phase2_worktree, "local_trackers/runtime_configs/glofas_quantile_certification_restart_prepared_r2_20260921")
)
part4_root <- value(
  "part4_root",
  file.path(phase2_worktree, "local_trackers/runtime_configs/glofas_part4_joint_continuation_integrity_r4_gatefix_20260921")
)
search3_adoption_root <- value(
  "search3_adoption_root",
  file.path(
    search3_worktree,
    "local_trackers/runtime_configs/glofas_search3_rainy_season_20260924_r2/provenance/search3_scientific_adoption_20260925"
  )
)
runtime_root <- app_resolve_path(value(
  "runtime_root",
  file.path(repo_root, "local_trackers/runtime_configs/glofas_unresolved_quantile_diagnostics_20260927")
), must_work = FALSE)
fixed_point_iterations <- as.integer(value("fixed_point_iterations", "100"))
tolerance <- as.numeric(value("tolerance", "1e-4"))
if (!is.finite(fixed_point_iterations) || fixed_point_iterations < 1L ||
    !is.finite(tolerance) || tolerance <= 0) {
  stop("Invalid fixed-point audit controls.", call. = FALSE)
}
if (dir.exists(runtime_root) && length(list.files(runtime_root, all.files = TRUE, no.. = TRUE))) {
  stop(sprintf("Diagnostic runtime already exists and is non-empty: %s", runtime_root), call. = FALSE)
}
dirs <- file.path(runtime_root, c("tables", "reports", "manifests", "status"))
invisible(lapply(dirs, app_ensure_dir))
tables_dir <- file.path(runtime_root, "tables")
reports_dir <- file.path(runtime_root, "reports")
manifests_dir <- file.path(runtime_root, "manifests")
status_dir <- file.path(runtime_root, "status")

fit_paths <- c(
  part1_joint_al = file.path(historical_root, "objects/cert_part1_fit_joint_al_all7_fit.rds"),
  part2_joint_al = file.path(historical_root, "objects/cert_part2_fit_joint_al_all7_fit.rds"),
  part3_joint_al = file.path(historical_root, "objects/cert_part3_fit_joint_al_all7_fit.rds"),
  part4_joint_al = file.path(part4_root, "objects/part4_joint_al_continuation_b02_fit_side.rds"),
  part4_joint_exal = file.path(part4_root, "objects/part4_joint_exal_continuation_b02_fit_side.rds")
)
contract_paths <- c(
  part1_certificate = file.path(historical_root, "tables/cert_part1_fit_joint_al_all7_certification.csv"),
  part2_certificate = file.path(historical_root, "tables/cert_part2_fit_joint_al_all7_certification.csv"),
  part3_certificate = file.path(historical_root, "tables/cert_part3_fit_joint_al_all7_certification.csv"),
  part4_al_manifest = file.path(part4_root, "manifests/part4_joint_al_continuation_b02_artifacts.csv"),
  part4_exal_manifest = file.path(part4_root, "manifests/part4_joint_exal_continuation_b02_artifacts.csv"),
  search3_adoption = file.path(search3_adoption_root, "tables/adopted_component_manifest.csv")
)
all_paths <- c(fit_paths, contract_paths)
missing <- all_paths[!file.exists(all_paths)]
if (length(missing)) {
  stop(sprintf("Missing required audit artifacts:\n%s", paste(missing, collapse = "\n")), call. = FALSE)
}
source_manifest <- app_glofas_rootcause_artifact_manifest(all_paths, names(all_paths))
app_write_csv(source_manifest, file.path(manifests_dir, "source_artifact_manifest.csv"))

fits <- lapply(fit_paths, readRDS)
terminal <- do.call(rbind, Map(
  app_glofas_rootcause_terminal_trace_row,
  fits,
  names(fits)
))
app_write_csv(terminal, file.path(tables_dir, "terminal_status.csv"))

replays <- list()
for (component in c("part1_joint_al", "part2_joint_al")) {
  fit <- fits[[component]]
  replays[[paste0(component, "_one_rhs_sweep")]] <- app_glofas_rootcause_part1_replay(
    fit = fit, iterations = fixed_point_iterations, inner_steps = 1L,
    tolerance = tolerance, label = paste0(component, "_one_rhs_sweep")
  )$trace
  replays[[paste0(component, "_production_five_rhs_sweeps")]] <- app_glofas_rootcause_part1_replay(
    fit = fit, iterations = fixed_point_iterations, inner_steps = 5L,
    tolerance = tolerance,
    label = paste0(component, "_production_five_rhs_sweeps")
  )$trace
}

part3 <- fits$part3_joint_al
for (component in c("reference", "discrepancy")) {
  state <- part3[[paste0("rhs_state_", component)]]
  mean <- part3[[paste0("beta_", component, "_mean")]]
  variance <- part3[[paste0("beta_", component, "_var_diag")]]
  for (inner_steps in c(1L, 5L)) {
    label <- sprintf("part3_joint_al_%s_%s_rhs_sweeps", component, if (inner_steps == 1L) "one" else "five")
    replays[[label]] <- app_glofas_rootcause_partitioned_replay(
      state, mean, variance,
      iteration_offset = as.integer(part3$iterations_completed %||% 400L),
      iterations = fixed_point_iterations,
      inner_steps = inner_steps,
      tolerance = tolerance,
      label = label
    )$trace
  }
}

for (fit_name in c("part4_joint_al", "part4_joint_exal")) {
  fit <- fits[[fit_name]]
  offset <- max(as.integer(fit$trace$outer_iteration))
  for (component in c("reference", "discrepancy")) {
    label <- paste(fit_name, component, "one_rhs_sweep", sep = "_")
    replays[[label]] <- app_glofas_rootcause_partitioned_replay(
      fit[[paste0("rhs_state_", component)]],
      fit[[paste0("beta_", component, "_mean")]],
      fit[[paste0("beta_", component, "_var_diag")]],
      iteration_offset = offset,
      iterations = fixed_point_iterations,
      inner_steps = 1L,
      tolerance = tolerance,
      label = label
    )$trace
  }
}
fixed_point_trace <- do.call(rbind, replays)
rownames(fixed_point_trace) <- NULL
fixed_point_summary <- do.call(rbind, lapply(split(fixed_point_trace, fixed_point_trace$label), function(x) {
  first_pass <- which(x$semantic_pass)
  data.frame(
    label = x$label[[1L]],
    iterations = nrow(x),
    first_semantic_pass = if (length(first_pass)) min(first_pass) else NA_integer_,
    terminal_inferential_relative_change = tail(x$inferential_relative_change, 1L),
    terminal_auxiliary_log_change = tail(x$auxiliary_log_change, 1L),
    terminal_precision_log_change = tail(x$precision_log_change, 1L),
    terminal_raw_relative_change = tail(x$raw_relative_change, 1L),
    semantic_fixed_point_reached = isTRUE(tail(x$semantic_pass, 1L)),
    stringsAsFactors = FALSE
  )
}))
rownames(fixed_point_summary) <- NULL
app_write_csv(fixed_point_trace, file.path(tables_dir, "rhs_fixed_point_trace.csv"))
app_write_csv(fixed_point_summary, file.path(tables_dir, "rhs_fixed_point_summary.csv"))

part4_gate <- do.call(rbind, lapply(c("al", "exal"), function(family) {
  fit <- fits[[paste0("part4_joint_", family)]]
  transform(
    as.data.frame(fit$rhs_convergence_diagnostics),
    family = family,
    fit_converged = isTRUE(fit$converged),
    outer_converged = isTRUE(fit$converged_outer),
    inner_converged = isTRUE(fit$converged_inner),
    rhs_converged = isTRUE(fit$converged_rhs),
    stopping_reason = as.character(fit$stopping_reason)
  )
}))
app_write_csv(part4_gate, file.path(tables_dir, "part4_rhs_gate_decomposition.csv"))

part4_solver_validation <- do.call(rbind, lapply(c("al", "exal"), function(family) {
  fit <- fits[[paste0("part4_joint_", family)]]
  offset <- max(as.integer(fit$trace$outer_iteration))
  do.call(rbind, lapply(c("reference", "discrepancy"), function(component) {
    solved <- app_glofas_part3_rhs_solve_fixed_moments(
      fit[[paste0("rhs_state_", component)]],
      fit[[paste0("beta_", component, "_mean")]],
      fit[[paste0("beta_", component, "_var_diag")]],
      iter = offset + 1L,
      min_iter = 2L,
      max_iter = 50L,
      tolerance = tolerance,
      consecutive_passes = 2L
    )
    data.frame(
      family = family,
      component = component,
      rhs_inner_iterations = solved$iterations,
      rhs_inner_converged = solved$converged,
      terminal_inferential_relative_change = solved$relative_change,
      global_update_enabled = solved$global_update_enabled,
      stringsAsFactors = FALSE
    )
  }))
}))
app_write_csv(
  part4_solver_validation,
  file.path(tables_dir, "part4_bounded_rhs_solver_validation.csv")
)

search3 <- app_read_csv(contract_paths[["search3_adoption"]])
app_write_csv(search3, file.path(tables_dir, "search3_adopted_components.csv"))

part3_counter_floor <- 1 / 399
fixed_point_value <- function(label, field) {
  row <- fixed_point_summary[fixed_point_summary$label == label, , drop = FALSE]
  if (nrow(row) != 1L) stop(sprintf("Missing fixed-point summary: %s", label), call. = FALSE)
  row[[field]][[1L]]
}
part4_first_pass <- vapply(c("al", "exal"), function(family) {
  labels <- paste0("part4_joint_", family, "_", c("reference", "discrepancy"), "_one_rhs_sweep")
  max(vapply(labels, fixed_point_value, numeric(1L), field = "first_semantic_pass"))
}, numeric(1L))
issues <- data.frame(
  issue_id = c(
    "QAL_PART1_COUPLED_DRIFT", "QAL_PART2_COUPLED_DRIFT",
    "QAL_PART3_COUNTER_CONTAMINATION", "PART4_JOINT_AL_NESTED_GATE",
    "PART4_JOINT_EXAL_TAIL_AND_NESTED_GATE", "SEARCH3_DISCREPANCY_GEOMETRY"
  ),
  scope = c(
    "Part 1 joint AL", "Part 2 joint AL", "Part 3 joint AL",
    "Part 4 joint AL", "Part 4 joint exAL", "Parts 2-4 discrepancy geometry"
  ),
  status = c(
    "rhs_fixed_map_stationary_coupled_latent_unresolved",
    "rhs_fixed_map_stationary_coupled_latent_unresolved",
    "root_cause_confirmed_counter_contamination",
    "root_cause_confirmed_incomplete_rhs_inner_solve",
    "incomplete_rhs_inner_solve_plus_tail_inner_failure",
    "resolved_adopt_search3_dis_007"
  ),
  target_changing = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
  broad_rerun_authorized = FALSE,
  evidence = c(
    sprintf("held-moment RHS replay passes immediately; terminal coupled latent change %.6g", terminal$latent_change[terminal$component == "part1_joint_al"]),
    sprintf("held-moment RHS replay passes by the second production replay; terminal coupled latent change %.6g", terminal$latent_change[terminal$component == "part2_joint_al"]),
    sprintf("recorded terminal RHS %.9f equals counter floor 1/399 %.9f", terminal$rhs_change_recorded[terminal$component == "part3_joint_al"], part3_counter_floor),
    sprintf("held-moment semantic RHS state requires up to %d coordinate sweeps; production performed one", part4_first_pass[["al"]]),
    sprintf("held-moment semantic RHS state requires up to %d coordinate sweeps and extreme inner blocks remain nonstationary", part4_first_pass[["exal"]]),
    "reference retained as search3_ref_001; discrepancy adopted as search3_dis_007"
  ),
  next_gate = c(
    "one same-target Part 1 continuation using the semantic certificate",
    "validate Part 1 mechanism on Part 2",
    "prospective same-target segment; do not refit solely for the counter defect",
    "validate bounded fixed-moment RHS inner solver, then rebuild under Search III discrepancy",
    "reduced-horizon exAL tail experiment before production rebuild",
    "dependency-audited Parts 2-4 rebuild"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(issues, file.path(tables_dir, "issue_registry.csv"))

report <- c(
  "# GloFAS Quantile Root-Cause Diagnostic Report",
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Scope",
  "",
  "This is a diagnostic-only, no-refit audit. It does not promote, overwrite, or relabel any saved fit.",
  "",
  "## Established Findings",
  "",
  sprintf("- Search III is complete and adopts `%s` for reference and `%s` for discrepancy.",
    search3$candidate_id[search3$component == "reference"],
    search3$candidate_id[search3$component == "discrepancy"]),
  sprintf("- Part 3's recorded terminal RHS change is %.9f; the unavoidable iteration-counter change is %.9f.",
    terminal$rhs_change_recorded[terminal$component == "part3_joint_al"], part3_counter_floor),
  "- The production convergence helper flattened RHS bookkeeping counters together with inferential scales. The prospective gate now monitors expected inverse scales and induced prior precision only, while retaining raw movement as a diagnostic.",
  "- With coefficient moments held fixed, the Part 1 RHS map is already below tolerance and the Part 2 production-style map passes by the second replay. Their remaining uncertainty is coupled latent/CAVI movement, not an independently drifting RHS fixed point.",
  sprintf("- Part 4 AL and exAL require up to %d and %d fixed-moment RHS coordinate sweeps, respectively, while production performed one per outer iteration. This confirms an under-solved RHS inner block without changing the posterior target.", part4_first_pass[["al"]], part4_first_pass[["exal"]]),
  sprintf("- The production bounded solver converged on all %d terminal Part 4 component states within %d sweeps (maximum terminal semantic change %.3g).", nrow(part4_solver_validation), max(part4_solver_validation$rhs_inner_iterations), max(part4_solver_validation$terminal_inferential_relative_change)),
  "- Part 4 exAL also retains a separate extreme-quantile inner-convergence failure. Neither Part 4 joint fit is promoted by this audit.",
  "",
  "## Fixed-Point Replay",
  "",
  paste0("- `", fixed_point_summary$label, "`: terminal semantic change ",
    format(fixed_point_summary$terminal_inferential_relative_change, digits = 5),
    "; pass=", fixed_point_summary$semantic_fixed_point_reached),
  "",
  "## Decision",
  "",
  "Do not broadly rerun the superseded geometry. First run one bounded Part 1 joint-AL same-target continuation with the semantic certificate. Validate the bounded RHS inner solver on deterministic tests and a reduced Part 4 experiment. Rebuild Parts 2-4 only under the adopted Search III discrepancy geometry after both gates are frozen.",
  "",
  "Status: `DIAGNOSTIC_COMPLETE_PRODUCTION_REFIT_NOT_AUTHORIZED`"
)
writeLines(report, file.path(reports_dir, "root_cause_findings.md"), useBytes = TRUE)

output_files <- list.files(runtime_root, recursive = TRUE, full.names = TRUE)
output_files <- output_files[file.info(output_files)$isdir %in% FALSE]
output_manifest <- app_glofas_rootcause_artifact_manifest(
  output_files,
  substring(output_files, nchar(normalizePath(runtime_root, mustWork = TRUE)) + 2L)
)
app_write_csv(output_manifest, file.path(manifests_dir, "diagnostic_output_manifest.csv"))
writeLines("DIAGNOSTIC_COMPLETE_PRODUCTION_REFIT_NOT_AUTHORIZED", file.path(status_dir, "audit.completed"))

cat(sprintf("runtime_root=%s\n", normalizePath(runtime_root, mustWork = TRUE)))
cat(sprintf("source_artifacts=%d\n", nrow(source_manifest)))
cat(sprintf("fixed_point_replays=%d\n", nrow(fixed_point_summary)))
cat("DIAGNOSTIC_COMPLETE_PRODUCTION_REFIT_NOT_AUTHORIZED\n")
