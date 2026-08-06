# Phase163 case-specific upper-tail Joint exQDESN VB/VB-LD calibration.

app_joint_exqdesn_phase163_root <- function() "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
app_joint_exqdesn_phase163_dirs <- function() {
  r <- app_joint_exqdesn_phase163_root()
  list(
    phase150_freeze = file.path(r, "joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727"),
    phase149_readiness = file.path(r, "joint_qdesn_phase149_case_specific_exal_screening_readiness_20260726"),
    phase151_readiness = file.path(r, "joint_qdesn_phase151_case_specific_feature_screening_readiness_20260728"),
    phase162 = file.path(r, "joint_qdesn_phase162_exal_scenario_classification_20260805"),
    readiness = file.path(r, "joint_qdesn_phase163_tail_calibration_readiness_20260806"),
    screening = file.path(r, "joint_qdesn_phase163_tail_calibration_vb_20260806"),
    fixture = file.path(r, "joint_qdesn_simulation_dgp_fixtures_20260706")
  )
}

app_joint_exqdesn_phase163_key <- function(tau0, zeta2, alpha, gamma) {
  paste(format(round(as.numeric(tau0), 8), scientific = FALSE), format(round(as.numeric(zeta2), 8), scientific = FALSE),
    format(round(as.numeric(alpha), 8), scientific = FALSE), as.character(gamma), sep = "|")
}

app_joint_exqdesn_phase163_registry <- function(dirs = app_joint_exqdesn_phase163_dirs()) {
  controls <- app_read_csv(file.path(dirs$phase150_freeze, "case_winner_controls.csv"))
  classification <- app_read_csv(file.path(dirs$phase162, "scenario_classification.csv"))
  targets <- classification$scenario_id[classification$next_priority <= 2L & classification$limitation_class != "already_adequate"]
  controls <- controls[controls$scenario_ids %in% targets & controls$model_ids == "joint_exqdesn_rhs_vb", , drop = FALSE]
  if (nrow(controls) != 5L) stop("Phase163 requires exactly five case-specific Joint exQDESN controls.", call. = FALSE)
  roles <- data.frame(
    role = c("shrink_wide_alpha", "relax_wide_alpha", "tight_slab_wide_alpha", "wide_slab_wide_alpha"),
    tau_mult = c(.75, 1.25, 1, 1), zeta_mult = c(1, 1, .5, 2), alpha_mult = c(1.25, 1.25, 1.25, 1.25),
    rationale = c("coordinated stronger RHS shrinkage and upper-fan flexibility",
      "coordinated weaker RHS shrinkage and upper-fan flexibility",
      "tighter slab with upper-fan flexibility", "wider slab with upper-fan flexibility"), stringsAsFactors = FALSE)
  prior149 <- app_read_csv(file.path(dirs$phase149_readiness, "phase149_case_specific_screening_registry.csv"))
  prior151 <- app_read_csv(file.path(dirs$phase151_readiness, "phase151_candidate_registry.csv"))
  old <- rbind(
    data.frame(scenario_id = prior149$scenario_ids, key = app_joint_exqdesn_phase163_key(prior149$tau0, prior149$zeta2, prior149$alpha_prior_sd, prior149$gamma_init_policy)),
    data.frame(scenario_id = prior151$scenario_id, key = app_joint_exqdesn_phase163_key(prior151$tau0, prior151$zeta2, prior151$alpha_prior_sd, prior151$gamma_init_policy)))
  rows <- list()
  for (ii in seq_len(nrow(controls))) for (jj in seq_len(nrow(roles))) {
    c0 <- controls[ii, ]; rr <- roles[jj, ]
    tau0 <- pmin(1.5, pmax(.1, c0$tau0 * rr$tau_mult)); zeta2 <- pmin(256, pmax(8, c0$zeta2 * rr$zeta_mult))
    alpha <- pmin(2, pmax(.35, as.numeric(c0$alpha_prior_sd) * rr$alpha_mult))
    key <- app_joint_exqdesn_phase163_key(tau0, zeta2, alpha, c0$gamma_init_policy)
    prior_duplicate <- any(old$scenario_id == c0$scenario_ids & old$key == key)
    candidate_id <- paste(c0$scenario_ids, "joint_exqdesn_rhs_vb", "phase163", rr$role,
      paste0("tau0_", gsub("\\.", "p", tau0)), paste0("zeta2_", gsub("\\.", "p", zeta2)),
      paste0("alpha_", gsub("\\.", "p", alpha)), sep = "__")
    root <- file.path(dirs$screening, "cases", paste0(c0$scenario_ids, "__joint_exqdesn_rhs_vb"), "candidates", rr$role)
    rows[[length(rows)+1L]] <- data.frame(candidate_id = candidate_id,
      candidate_label = paste(c0$scenario_ids, "Joint exQDESN", rr$role, sep = " | "), use_existing_artifacts = FALSE,
      fit_dir = file.path(root, "fit"), forecast_dir = file.path(root, "forecast"),
      vb_max_iter = max(2880L, as.integer(c0$vb_max_iter)), adaptive_vb_max_iter_grid = "2880,3360,3840",
      vb_tol = min(1e-4, as.numeric(c0$vb_tol)), rhs_vb_inner = max(14L, as.integer(c0$rhs_vb_inner)),
      tau0 = tau0, zeta2 = zeta2, a_sigma = c0$a_sigma, b_sigma = c0$b_sigma,
      alpha_prior_sd = alpha, alpha_min_spacing = c0$alpha_min_spacing,
      gamma_init_policy = c0$gamma_init_policy, review_adjustment_threshold = c0$review_adjustment_threshold,
      max_dense_dim = c0$max_dense_dim, n_cores = 1L, candidate_role = "phase163_case_specific_tail_calibration",
      notes = rr$rationale, scenario_ids = c0$scenario_ids, model_ids = "joint_exqdesn_rhs_vb",
      case_id = c0$case_id, phase163_role = rr$role, source_phase150_candidate_id = c0$candidate_id,
      no_global_specification = TRUE, upper_tail_target = TRUE, prior_duplicate = prior_duplicate, stringsAsFactors = FALSE)
  }
  registry <- do.call(rbind, rows)
  if (any(registry$prior_duplicate)) stop("Phase163 generated a control combination already present in Phase149/151.", call. = FALSE)
  app_joint_qdesn_validate_screening_registry(registry)
  registry
}

