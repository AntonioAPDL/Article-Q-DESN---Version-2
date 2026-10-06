joint_width_components <- function(source_root, output) {
  stopifnot(!dir.exists(output))
  app_joint_prior_verify_freeze(source_root)
  ct <- readRDS(file.path(source_root, "contract.rds"))
  cells <- app_joint_prior_collect(source_root, "confirmation")
  cells <- cells[cells$scenario_id == "laplace_bridge" & cells$arm_id == "prior_08", ]
  plan <- app_read_csv(file.path(source_root, "confirmation/chains.csv"))
  get_mean <- function(cell) {
    jobs <- plan[plan$cell_id == cell$cell_id, ]; jobs <- jobs[order(jobs$chain_id), ]
    frames <- lapply(jobs$worker_id, function(worker) app_read_csv(file.path(source_root,
      "confirmation/chains", sprintf("worker_%04d", worker), "posterior_draws.csv.gz")))
    list(beta = colMeans(do.call(rbind, lapply(frames, app_joint_recursive_select_block, "beta"))),
      alpha = colMeans(do.call(rbind, lapply(frames, app_joint_recursive_select_block, "alpha"))))
  }
  result <- list()
  for (replicate in 1:2) {
    group <- cells[cells$replicate_id == replicate, ]
    reference <- group$cell_id[group$structure == "independent" & group$likelihood == "AL"]
    Z <- readRDS(file.path(source_root, "confirmation/scores",
      sprintf("cell_%04d", reference), "mean_design.rds"))$mean_design
    context <- app_joint_prior_context(source_root, "confirmation", unique(group$dataset_id))
    first_leads <- which(context$design$forecast_map$horizon == 1L)
    oracle <- readRDS(file.path(source_root, "confirmation/datasets",
      sprintf("dataset_%02d", unique(group$dataset_id)), "oracle.rds"))
    for (likelihood in c("AL", "exAL")) {
      pair <- group[group$likelihood == likelihood, ]
      jcell <- pair[pair$structure == "joint", ]; icell <- pair[pair$structure == "independent", ]
      joint <- get_mean(jcell); independent <- get_mean(icell)
      evaluate <- function(beta, alpha) app_joint_recursive_canonical_metrics(
        Z, beta, alpha, oracle, ct$tau, ct$weights)$origin_marginal_dgp_integrated_acrps
      jj <- evaluate(joint$beta, joint$alpha)
      ii <- evaluate(independent$beta, independent$alpha)
      ji <- evaluate(joint$beta, independent$alpha)
      ij <- evaluate(independent$beta, joint$alpha)
      beta <- ((jj - ij) + (ji - ii)) / 2
      alpha <- ((jj - ji) + (ij - ii)) / 2
      stopifnot(abs(beta + alpha - (jj - ii)) < 1e-10)
      native_first_lead_error <- max(vapply(pair$cell_id, function(id) {
        native <- readRDS(file.path(source_root, "confirmation/scores",
          sprintf("cell_%04d", id), "mean_design.rds"))$mean_design
        max(abs(native[first_leads, , drop = FALSE] - Z[first_leads, , drop = FALSE]))
      }, numeric(1L)))
      stopifnot(native_first_lead_error < 1e-10)
      result[[length(result) + 1L]] <- data.frame(replicate_id = replicate,
        likelihood = likelihood, joint_beta_joint_alpha = jj,
        independent_beta_independent_alpha = ii,
        joint_beta_independent_alpha = ji, independent_beta_joint_alpha = ij,
        common_design_gap = jj - ii, symmetric_beta_gap_allocation = beta,
        symmetric_alpha_gap_allocation = alpha, beta_fraction_of_common_gap = beta / (jj - ii),
        first_lead_mean_design_max_difference = native_first_lead_error)
    }
  }
  app_ensure_dir(output)
  x <- do.call(rbind, result)
  app_write_csv(x, file.path(output, "laplace_readout_component_audit.csv"))
  script <- app_path("local_trackers/joint_score_width_audit_20261006/readout_component_audit.R")
  app_write_csv(data.frame(path = script, sha256 = app_sha256_file(script)),
    file.path(output, "analysis_source.csv"))
  writeLines(c("Predeclared two-by-two posterior-mean beta/intercept swaps on the frozen independent-AL mean-state design.",
    "Symmetric allocations telescope exactly to the common-design score gap; they are not causal effects of changing a prior.",
    "Hybrid point actions are diagnostics only, not fitted models, new posteriors, or publication candidates.",
    "First-lead mean designs must agree across models because no recursive future input has yet entered the reservoir.",
    capture.output(sessionInfo())), file.path(output, "METHODS.txt"))
  app_joint_shared_write_manifest(output, setNames(list.files(output, full.names = TRUE), list.files(output)))
  stopifnot(all(app_joint_shared_verify_manifest(output)$verified))
  print(x, row.names = FALSE, digits = 6)
  cat("READOUT_COMPONENT_AUDIT_COMPLETE\n")
}
