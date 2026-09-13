#!/usr/bin/env Rscript

if (!exists("app_joint_article_read_contract", mode = "function") ||
    !exists("app_joint_article_score_read_contract", mode = "function")) {
  file_arg <- sub(
    "^--file=", "",
    commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]
  )
  repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."),
    mustWork = TRUE)
  source(file.path(repo_root, "application", "scripts",
    "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))
}

v2 <- app_joint_article_read_contract(
  app_joint_article_corrected_contract_path())
v3 <- app_joint_article_read_contract(
  app_joint_article_muscat_corrected_contract_path())
score_v2 <- app_joint_article_score_read_contract(
  app_joint_article_corrected_score_contract_path())
score_v3 <- app_joint_article_score_read_contract(
  app_joint_article_muscat_corrected_score_contract_path())

changed_rows <- function(old, new) {
  common <- intersect(old$name, new$name)
  common[vapply(common, function(name) {
    old_row <- old[old$name == name, , drop = FALSE]
    new_row <- new[new$name == name, , drop = FALSE]
    rownames(old_row) <- NULL
    rownames(new_row) <- NULL
    !identical(old_row, new_row)
  }, logical(1L))]
}

allowed_changed <- c(
  "contract_version", "run_tag", "execution_branch", "host_profile_id",
  "source_worktree", "initial_concurrency", "maximum_concurrency"
)
allowed_added <- c(
  "cpu_affinity_list", "required_physical_cores",
  "capacity_approval_token"
)
stopifnot(
  setequal(changed_rows(v2$table, v3$table), allowed_changed),
  setequal(setdiff(v3$table$name, v2$table$name), allowed_added),
  !length(setdiff(v2$table$name, v3$table$name)),
  identical(v3$version, "joint_shared_backbone_article_confirmation_v3"),
  identical(v3$run_tag,
    "joint_qdesn_corrected_article_comparison_muscat_25core_20260909"),
  identical(v3$execution_branch,
    "work/joint-qdesn-corrected-article-comparison-muscat-25core-20260909"),
  identical(v3$host_profile_id, "muscat_corrected_25core_20260909"),
  identical(v3$cpu_affinity_list, "0-24"),
  v3$required_physical_cores == 25L,
  identical(v3$capacity_approval_token, "MUSCAT_25_PHYSICAL_IDLE"),
  v3$initial_concurrency == 25L,
  v3$maximum_concurrency == 25L
)

score_allowed_changed <- c("contract_version", "runtime_root")
stopifnot(
  setequal(changed_rows(score_v2$table, score_v3$table),
    score_allowed_changed),
  !length(setdiff(score_v3$table$name, score_v2$table$name)),
  !length(setdiff(score_v2$table$name, score_v3$table$name)),
  identical(score_v3$version,
    "joint_qdesn_corrected_article_score_packet_v3"),
  identical(score_v3$runtime_root, file.path(
    "application", "cache",
    "joint_qdesn_corrected_article_comparison_muscat_25core_20260909"))
)

# Execution metadata cannot alter seeds or the scientific posterior/score target.
scientific_sections <- c(
  "selection", "quantile", "vb", "posterior", "mcmc", "seeds", "scoring"
)
scientific_names <- setdiff(
  v2$table$name[v2$table$section %in% scientific_sections],
  c("initial_concurrency", "maximum_concurrency")
)
v2_science <- v2$table[v2$table$name %in% scientific_names, , drop = FALSE]
v3_science <- v3$table[v3$table$name %in% scientific_names, , drop = FALSE]
rownames(v2_science) <- NULL
rownames(v3_science) <- NULL
stopifnot(identical(v2_science, v3_science))

score_science <- setdiff(score_v2$table$name, score_allowed_changed)
stopifnot(!length(changed_rows(
  score_v2$table[score_v2$table$name %in% score_science, , drop = FALSE],
  score_v3$table[score_v3$table$name %in% score_science, , drop = FALSE]
)))

scenario_id <- sprintf("scenario_%02d", seq_len(8L))
selected <- data.frame(
  scenario_order = seq_len(8L), scenario_id = scenario_id,
  article_seed = 7000L + seq_len(8L),
  candidate_id = paste0("candidate_", seq_len(8L)),
  architecture_signature = paste0("architecture_", seq_len(8L)),
  design_class = "shared_backbone", rhs_tau0 = rep(0.1, 8L),
  stringsAsFactors = FALSE
)
design_manifest <- data.frame(
  scenario_order = seq_len(8L), scenario_id = scenario_id,
  design_path = file.path(tempdir(), paste0(scenario_id, ".rds")),
  design_fingerprint = vapply(scenario_id, app_joint_qvp_sha256_text,
    character(1L)),
  p = 3L, fit_rows = 500L, validation_rows = 500L,
  scored_forecast_rows = 1000L, stringsAsFactors = FALSE
)
vb_v2 <- app_joint_article_build_vb_plan(selected, design_manifest, v2)
vb_v3 <- app_joint_article_build_vb_plan(selected, design_manifest, v3)
stopifnot(
  nrow(vb_v3) == 136L,
  identical(vb_v2$component_seed, vb_v3$component_seed),
  identical(vb_v2$depends_on, vb_v3$depends_on)
)
model_map <- app_joint_article_model_map()
future <- merge(
  data.frame(scenario_id = scenario_id, stringsAsFactors = FALSE),
  data.frame(model_id = model_map$model_id, stringsAsFactors = FALSE),
  by = NULL
)
future$fit_structure <- ifelse(grepl("independent", future$model_id),
  "independent", "joint")
future$likelihood_family <- ifelse(grepl("exqdesn", future$model_id),
  "exAL", "AL")
future$article_fixture_used_for_selection <- FALSE
cells_v2 <- app_joint_article_build_model_cells(future, design_manifest, v2)
cells_v3 <- app_joint_article_build_model_cells(future, design_manifest, v3)
mcmc_v2 <- app_joint_article_build_mcmc_plan(cells_v2, v2)
mcmc_v3 <- app_joint_article_build_mcmc_plan(cells_v3, v3)
stopifnot(
  nrow(cells_v3) == 32L,
  nrow(mcmc_v3) == 160L,
  all(table(mcmc_v3$model_cell_id) == 5L),
  identical(mcmc_v2$chain_seed, mcmc_v3$chain_seed),
  identical(mcmc_v2$chain_start_seed, mcmc_v3$chain_start_seed),
  identical(mcmc_v2$model_cell_id, mcmc_v3$model_cell_id)
)

profile <- app_joint_article_read_host_profile(v3$host_profile_id)
stopifnot(
  nrow(profile) == 1L,
  identical(profile$host[[1L]], "muscat.be.ucsc.edu"),
  identical(profile$runtime_root[[1L]], score_v3$runtime_root),
  identical(profile$source_worktree[[1L]], v3$source_worktree),
  as.integer(profile$initial_concurrency[[1L]]) == 25L,
  as.integer(profile$maximum_concurrency[[1L]]) == 25L,
  !app_as_bool_vec(profile$production_launched)[[1L]]
)

# Affinity parsing and topology must prove 25 distinct physical cores.
stopifnot(
  identical(app_joint_article_parse_cpu_list("0-2,4,6-7"),
    c(0L, 1L, 2L, 4L, 6L, 7L)),
  inherits(try(app_joint_article_parse_cpu_list("0-2,2"),
    silent = TRUE), "try-error")
)
affinity <- app_joint_article_cpu_affinity_preflight(
  v3, effective_cpu_ids = 0:24)
stopifnot(
  nrow(affinity) == 25L,
  all(affinity$verified),
  affinity$distinct_physical_cores[[1L]] == 25L,
  identical(affinity$logical_cpu, 0:24)
)
stopifnot(inherits(try(app_joint_article_cpu_affinity_preflight(
  v3, effective_cpu_ids = 0:23), silent = TRUE), "try-error"))

# The process gate excludes only the current process family.
fake_processes <- data.frame(
  pid = c(100L, 101L, 102L, 200L, 300L, 400L),
  ppid = c(1L, 100L, 1L, 1L, 1L, 1L),
  command = c(
    "current R preflight",
    "pricefm expected descendant",
    "pricefm sibling campaign",
    "pricefm unrelated campaign",
    "glofas unrelated campaign",
    "joint_qdesn_corrected_article_comparison_jerez_20260909"
  ),
  stringsAsFactors = FALSE
)
competing <- app_joint_article_competing_processes(fake_processes,
  current_pid = 100L)
stopifnot(
  length(competing) == 4L,
  any(grepl("102 pricefm", competing, fixed = TRUE)),
  any(grepl("200 pricefm", competing, fixed = TRUE)),
  any(grepl("300 glofas", competing, fixed = TRUE)),
  any(grepl("400 joint_qdesn", competing, fixed = TRUE)),
  !any(grepl("101", competing, fixed = TRUE))
)

capacity_guard <- Sys.getenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED",
  unset = NA_character_)
