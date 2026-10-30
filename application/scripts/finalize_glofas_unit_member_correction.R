#!/usr/bin/env Rscript
# Analyze the complete corrected comparison; never fit or publish here.
source("application/scripts/_glofas_unit_member_bootstrap.R")
source("application/R/glofas_search3_final_closeout.R")
source("application/R/glofas_part4_exal_inner_audit.R")
args <- app_parse_args(list(runtime_root = ""))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
manifest <- app_read_csv(file.path(root, "configs/part4_model_manifest.csv"))
if (nrow(manifest) != 18L || anyDuplicated(manifest$run_id)) stop("Expected all 18 corrected fits.")
counts <- app_glofas_closeout_marker_counts(file.path(root, "status"))
if (counts$completed != 18L || counts$running || counts$failed) stop("Corrected fit processes are incomplete.")
output <- file.path(root, "final_packet")
if (dir.exists(output) && length(list.files(output))) stop("Never overwrite a frozen final packet.")
app_ensure_dir(output)
diagnostics <- list()
rows <- list()
tau <- app_glofas_part4_quantile_grid()
label <- c(normal_ridge_diagnostic="Normal Ridge", normal_rhs_vb_diagnostic="Normal RHS/VB",
  independent_al_rhs_vb="Independent AL", independent_exal_rhs_vb="Independent exAL",
  joint_al_rhs_vb="MQ AL", joint_exal_rhs_vb="MQ exAL")
for (i in seq_len(nrow(manifest))) {
  job <- manifest$run_id[[i]]
  family <- manifest$part4_family[[i]]
  app_glofas_closeout_verify_manifest(root, file.path(root, "manifests", paste0(job, "_artifacts.csv")))
  target <- jsonlite::read_json(file.path(root, "manifests", paste0(job, "_target.json")), simplifyVector=TRUE)
  if (!identical(target$policy, "unit_member_likelihood_v1") || target$included_issued_G != 1428L ||
      target$included_future_Y != if (grepl("^normal_", family)) 28L else 0L) stop("Wrong target row counts.")
  fit_object <- readRDS(file.path(root, "objects", paste0(job, "_fit_side.rds")))
  if (!identical(fit_object$unit_member_contract$policy, "unit_member_likelihood_v1")) stop("Legacy fit in corrected packet.")
  joint <- grepl("^joint_", family)
  fit <- if (joint) fit_object else fit_object$fit
  converged <- if (joint) {
    isTRUE(tryCatch({app_glofas_closeout_validate_joint_fit(fit); TRUE}, error=function(e) FALSE))
  } else isTRUE(fit$vb_diagnostics$converged)
  quadrature <- TRUE
  if (grepl("exal", family)) {
    exfits <- if (joint) fit$fits else list(fit)
    quadrature <- all(vapply(exfits, function(x) {
      all(app_glofas_part4_exal_terminal_quadrature(x)$quadrature_pass)
    }, logical(1L)))
    converged <- converged && quadrature
  }
  diagnostics[[i]] <- data.frame(job_id=job, family=label[[family]],
    recorded_converged=if (joint) isTRUE(fit$converged) else isTRUE(fit$vb_diagnostics$converged),
    strict_numerical_gate=converged, quadrature_pass=quadrature,
    fit_sha256=app_sha256_file(file.path(root, "objects", paste0(job, "_fit_side.rds"))))
  if (grepl("^normal_", family)) {
    draws <- utils::read.csv(gzfile(file.path(root, "predictions", paste0(job, "_posterior_draws.csv.gz"))),
      stringsAsFactors=FALSE)
    qrows <- do.call(rbind, lapply(split(draws, draws$target_date), function(block) {
      data.frame(target_date=as.Date(unique(block$target_date)), horizon=unique(block$horizon),
        quantile_level=tau, y_reference=unique(block$y_reference),
        qhat=as.numeric(stats::quantile(block$latent_y_draw, tau, names=FALSE, type=8)))
    }))
  } else qrows <- app_read_csv(file.path(root, "scores", paste0(job, "_by_horizon.csv")))
  qrows <- qrows[, c("target_date", "horizon", "quantile_level", "y_reference", "qhat")]
  qrows$family <- label[[family]]
  rows[[i]] <- qrows
  rm(fit_object, fit); invisible(gc())
}
design <- readRDS(file.path(root, "objects/part4_shared_design_truth_free.rds"))
app_glofas_unit_member_validate_design(design)
ensemble <- design$latent_data$g_ensemble
truth <- readRDS(file.path(root, "objects/part4_scoring_panel_sidecar.rds"))
if (!identical(truth$role, "post_fit_scoring_sidecar") || isTRUE(truth$future_truth_used_in_fit)) stop("Truth firewall failed.")
raw <- do.call(rbind, lapply(split(ensemble, ensemble$target_date), function(block) {
  date <- as.Date(unique(block$target_date))
  data.frame(target_date=date, horizon=unique(block$horizon), quantile_level=tau,
    y_reference=truth$panel$y_transformed[as.Date(truth$panel$target_date) == date],
    qhat=as.numeric(stats::quantile(block$g_transformed, tau, names=FALSE, type=8)), family="Raw GloFAS")
}))
all_rows <- do.call(rbind, c(rows, list(raw)))
diagnostics <- do.call(rbind, diagnostics)
summary <- do.call(rbind, lapply(split(all_rows, all_rows$family), function(block) {
  if (nrow(block) != 196L || length(unique(block$target_date)) != 28L) stop("Incomplete family comparison.")
  family <- unique(block$family)
  passed <- family == "Raw GloFAS" || all(diagnostics$strict_numerical_gate[diagnostics$family == family])
  app_glofas_closeout_summarize_quantiles(block, family, "complete_unit_member_comparison",
    if (passed) "numerical_gate_pass" else "bounded_fit_requires_review")
}))
calibration <- do.call(rbind, lapply(split(all_rows, all_rows$family), function(block) {
  app_glofas_closeout_calibration(block, unique(block$family))
}))
app_write_csv(all_rows, file.path(output, "quantile_paths.csv"))
app_write_csv(summary, file.path(output, "family_scores.csv"))
app_write_csv(calibration, file.path(output, "quantile_calibration.csv"))
app_write_csv(diagnostics, file.path(output, "fit_numerical_gates.csv"))
decision <- if (all(diagnostics$strict_numerical_gate)) "READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION" else
  "NOT_READY_BOUNDED_FITS_REQUIRE_REVIEW"
app_write_json(list(status=decision, fit_units=18L,
  numerical_pass=sum(diagnostics$strict_numerical_gate), numerical_review=sum(!diagnostics$strict_numerical_gate),
  model_selection_or_retuning=FALSE, article_changed=FALSE,
  contract=app_glofas_unit_member_contract()), file.path(output, "DECISION.json"))
app_glofas_closeout_write_manifest(root,
  file.path("final_packet", c("quantile_paths.csv", "family_scores.csv", "quantile_calibration.csv",
    "fit_numerical_gates.csv", "DECISION.json")), file.path(output, "artifact_manifest.csv"))
cat(decision, "\n")