app_joint_exqdesn_phase163_prepare <- function(dirs = app_joint_exqdesn_phase163_dirs()) {
  app_ensure_dir(dirs$readiness); app_ensure_dir(dirs$screening)
  sources <- do.call(rbind, list(
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase150_freeze, "phase150_freeze"),
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase151_readiness, "phase151_readiness"),
    app_joint_exqdesn_phase162_verify_manifest(dirs$phase162, "phase162")))
  if (any(sources$status != "pass")) stop("Phase163 source verification failed.", call. = FALSE)
  registry <- app_joint_exqdesn_phase163_registry(dirs)
  classification <- app_read_csv(file.path(dirs$phase162, "scenario_classification.csv"))
  benchmarks <- classification[classification$scenario_id %in% registry$scenario_ids,
    c("scenario_id", "mcmc_fit_truth_mae_exal", "mcmc_forecast_truth_mae_exal",
      "mcmc_forecast_check_loss_mean_exal", "mcmc_forecast_crps_grid_exal", "mcmc_forecast_truth_mae_al")]
  assessment <- data.frame(gate_status = "pass", scenarios = length(unique(registry$scenario_ids)), candidates = nrow(registry),
    prior_duplicates = sum(registry$prior_duplicate), source_hash_failures = sum(sources$status != "pass"),
    workers_recommended = min(20L, nrow(registry)), recommendation = "launch_phase163_parallel_vb_vbld", stringsAsFactors = FALSE)
  writeLines(c("# Phase163 upper-tail calibration readiness", "", "Twenty novel combined-control candidates target five scenarios.",
    "The study is scenario-specific, direct-readout, VB/VB-LD-first, and performs no MCMC.",
    "Existing Phase150/article results are frozen comparators and are not rerun."), file.path(dirs$readiness, "README.md"))
  out <- list(phase163_candidate_registry = registry, frozen_benchmarks = benchmarks,
    source_manifest_verification = sources, phase163_readiness_assessment = assessment,
    provenance = app_joint_qvp_provenance_rows())
  paths <- vapply(names(out), function(n) app_joint_qvp_write_csv(out[[n]], file.path(dirs$readiness, paste0(n, ".csv"))), character(1L))
  paths <- c(paths, README = file.path(dirs$readiness, "README.md"))
  manifest <- data.frame(label=names(paths),relative_path=basename(paths),size_bytes=as.numeric(file.info(paths)$size),
    sha256=vapply(paths,app_sha256_file,character(1L)),stringsAsFactors=FALSE)
  app_joint_qvp_write_csv(manifest,file.path(dirs$readiness,"artifact_manifest.csv"))
  list(dirs=dirs,registry=registry,assessment=assessment)
}