Sys.unsetenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED")
stopifnot(inherits(try(app_joint_article_assert_capacity_authorized(v3),
  silent = TRUE), "try-error"))
Sys.setenv(JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED =
  "MUSCAT_25_PHYSICAL_IDLE")
stopifnot(isTRUE(app_joint_article_assert_capacity_authorized(v3)))
if (is.na(capacity_guard)) {
  Sys.unsetenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED")
} else {
  Sys.setenv(JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED = capacity_guard)
}

launcher <- readLines(app_path("application/scripts",
  "launch_joint_qdesn_corrected_article_comparison_muscat.sh"), warn = FALSE)
launcher_text <- paste(launcher, collapse = "\n")
stopifnot(
  grepl("joint_qdesn_shared_backbone_article_confirmation_contract_v3.csv",
    launcher_text, fixed = TRUE),
  grepl("joint_qdesn_corrected_article_score_contract_v3.csv",
    launcher_text, fixed = TRUE),
  grepl("MUSCAT_25_PHYSICAL_IDLE", launcher_text, fixed = TRUE),
  grepl("CPU_AFFINITY=\"0-24\"", launcher_text, fixed = TRUE),
  grepl("--max-workers 25", launcher_text, fixed = TRUE),
  grepl("run_pinned_r", launcher_text, fixed = TRUE),
  !grepl("--max-workers 50", launcher_text, fixed = TRUE),
  !grepl("JEREZ_50_IDLE", launcher_text, fixed = TRUE),
  !grepl("joint_qdesn_corrected_article_comparison_jerez_20260909",
    launcher_text, fixed = TRUE)
)

cat("Muscat corrected JOINT article-comparison contract tests passed.\n")
