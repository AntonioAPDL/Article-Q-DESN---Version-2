#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(coda)
  library(jsonlite)
  library(yaml)
})

args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
artifact <- "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
prep <- arg("--prep-dir", file.path(artifact, "authoritative/pricefm_stage_r52_r53_exal_m0_launch_prep_20260811"))
out <- arg("--output-dir", file.path(artifact, "authoritative/pricefm_stage_r54_exal_m0_closeout_20260812"))
force <- tolower(arg("--force", "false")) %in% c("1", "true", "yes")
if (dir.exists(out) && length(list.files(out)) && !force) stop("Output exists: ", out, call. = FALSE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)

cases <- utils::read.csv(file.path(prep, "pricefm_stage_r52_case_manifest.csv"), stringsAsFactors = FALSE)
manifest <- utils::read.csv(file.path(prep, "pricefm_stage_r53_launch_manifest.csv"), stringsAsFactors = FALSE)
if (nrow(cases) != 87L || nrow(manifest) != 2436L) stop("R54 requires the full 87-case/2436-chain surface", call. = FALSE)
summaries <- lapply(manifest$output_dir, function(path) {
  summary <- file.path(path, "job_summary.json")
  if (!file.exists(summary)) return(NULL)
  jsonlite::fromJSON(summary)
})
complete <- vapply(summaries, function(x) !is.null(x) && identical(x$status, "completed") && isTRUE(x$finite_draws) && identical(x$core_update_mode, "m0_v_collapsed_support_logit"), logical(1L))
if (!all(complete)) stop(sum(!complete), " R53 chain jobs are incomplete or invalid", call. = FALSE)

pinball <- function(y, pred, tau) ifelse(y >= pred, tau * (y - pred), (1 - tau) * (pred - y))
safe_rhat <- function(chains) {
  tryCatch(as.numeric(coda::gelman.diag(coda::mcmc.list(lapply(chains, coda::mcmc)), autoburnin = FALSE, multivariate = FALSE)$psrf[1L, 1L]), error = function(e) NA_real_)
}
safe_ess <- function(chains) {
  tryCatch(as.numeric(coda::effectiveSize(coda::mcmc.list(lapply(chains, coda::mcmc)))[1L]), error = function(e) NA_real_)
}

