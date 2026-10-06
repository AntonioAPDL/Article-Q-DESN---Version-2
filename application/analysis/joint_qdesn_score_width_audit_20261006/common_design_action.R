joint_width_common_action <- function(source_root, output) {
  stopifnot(!dir.exists(output))
  app_joint_prior_verify_freeze(source_root)
  ct <- readRDS(file.path(source_root, "contract.rds"))
  cells <- app_joint_prior_collect(source_root, "confirmation")
  cells <- cells[cells$scenario_id == "laplace_bridge" & cells$arm_id == "prior_08", ]
  stopifnot(nrow(cells) == 8L)
  plan <- app_read_csv(file.path(source_root, "confirmation/chains.csv"))
  result <- list()
  app_ensure_dir(output)
  for (i in seq_len(nrow(cells))) {
    cell <- cells[i, ]; id <- cell$cell_id
    jobs <- plan[plan$cell_id == id, ]; jobs <- jobs[order(jobs$chain_id), ]
    frames <- lapply(jobs$worker_id, function(worker) app_read_csv(file.path(source_root,
      "confirmation/chains", sprintf("worker_%04d", worker), "posterior_draws.csv.gz")))
    beta <- colMeans(do.call(rbind, lapply(frames, app_joint_recursive_select_block, "beta")))
    alpha <- colMeans(do.call(rbind, lapply(frames, app_joint_recursive_select_block, "alpha")))
    Z <- readRDS(file.path(source_root, "confirmation/scores",
      sprintf("cell_%04d", id), "mean_design.rds"))$mean_design
    reference <- cells$cell_id[cells$replicate_id == cell$replicate_id &
      cells$likelihood == "AL" & cells$structure == "independent"]
    common <- readRDS(file.path(source_root, "confirmation/scores",
      sprintf("cell_%04d", reference), "mean_design.rds"))$mean_design
    stopifnot(identical(dim(Z), dim(common)), identical(colnames(Z), colnames(common)))
    oracle <- readRDS(file.path(source_root, "confirmation/datasets",
      sprintf("dataset_%02d", cell$dataset_id), "oracle.rds"))
    native <- app_joint_recursive_canonical_metrics(Z, beta, alpha, oracle, ct$tau, ct$weights)
    other <- app_joint_recursive_canonical_metrics(common, beta, alpha, oracle, ct$tau, ct$weights)
    error <- abs(native$origin_marginal_dgp_integrated_acrps -
      cell$canonical_origin_marginal_dgp_integrated_acrps)
    stopifnot(error < 1e-8)
    result[[i]] <- cbind(cell[c("cell_id", "replicate_id", "structure", "likelihood")],
      native_action_score = native$origin_marginal_dgp_integrated_acrps,
      common_design_action_score = other$origin_marginal_dgp_integrated_acrps,
      common_minus_native_score = other$origin_marginal_dgp_integrated_acrps -
        native$origin_marginal_dgp_integrated_acrps,
      native_action_oracle_rmse = native$origin_marginal_oracle_quantile_rmse,
      common_design_action_oracle_rmse = other$origin_marginal_oracle_quantile_rmse,
      mean_design_rms_difference = sqrt(mean((Z - common)^2)),
      original_action_reconstruction_error = error)
  }
  x <- do.call(rbind, result)
  app_write_csv(x, file.path(output, "laplace_common_design_action.csv"))
  contrast <- do.call(rbind, lapply(which(x$structure == "joint"), function(i) {
    j <- x[i, ]; independent <- x[x$replicate_id == j$replicate_id &
      x$likelihood == j$likelihood & x$structure == "independent", ]
    native_gap <- j$native_action_score - independent$native_action_score
    common_gap <- j$common_design_action_score - independent$common_design_action_score
    data.frame(replicate_id = j$replicate_id, likelihood = j$likelihood,
      native_joint_minus_independent_gap = native_gap,
      common_design_joint_minus_independent_gap = common_gap,
      native_design_contribution_to_gap = native_gap - common_gap,
      common_gap_fraction_of_native_gap = common_gap / native_gap)
  }))
  app_write_csv(contrast, file.path(output, "common_design_gap_contrasts.csv"))
  script <- app_path("local_trackers/joint_score_width_audit_20261006/common_design_action.R")
  app_write_csv(data.frame(path = script, sha256 = app_sha256_file(script)),
    file.path(output, "analysis_source.csv"))
  writeLines(c("Diagnostic use of independent-AL mean states with each model's unchanged posterior-mean readout.",
    "Not a replacement forecast, altered score contract, posterior refit, or causal identification of a prior effect.",
    "Independent product-posterior permutations leave coefficient marginal means unchanged.",
    "Native canonical scores reproduce the frozen baseline before any comparison.",
    capture.output(sessionInfo())), file.path(output, "METHODS.txt"))
  app_joint_shared_write_manifest(output, setNames(list.files(output, full.names = TRUE), list.files(output)))
  stopifnot(all(app_joint_shared_verify_manifest(output)$verified))
  print(x, row.names = FALSE, digits = 6)
  print(contrast, row.names = FALSE, digits = 6)
  cat("COMMON_DESIGN_ACTION_COMPLETE\n")
}
