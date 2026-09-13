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

v3 <- app_joint_article_read_contract(
  app_joint_article_muscat_corrected_contract_path())
v4 <- app_joint_article_read_contract(
  app_joint_article_muscat_shared_contract_path())
score_v3 <- app_joint_article_score_read_contract(
  app_joint_article_muscat_corrected_score_contract_path())
score_v4 <- app_joint_article_score_read_contract(
  app_joint_article_muscat_shared_score_contract_path())

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
  "initial_concurrency", "maximum_concurrency", "cpu_affinity_list",
  "required_physical_cores", "capacity_approval_token"
)
allowed_added <- c(
  "shared_capacity_mode", "pricefm_reserved_cpu_list",
  "glofas_spare_cpu_list", "allowed_competing_process_patterns"
)
stopifnot(
  setequal(changed_rows(v3$table, v4$table), allowed_changed),
  setequal(setdiff(v4$table$name, v3$table$name), allowed_added),
  !length(setdiff(v3$table$name, v4$table$name)),
  identical(v4$version, "joint_shared_backbone_article_confirmation_v4"),
  identical(v4$run_tag,
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909"),
  identical(v4$execution_branch,
    "work/joint-qdesn-corrected-article-comparison-muscat-11core-20260909"),
  identical(v4$host_profile_id, "muscat_corrected_11core_20260909"),
  identical(v4$cpu_affinity_list, "1-9,16,24"),
  v4$required_physical_cores == 11L,
  identical(v4$capacity_approval_token, "MUSCAT_11_PHYSICAL_SHARED"),
  identical(v4$shared_capacity_mode, "pricefm_r97_glofas_part4"),
  identical(v4$pricefm_reserved_cpu_list, "42-47,49-55,57-63"),
  identical(v4$glofas_spare_cpu_list, "0,32"),
  identical(v4$allowed_competing_process_patterns,
    c("pricefm_stage_r97", "glofas_part4_joint_convergence_closeout_20260907")),
  v4$initial_concurrency == 11L,
  v4$maximum_concurrency == 11L
)

score_allowed_changed <- c("contract_version", "runtime_root")
stopifnot(
  setequal(changed_rows(score_v3$table, score_v4$table),
    score_allowed_changed),
  !length(setdiff(score_v4$table$name, score_v3$table$name)),
  !length(setdiff(score_v3$table$name, score_v4$table$name)),
  identical(score_v4$version,
    "joint_qdesn_corrected_article_score_packet_v4"),
  identical(score_v4$runtime_root, file.path(
    "application", "cache",
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909"))
)

# Execution metadata cannot alter seeds or the scientific posterior/score target.
scientific_sections <- c(
  "selection", "quantile", "vb", "posterior", "mcmc", "seeds", "scoring"
)
scientific_names <- setdiff(
  v3$table$name[v3$table$section %in% scientific_sections],
  c("initial_concurrency", "maximum_concurrency")
)
v3_science <- v3$table[v3$table$name %in% scientific_names, , drop = FALSE]
v4_science <- v4$table[v4$table$name %in% scientific_names, , drop = FALSE]
rownames(v3_science) <- NULL
rownames(v4_science) <- NULL
stopifnot(identical(v3_science, v4_science))

score_science <- setdiff(score_v3$table$name, score_allowed_changed)
stopifnot(!length(changed_rows(
  score_v3$table[score_v3$table$name %in% score_science, , drop = FALSE],
  score_v4$table[score_v4$table$name %in% score_science, , drop = FALSE]
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
vb_v3 <- app_joint_article_build_vb_plan(selected, design_manifest, v3)
vb_v4 <- app_joint_article_build_vb_plan(selected, design_manifest, v4)
stopifnot(
  nrow(vb_v4) == 136L,
  identical(vb_v3$component_seed, vb_v4$component_seed),
  identical(vb_v3$depends_on, vb_v4$depends_on)
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
cells_v3 <- app_joint_article_build_model_cells(future, design_manifest, v3)
cells_v4 <- app_joint_article_build_model_cells(future, design_manifest, v4)
mcmc_v3 <- app_joint_article_build_mcmc_plan(cells_v3, v3)
mcmc_v4 <- app_joint_article_build_mcmc_plan(cells_v4, v4)
stopifnot(
  nrow(cells_v4) == 32L,
  nrow(mcmc_v4) == 160L,
  all(table(mcmc_v4$model_cell_id) == 5L),
  identical(mcmc_v3$chain_seed, mcmc_v4$chain_seed),
  identical(mcmc_v3$chain_start_seed, mcmc_v4$chain_start_seed),
  identical(mcmc_v3$model_cell_id, mcmc_v4$model_cell_id)
)

profile <- app_joint_article_read_host_profile(v4$host_profile_id)
stopifnot(
  nrow(profile) == 1L,
  identical(profile$host[[1L]], "muscat.be.ucsc.edu"),
  identical(profile$runtime_root[[1L]], score_v4$runtime_root),
  identical(profile$source_worktree[[1L]], v4$source_worktree),
  as.integer(profile$initial_concurrency[[1L]]) == 11L,
  as.integer(profile$maximum_concurrency[[1L]]) == 11L,
  !app_as_bool_vec(profile$production_launched)[[1L]]
)

# Affinity parsing and topology must prove 11 distinct physical cores.
stopifnot(
  identical(app_joint_article_parse_cpu_list("0-2,4,6-7"),
    c(0L, 1L, 2L, 4L, 6L, 7L)),
  inherits(try(app_joint_article_parse_cpu_list("0-2,2"),
    silent = TRUE), "try-error")
)
affinity <- app_joint_article_cpu_affinity_preflight(
  v4, effective_cpu_ids = c(1:9, 16L, 24L))
stopifnot(
  nrow(affinity) == 11L,
  all(affinity$verified),
  affinity$distinct_physical_cores[[1L]] == 11L,
  identical(affinity$logical_cpu, c(1:9, 16L, 24L))
)
stopifnot(inherits(try(app_joint_article_cpu_affinity_preflight(
  v4, effective_cpu_ids = c(1:9, 16L)), silent = TRUE), "try-error"))

shared <- app_joint_article_shared_capacity_preflight(v4, affinity)
stopifnot(
  nrow(shared) == 1L,
  shared$joint_physical_cores[[1L]] == 11L,
  shared$pricefm_physical_cores[[1L]] == 20L,
  shared$glofas_spare_physical_cores[[1L]] == 1L,
  shared$total_physical_cores[[1L]] == 32L,
  shared$joint_pricefm_overlap[[1L]] == 0L,
  shared$joint_spare_overlap[[1L]] == 0L,
  isTRUE(shared$allocation_verified[[1L]])
)

# The process gate allows only the frozen PriceFM and GloFAS campaigns.
fake_processes <- data.frame(
  pid = c(100L, 101L, 200L, 300L, 400L, 500L),
  ppid = c(1L, 100L, 1L, 1L, 1L, 1L),
  command = c(
    "current R preflight",
    "joint expected descendant",
    "pricefm_stage_r97 authorized campaign",
    "glofas_part4_joint_convergence_closeout_20260907 authorized campaign",
    "pricefm unrelated campaign",
    "joint_qdesn_corrected_article_comparison_jerez_20260909"
  ),
  stringsAsFactors = FALSE
)
competing <- app_joint_article_competing_processes(fake_processes,
  current_pid = 100L,
  allowed_patterns = v4$allowed_competing_process_patterns)
stopifnot(
  length(competing) == 2L,
  any(grepl("400 pricefm", competing, fixed = TRUE)),
  any(grepl("500 joint_qdesn", competing, fixed = TRUE)),
  !any(grepl("200", competing, fixed = TRUE)),
  !any(grepl("300", competing, fixed = TRUE)),
  !any(grepl("101", competing, fixed = TRUE))
)

# Queue workers may exclude only their lock-authenticated execution family.
family_processes <- data.frame(
  pid = c(100L, 101L, 102L, 103L, 900L),
  ppid = c(1L, 100L, 100L, 101L, 1L),
  command = c(
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909 queue",
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909 worker 1",
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909 worker 2",
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909 child",
    "joint_qdesn_corrected_article_comparison_muscat_11core_20260909 duplicate"
  ),
  stringsAsFactors = FALSE
)
family_root <- tempfile("joint_mcmc_execution_family_")
dir.create(file.path(family_root, "mcmc_queue.lock"), recursive = TRUE)
app_write_csv(data.frame(pid = 100L, root = family_root,
  stringsAsFactors = FALSE), file.path(family_root, "mcmc_queue.lock", "owner.csv"))
family <- app_joint_article_verify_execution_family(
  family_root, processes = family_processes, current_pid = 101L,
  execution_root_pid = 100L)
stopifnot(setequal(family, c(100L, 101L, 102L, 103L)))
strict_competing <- app_joint_article_competing_processes(
  family_processes, current_pid = 101L)
stopifnot(
  any(grepl("100 .*queue", strict_competing)),
  any(grepl("102 .*worker 2", strict_competing)),
  any(grepl("900 .*duplicate", strict_competing))
)
family_competing <- app_joint_article_competing_processes(
  family_processes, current_pid = 101L, excluded_pids = family)
stopifnot(
  length(family_competing) == 1L,
  grepl("900 .*duplicate", family_competing[[1L]])
)
stopifnot(inherits(try(app_joint_article_verify_execution_family(
  family_root, processes = family_processes, current_pid = 900L,
  execution_root_pid = 100L), silent = TRUE), "try-error"))
app_write_csv(data.frame(pid = 999L, root = family_root,
  stringsAsFactors = FALSE), file.path(family_root, "mcmc_queue.lock", "owner.csv"))
stopifnot(inherits(try(app_joint_article_verify_execution_family(
  family_root, processes = family_processes, current_pid = 101L,
  execution_root_pid = 100L), silent = TRUE), "try-error"))
unlink(family_root, recursive = TRUE, force = TRUE)

if (.Platform$OS.type != "windows") {
  fork_root <- tempfile("joint_mcmc_real_fork_family_")
  dir.create(file.path(fork_root, "mcmc_queue.lock"), recursive = TRUE)
  parent_pid <- Sys.getpid()
  app_write_csv(data.frame(pid = parent_pid, root = fork_root,
    stringsAsFactors = FALSE), file.path(fork_root, "mcmc_queue.lock", "owner.csv"))
  fork_results <- parallel::mclapply(1:2, function(index) {
    ready <- file.path(fork_root, sprintf("ready_%d", Sys.getpid()))
    writeLines(as.character(Sys.getpid()), ready)
    deadline <- Sys.time() + 5
    while (length(list.files(fork_root, pattern = "^ready_")) < 2L &&
        Sys.time() < deadline) Sys.sleep(0.02)
    processes <- app_joint_article_process_table()
    family <- app_joint_article_verify_execution_family(
      fork_root, processes = processes, current_pid = Sys.getpid(),
      execution_root_pid = parent_pid)
    c(parent_present = parent_pid %in% family,
      worker_present = Sys.getpid() %in% family,
      family_size = length(family))
  }, mc.cores = 2L, mc.preschedule = FALSE)
  stopifnot(
    length(fork_results) == 2L,
    all(vapply(fork_results, function(x) all(x[1:2] == 1), logical(1L))),
    all(vapply(fork_results, function(x) x[["family_size"]] >= 3L,
      logical(1L)))
  )
  unlink(fork_root, recursive = TRUE, force = TRUE)
}

capacity_guard <- Sys.getenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED",
  unset = NA_character_)
Sys.unsetenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED")
stopifnot(inherits(try(app_joint_article_assert_capacity_authorized(v4),
  silent = TRUE), "try-error"))
Sys.setenv(JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED =
  "MUSCAT_11_PHYSICAL_SHARED")
stopifnot(isTRUE(app_joint_article_assert_capacity_authorized(v4)))
if (is.na(capacity_guard)) {
  Sys.unsetenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED")
} else {
  Sys.setenv(JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED = capacity_guard)
}

launcher <- readLines(app_path("application/scripts",
  "launch_joint_qdesn_corrected_article_comparison_muscat_11core.sh"),
  warn = FALSE)
launcher_text <- paste(launcher, collapse = "\n")
stopifnot(
  grepl("joint_qdesn_shared_backbone_article_confirmation_contract_v4.csv",
    launcher_text, fixed = TRUE),
  grepl("joint_qdesn_corrected_article_score_contract_v4.csv",
    launcher_text, fixed = TRUE),
  grepl("MUSCAT_11_PHYSICAL_SHARED", launcher_text, fixed = TRUE),
  grepl("CPU_AFFINITY=\"1-9,16,24\"", launcher_text, fixed = TRUE),
  grepl("--max-workers 11", launcher_text, fixed = TRUE),
  grepl("--run-all", launcher_text, fixed = TRUE),
  grepl("run_pinned_r", launcher_text, fixed = TRUE),
  !grepl("--max-workers 25", launcher_text, fixed = TRUE),
  !grepl("--max-workers 50", launcher_text, fixed = TRUE),
  !grepl("JEREZ_50_IDLE", launcher_text, fixed = TRUE),
  !grepl("joint_qdesn_corrected_article_comparison_jerez_20260909",
    launcher_text, fixed = TRUE)
)

cat("Muscat shared-capacity corrected JOINT contract tests passed.\n")