diagnostic_rows <- list()
metric_rows <- list()
chain_metric_rows <- list()
case_rows <- list()
di <- 0L
mi <- 0L
ci <- 0L
for (case_index in seq_len(nrow(cases))) {
  case <- cases[case_index, ]
  case_manifest <- manifest[manifest$case_id == case$id, , drop = FALSE]
  case_summary <- jsonlite::fromJSON(file.path(case$output_dir, "case_summary.json"))
  vb <- utils::read.csv(file.path(case$output_dir, "vb_replay_metrics.csv"), stringsAsFactors = FALSE)
  case_m0_metrics <- list()
  case_chain_metrics <- list()
  for (tau in sort(unique(case_manifest$tau))) {
    jobs <- case_manifest[abs(case_manifest$tau - tau) < 1e-12, , drop = FALSE]
    if (nrow(jobs) != 4L || length(unique(jobs$chain)) != 4L) {
      stop("Expected four unique chains for ", case$id, "/tau=", tau, call. = FALSE)
    }
    fits <- lapply(jobs$output_dir, function(path) readRDS(file.path(path, "posterior_draws.rds")))
    expected_draws <- unique(jobs$n_mcmc)
    if (length(expected_draws) != 1L || any(vapply(fits, function(fit) nrow(fit$beta), integer(1L)) != expected_draws)) {
      stop("Retained-draw count mismatch for ", case$id, "/tau=", tau, call. = FALSE)
    }
    for (parameter in c("sigma", "gamma", "rhs_tau", "rhs_c2", "beta_l2")) {
      chains <- lapply(fits, function(fit) as.numeric(fit$scalar[[parameter]]))
      di <- di + 1L
      rhat <- safe_rhat(chains)
      ess <- safe_ess(chains)
      diagnostic_rows[[di]] <- data.frame(
        case_id = case$id, region = case$region, fold = case$fold, tau = tau,
        parameter = parameter, rhat = rhat, ess = ess,
        passed = is.finite(rhat) && rhat <= 1.01 && is.finite(ess) && ess >= 400,
        stringsAsFactors = FALSE
      )
    }
    predictions <- do.call(rbind, lapply(jobs$output_dir, function(path) {
      utils::read.csv(gzfile(file.path(path, "posterior_mean_predictions.csv.gz")), stringsAsFactors = FALSE)
    }))
    if (length(unique(predictions$chain)) != 4L) {
      stop("Prediction chain count mismatch for ", case$id, "/tau=", tau, call. = FALSE)
    }
    for (split in c("val", "test")) {
      rows <- utils::read.csv(file.path(case$adapter_dir, paste0("rows_", split, ".csv")), stringsAsFactors = FALSE)
      scale <- unique(vb$scale_factor[vb$split == split])
      if (length(scale) != 1L) stop("Metric scale changed for ", case$id, "/", split, call. = FALSE)
      chain_losses <- numeric()
      for (chain in sort(unique(predictions$chain))) {
        pred <- predictions[predictions$split == split & predictions$chain == chain, c("origin_id", "horizon", "pred_scaled")]
        if (nrow(pred) != nrow(rows) || anyDuplicated(pred[, c("origin_id", "horizon")])) {
          stop("Incomplete chain predictions for ", case$id, "/tau=", tau, "/chain=", chain, "/", split, call. = FALSE)
        }
        joined <- merge(rows[, c("origin_id", "horizon", "y_scaled")], pred, by = c("origin_id", "horizon"), sort = FALSE)
        if (nrow(joined) != nrow(rows)) stop("Prediction join mismatch", call. = FALSE)
        loss <- mean(pinball(joined$y_scaled, joined$pred_scaled, tau)) * scale
        chain_losses <- c(chain_losses, loss)
        ci <- ci + 1L
        chain_metric_rows[[ci]] <- data.frame(
          case_id = case$id, region = case$region, fold = case$fold, tau = tau,
          chain = chain, split = split, original_AQL = loss, stringsAsFactors = FALSE
        )
      }
      mean_prediction <- stats::aggregate(
        pred_scaled ~ origin_id + horizon,
        predictions[predictions$split == split, c("origin_id", "horizon", "pred_scaled")], mean
      )
      joined <- merge(rows[, c("origin_id", "horizon", "y_scaled")], mean_prediction, by = c("origin_id", "horizon"), sort = FALSE)
      if (nrow(joined) != nrow(rows)) stop("Mean-prediction join mismatch", call. = FALSE)
      m0_aql <- mean(pinball(joined$y_scaled, joined$pred_scaled, tau)) * scale
      baseline <- vb$original_AQL[vb$split == split & abs(vb$tau - tau) < 1e-12]
      if (length(baseline) != 1L || !is.finite(baseline)) {
        stop("Missing unique VB baseline for ", case$id, "/tau=", tau, "/", split, call. = FALSE)
      }
      mi <- mi + 1L
      metric_rows[[mi]] <- data.frame(
        case_id = case$id, region = case$region, fold = case$fold, tau = tau,
        split = split, m0_AQL = m0_aql, vb_replay_AQL = baseline,
        m0_minus_vb = m0_aql - baseline,
        relative_delta = m0_aql / baseline - 1,
        chain_relative_spread = (max(chain_losses) - min(chain_losses)) / mean(chain_losses),
        stringsAsFactors = FALSE
      )
    }
  }
  case_metrics <- do.call(rbind, metric_rows)[do.call(rbind, metric_rows)$case_id == case$id, , drop = FALSE]
  case_diagnostics <- do.call(rbind, diagnostic_rows)[do.call(rbind, diagnostic_rows)$case_id == case$id, , drop = FALSE]
  val <- case_metrics[case_metrics$split == "val", , drop = FALSE]
  test <- case_metrics[case_metrics$split == "test", , drop = FALSE]
  m0_val <- mean(val$m0_AQL)
  vb_val <- mean(val$vb_replay_AQL)
  m0_test <- mean(test$m0_AQL)
  validation_selected <- is.finite(m0_val) && m0_val < vb_val - 1e-10
  validation_harm_pass <- all(val$relative_delta <= 0.005 + 1e-12)
  diagnostics_pass <- all(case_diagnostics$passed)
  chain_stability_pass <- all(case_metrics$chain_relative_spread <= 0.005 + 1e-12)
  beats_qdesn <- m0_test < as.numeric(case_summary$authority_qdesn_AQL)
  case_cfg <- yaml::read_yaml(case$config)$pricefm_stage_r52_case
  beats_pricefm <- m0_test < as.numeric(case_cfg$cached_pricefm_AQL)
  internal <- validation_selected && validation_harm_pass && diagnostics_pass && chain_stability_pass &&
    isTRUE(case_summary$promotion_replay_eligible) && beats_qdesn
  article <- internal && beats_pricefm
  case_rows[[case_index]] <- data.frame(
    case_id = case$id, region = case$region, fold = case$fold,
    m0_validation_AQL = m0_val, vb_replay_validation_AQL = vb_val,
    m0_test_AQL = m0_test, authority_qdesn_AQL = as.numeric(case_summary$authority_qdesn_AQL),
    cached_pricefm_AQL = as.numeric(case_cfg$cached_pricefm_AQL),
    validation_selected = validation_selected, validation_harm_guard_pass = validation_harm_pass,
    diagnostics_pass = diagnostics_pass, chain_stability_pass = chain_stability_pass,
    authority_replay_pass = isTRUE(case_summary$promotion_replay_eligible),
    beats_authoritative_qdesn = beats_qdesn, beats_cached_pricefm = beats_pricefm,
    internal_registry_promotion_candidate = internal,
    article_pricefm_promotion_candidate = article,
    decision = if (article) "dual_reference_article_review" else if (internal) "internal_qdesn_upgrade_review" else "retain_current_authority",
    registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE,
    stringsAsFactors = FALSE
  )
}

