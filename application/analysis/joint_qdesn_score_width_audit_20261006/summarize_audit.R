joint_width_tables <- function(input, output) {
  stopifnot(!dir.exists(output))
  app_ensure_dir(output)
  stopifnot(all(app_joint_shared_verify_manifest(input)$verified))
  cells <- app_read_csv(file.path(input, "cell_audit.csv"))
  chains <- app_read_csv(file.path(input, "chain_sensitivity.csv"))
  projections <- app_read_csv(file.path(input, "readout_projection_variance.csv"))
  result <- list()
  for (i in which(cells$structure == "joint")) {
    joint <- cells[i, ]
    independent <- cells[cells$scenario_id == joint$scenario_id &
      cells$replicate_id == joint$replicate_id &
      cells$likelihood == joint$likelihood & cells$structure == "independent", ]
    stopifnot(nrow(independent) == 1L)
    marginal_ratio <- joint$marginal_variance / independent$marginal_variance
    dependence_ratio <- (joint$total_variance / joint$marginal_variance) /
      (independent$total_variance / independent$marginal_variance)
    stopifnot(abs(marginal_ratio * dependence_ratio -
      joint$total_variance / independent$total_variance) < 1e-10)
    sensitivity <- chains[chains$cell_id == joint$cell_id &
      chains$allocation == "leave_one_chain_out", ]
    result[[length(result) + 1L]] <- data.frame(
      scenario_id = joint$scenario_id, replicate_id = joint$replicate_id,
      likelihood = joint$likelihood, arm_id = joint$arm_id,
      joint_mean = joint$posterior_score_mean,
      independent_mean = independent$posterior_score_mean,
      mean_gap_percent = 100 * (joint$posterior_score_mean / independent$posterior_score_mean - 1),
      canonical_action_gap_percent = 100 *
        (joint$canonical_origin_marginal_dgp_integrated_acrps /
          independent$canonical_origin_marginal_dgp_integrated_acrps - 1),
      joint_mean_minus_canonical = joint$posterior_score_mean -
        joint$canonical_origin_marginal_dgp_integrated_acrps,
      independent_mean_minus_canonical = independent$posterior_score_mean -
        independent$canonical_origin_marginal_dgp_integrated_acrps,
      joint_mcse_fraction_of_interval_width = joint$score_mcse_mean /
        joint$posterior_score_interval_width,
      interval_width_ratio = joint$posterior_score_interval_width /
        independent$posterior_score_interval_width,
      total_variance_ratio = joint$total_variance / independent$total_variance,
      marginal_variance_ratio = marginal_ratio,
      dependence_variance_ratio = dependence_ratio,
      joint_covariance_fraction = joint$covariance_fraction,
      independent_covariance_fraction = independent$covariance_fraction,
      joint_between_chain_fraction = joint$between_chain_variance_fraction,
      leave_one_chain_max_mean_change_percent =
        100 * max(abs(sensitivity$score_mean - joint$posterior_score_mean)) /
          joint$posterior_score_mean,
      leave_one_chain_width_min = min(sensitivity$width),
      leave_one_chain_width_max = max(sensitivity$width),
      raw_score_sd_ratio = sqrt(joint$raw_total_variance / independent$raw_total_variance),
      contracted_score_sd_ratio = sqrt(joint$total_variance / independent$total_variance),
      joint_contract_raw_variance_ratio = joint$total_variance / joint$raw_total_variance,
      independent_contract_raw_variance_ratio =
        independent$total_variance / independent$raw_total_variance)
  }
  attribution <- do.call(rbind, result)
  app_write_csv(attribution, file.path(output, "width_attribution.csv"))
  weights <- c(.025, .1, .2, .25, .2, .1, .025)
  projection_summary <- do.call(rbind, lapply(unique(projections$cell_id), function(id) {
    x <- projections[projections$cell_id == id, ]
    x <- x[order(x$tau), ]; stopifnot(nrow(x) == 7L)
    stopifnot(isTRUE(all.equal(x$tau, c(.05, .1, .25, .5, .75, .9, .95))))
    correlations <- x$intercept_fit_offset_correlation[
      is.finite(x$intercept_fit_offset_correlation)]
    vf <- sum(weights * x$fit_quantile_variance)
    vp <- sum(weights * x$forecast_quantile_variance)
    vc <- sum(weights * x$common_design_quantile_variance)
    data.frame(cell_id = id, weighted_fit_quantile_variance = vf / sum(weights),
      weighted_forecast_quantile_variance = vp / sum(weights),
      weighted_common_design_quantile_variance = vc / sum(weights),
      forecast_fit_variance_ratio = vp / vf, native_common_variance_ratio = vp / vc,
      weak_design_dimensions = unique(x$weak_design_dimensions),
      fit_condition_number = unique(x$fit_condition_number),
      weighted_weak_fit_projected_variance = sum(weights * x$weak_direction_fit_variance) / sum(weights),
      weighted_weak_forecast_projected_variance = sum(weights * x$weak_direction_forecast_variance) / sum(weights),
      minimum_intercept_offset_correlation = if (length(correlations)) min(correlations) else NA_real_,
      maximum_intercept_offset_correlation = if (length(correlations)) max(correlations) else NA_real_)
  }))
  projection_summary <- merge(cells[c("cell_id", "scenario_id", "replicate_id",
    "structure", "likelihood", "arm_id")], projection_summary, by = "cell_id", sort = FALSE)
  app_write_csv(projection_summary, file.path(output, "projection_summary.csv"))
  app_write_csv(cells[cells$scenario_id == "laplace_bridge", ], file.path(output, "laplace_comparison.csv"))
  script <- app_path("local_trackers/joint_score_width_audit_20261006/summarize_audit.R")
  app_write_csv(data.frame(source = c(file.path(input, "artifact_manifest.csv"), script),
    sha256 = vapply(c(file.path(input, "artifact_manifest.csv"), script), app_sha256_file, character(1L))),
    file.path(output, "summary_provenance.csv"))
  app_joint_shared_write_manifest(output, setNames(list.files(output, full.names = TRUE),
    list.files(output)))
  stopifnot(all(app_joint_shared_verify_manifest(output)$verified))
  print(attribution, row.names = FALSE, digits = 5)
  print(projection_summary, row.names = FALSE, digits = 5)
  cat("SUMMARY_TABLES_COMPLETE\n")
}
