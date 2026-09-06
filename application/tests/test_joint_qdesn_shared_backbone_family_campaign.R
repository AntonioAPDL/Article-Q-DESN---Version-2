#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "..", "scripts", "_joint_qdesn_shared_backbone_family_bootstrap.R"))

contract <- app_joint_shared_family_read_contract()
registry <- app_joint_shared_family_read_registry()
stopifnot(
  contract$article_scenarios == 8L,
  contract$campaign_scenarios == 7L,
  contract$retained_pilot_scenario == "regime_shift",
  contract$max_workers == 10L,
  nrow(registry) == 8L,
  sum(registry$enabled) == 7L,
  identical(registry$scenario_id[!registry$enabled], "regime_shift")
)

source_check <- app_joint_shared_family_validate_sources(contract, registry)
stopifnot(nrow(source_check) == 4L, all(source_check$verified))

root <- tempfile("joint_family_campaign_")
dir.create(root)
plan <- app_joint_shared_family_roots(root, registry)
stopifnot(
  nrow(plan) == 7L,
  sum(plan$ridge_jobs) == 4053L,
  sum(plan$rhs_jobs) == 3150L,
  sum(plan$quantile_jobs) == 357L,
  sum(plan$ridge_jobs + plan$rhs_jobs + plan$quantile_jobs) == 7560L,
  !any(grepl("regime_shift", plan$scenario_id, fixed = TRUE))
)

screen_tab <- app_joint_shared_family_screen_contract(
  "normal_bridge", 202610500L)
screen_path <- tempfile(fileext = ".csv")
app_write_csv(screen_tab, screen_path)
screen_contract <- app_joint_shared_read_contract(screen_path)
stopifnot(
  screen_contract$pilot_scenario == "normal_bridge",
  screen_contract$calibration_seed_base == 202610500L,
  screen_contract$authority_registry_sha256 == app_sha256_file(
    app_joint_shared_family_authority_path()),
  screen_contract$authority_manifest_sha256 == app_sha256_file(
    app_joint_shared_family_authority_manifest_path())
)

parent <- tempfile("joint_family_parent_")
dir.create(parent)
selected <- data.frame(
  scenario_id = "normal_bridge", candidate_id = "normal_bridge__test",
  design_class = "reservoir", rhs_tau0 = 0.1, stringsAsFactors = FALSE)
decision <- data.frame(
  status = "SHARED_BACKBONE_SELECTED_NOT_YET_QUANTILE_FIT",
  scenario_id = "normal_bridge", selected_candidate_id = "normal_bridge__test",
  stringsAsFactors = FALSE)
git_state <- data.frame(branch = "test", head = "0123456789abcdef", upstream = "test", stringsAsFactors = FALSE)
selected_path <- app_write_csv(selected, file.path(parent, "selected_shared_backbone.csv"))
decision_path <- app_write_csv(decision, file.path(parent, "shared_backbone_selection_decision.csv"))
git_path <- app_write_csv(git_state, file.path(parent, "source_git_state.csv"))
app_joint_shared_write_manifest(parent, c(
  selected = selected_path, decision = decision_path, git_state = git_path),
  filename = "final_artifact_manifest.csv")

quantile_tab <- app_joint_shared_family_quantile_contract(
  "normal_bridge", 202610550L, parent)
quantile_path <- tempfile(fileext = ".csv")
app_write_csv(quantile_tab, quantile_path)
quantile_contract <- app_joint_shared_quantile_read_contract(quantile_path)
verification <- app_joint_shared_quantile_verify_parent(parent, quantile_contract)
stopifnot(
  quantile_contract$pilot_scenario == "normal_bridge",
  quantile_contract$evaluation_seed_base == 202610550L,
  quantile_contract$parent_head == git_state$head,
  quantile_contract$parent_git_state_sha256 == app_sha256_file(git_path),
  all(verification$verification$hash_verified),
  verification$selected$candidate_id == selected$candidate_id
)

retained <- app_read_csv(app_joint_shared_family_retained_path())
stopifnot(
  nrow(retained) == 1L,
  retained$scenario_id == "regime_shift",
  retained$rhs_tau0 == 1,
  retained$retained_quantile_jobs == 51L,
  retained$retained_quantile_failures == 0L
)

cat("JOINT shared-backbone seven-family campaign tests passed.\n")