app_joint_exqdesn_phase163_audit <- function(dirs = app_joint_exqdesn_phase163_dirs()) {
  forecast <- app_read_csv(file.path(dirs$screening, "forecast_scenario_metric_summary.csv"))
  fit <- app_read_csv(file.path(dirs$screening, "fit_scenario_metric_summary.csv"))
  tau <- app_read_csv(file.path(dirs$screening, "forecast_tau_metric_summary.csv"))
  benchmarks <- app_read_csv(file.path(dirs$readiness, "frozen_benchmarks.csv"))
  f <- forecast[forecast$model_id == "joint_exqdesn_rhs_vb", c("candidate_id","scenario_id","truth_mae","check_loss_mean","gate_status","contract_crossing_pairs")]
  names(f)[3:6] <- c("forecast_truth_mae","forecast_check_loss","gate_status","contract_crossings")
  q <- tau[tau$model_id == "joint_exqdesn_rhs_vb" & abs(tau$tau-.95)<1e-8, c("candidate_id","scenario_id","truth_mae","truth_bias")]
  names(q)[3:4] <- c("tau095_truth_mae","tau095_truth_bias")
  z <- merge(merge(f,q,by=c("candidate_id","scenario_id")),benchmarks,by="scenario_id")
  z$forecast_gain_vs_article <- z$mcmc_forecast_truth_mae_exal-z$forecast_truth_mae
  z$check_loss_relative_change <- z$forecast_check_loss/z$mcmc_forecast_check_loss_mean_exal-1
  z$eligible_for_independent_validation <- z$gate_status=="pass" & z$contract_crossings==0 &
    z$forecast_gain_vs_article >= pmax(.0025,.025*z$mcmc_forecast_truth_mae_exal) & z$check_loss_relative_change <= .01
  z <- z[order(z$scenario_id,z$forecast_truth_mae,z$tau095_truth_mae),]
  winners <- do.call(rbind,lapply(split(z,z$scenario_id),function(x)x[1,,drop=FALSE]))
  assessment <- data.frame(gate_status=if(any(!is.finite(z$forecast_truth_mae)))"fail" else "pass",
    candidates=nrow(z),eligible=sum(z$eligible_for_independent_validation),recommendation=if(any(z$eligible_for_independent_validation))
      "freeze_eligible_candidates_for_independent_validation" else "retain_current_article_rows",stringsAsFactors=FALSE)
  app_joint_qvp_write_csv(z,file.path(dirs$screening,"phase163_candidate_ranking.csv"))
  app_joint_qvp_write_csv(winners,file.path(dirs$screening,"phase163_scenario_winners.csv"))
  app_joint_qvp_write_csv(assessment,file.path(dirs$screening,"phase163_result_assessment.csv"))
  list(ranking=z,winners=winners,assessment=assessment)
}