diagnostics <- do.call(rbind, diagnostic_rows)
metrics <- do.call(rbind, metric_rows)
chain_metrics <- do.call(rbind, chain_metric_rows)
decisions <- do.call(rbind, case_rows)
utils::write.csv(diagnostics, file.path(out, "pricefm_stage_r54_chain_diagnostics.csv"), row.names = FALSE)
utils::write.csv(metrics, file.path(out, "pricefm_stage_r54_quantile_metrics.csv"), row.names = FALSE)
utils::write.csv(chain_metrics, file.path(out, "pricefm_stage_r54_chain_metrics.csv"), row.names = FALSE)
utils::write.csv(decisions, file.path(out, "pricefm_stage_r54_case_decisions.csv"), row.names = FALSE)
utils::write.csv(decisions[decisions$internal_registry_promotion_candidate, ], file.path(out, "pricefm_stage_r54_internal_promotion_review_queue.csv"), row.names = FALSE)
utils::write.csv(decisions[decisions$article_pricefm_promotion_candidate, ], file.path(out, "pricefm_stage_r54_article_promotion_review_queue.csv"), row.names = FALSE)

summary <- list(
  status = "completed_read_only_closeout", cases = nrow(decisions), chain_jobs = nrow(manifest),
  validation_selected_cases = sum(decisions$validation_selected),
  internal_promotion_candidates = sum(decisions$internal_registry_promotion_candidate),
  article_promotion_candidates = sum(decisions$article_pricefm_promotion_candidate),
  registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE
)
writeLines(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), file.path(out, "summary.json"))
writeLines(c(
  "# PriceFM Stage-R54 collapsed-M0 closeout", "",
  "This closeout freezes seven-quantile bundle selection on validation, then audits test performance against both current authoritative Q-DESN and cached PriceFM.", "",
  "The internal queue requires improvement over authoritative Q-DESN. The article queue additionally requires improvement over PriceFM. Neither queue mutates the registry or article automatically."
), file.path(out, "pricefm_stage_r54_exal_m0_closeout_report.md"))
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")
