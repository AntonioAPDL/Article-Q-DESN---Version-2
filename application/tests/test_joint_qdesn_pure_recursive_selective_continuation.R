#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd())
} else {
  file_arg <- sub("^--file=", "", grep(
    "^--file=", commandArgs(FALSE), value = TRUE
  )[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts",
  "_joint_qdesn_pure_recursive_bootstrap.R"))

template <- data.frame(
  scenario_id = c(
    "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
    "nonlinear_reservoir_friendly", "normal_bridge",
    "persistent_heavy_tail", "regime_shift", "student_t_location_scale"
  ),
  candidate_id = paste0("candidate_", seq_len(8L)),
  feature_contract = "pure_recursive_v1", design_class = "reservoir",
  D = 1L, n = "20", n_tilde = NA_character_, retained_state_budget = 20L,
  width_shape = "flat", state_reduction = FALSE, response_lags = 5L,
  exogenous_lags = 0L, alpha = "0.5", rho = "0.8", pi_w = "0.1",
  pi_in = "0.5", input_scale = 0.1, reservoir_seed = 202609250L,
  raw_inputs_in_readout = FALSE, full_states_all_layers = TRUE,
  architecture_signature = paste0("signature_", seq_len(8L)),
  rhs_tau0 = 0.01, stringsAsFactors = FALSE
)
source_root <- tempfile("source_selection_")
target_root <- tempfile("target_selection_")
dir.create(source_root); dir.create(target_root)
app_write_csv(template, file.path(source_root, "selected_family_backbones.csv"))
target <- template
changed <- target$scenario_id %in%
  app_joint_pure_continuation_changed_scenarios()
target$candidate_id[changed] <- paste0(target$candidate_id[changed], "_expanded")
target$architecture_signature[changed] <- paste0(
  target$architecture_signature[changed], "_expanded"
)
app_write_csv(target, file.path(target_root, "selected_family_backbones.csv"))
audit <- app_joint_pure_continuation_spec_audit(target_root, source_root)
stopifnot(
  nrow(audit) == 8L,
  sum(audit$specification_identical) == 6L,
  identical(sort(audit$scenario_id[!audit$specification_identical]),
    sort(app_joint_pure_continuation_changed_scenarios()))
)

bad <- target
bad$candidate_id[bad$scenario_id == "normal_bridge"] <- "unexpected_change"
app_write_csv(bad, file.path(target_root, "selected_family_backbones.csv"))
rejected <- try(app_joint_pure_continuation_spec_audit(
  target_root, source_root), silent = TRUE)
stopifnot(inherits(rejected, "try-error"))

app_write_csv(target, file.path(target_root, "selected_family_backbones.csv"))
writeLines("label,relative_path,size_bytes,sha256",
  file.path(target_root, "quantile_artifact_manifest.csv"))
contract_table <- app_joint_pure_confirmation_contract(
  target_root,
  execution_branch =
    "work/joint-qdesn-pure-desn-expanded-continuation-20261003",
  run_tag = "test_expanded_continuation",
  source_worktree = repo_root,
  contract_version = "joint_qdesn_pure_recursive_article_confirmation_v3"
)
contract_value <- function(name) {
  contract_table$value[contract_table$name == name][[1L]]
}
stopifnot(
  contract_value("contract_version") ==
    "joint_qdesn_pure_recursive_article_confirmation_v3",
  contract_value("execution_branch") ==
    "work/joint-qdesn-pure-desn-expanded-continuation-20261003",
  contract_value("run_tag") == "test_expanded_continuation",
  contract_value("source_worktree") == repo_root,
  contract_value("exal_mcmc_method") == "M0_v_collapsed_support_logit",
  contract_value("cpu_affinity_list") ==
    "0,1,8,9,12,13,19,20,24,25,27,28,29,30,31"
)
contract_path <- app_write_csv(contract_table,
  file.path(target_root, "confirmation_contract.csv"))
parsed_contract <- app_joint_article_read_contract(contract_path)
stopifnot(parsed_contract$version ==
  "joint_qdesn_pure_recursive_article_confirmation_v3")

source_worker <- tempfile("source_worker_")
target_worker <- tempfile("target_worker_")
dir.create(source_worker)
summary <- data.frame(
  worker_id = 1L, scenario_id = "old", model_id = "model",
  status = "completed", statistic = 42, stringsAsFactors = FALSE
)
summary_path <- app_write_csv(summary, file.path(source_worker, "summary.csv"))
payload_path <- file.path(source_worker, "payload.rds")
saveRDS(list(value = 7), payload_path)
app_joint_shared_write_manifest(source_worker, c(
  summary = summary_path, payload = payload_path
))
writeLines("completed", file.path(source_worker, "DONE"))
target_row <- data.frame(
  worker_id = 9L, scenario_id = "new", model_id = "model",
  stringsAsFactors = FALSE
)
receipt <- app_joint_pure_import_worker(
  source_worker, target_worker, target_row, "summary.csv"
)
rewritten <- app_read_csv(file.path(target_worker, "summary.csv"))
verification <- app_joint_shared_verify_manifest(
  target_worker, file.path(target_worker, "artifact_manifest.csv")
)
stopifnot(
  receipt$import_status[[1L]] == "imported_verified",
  rewritten$worker_id[[1L]] == 9L,
  rewritten$scenario_id[[1L]] == "new",
  rewritten$statistic[[1L]] == 42,
  all(verification$verified)
)

cat("Selective expanded-continuation tests passed.\n")
