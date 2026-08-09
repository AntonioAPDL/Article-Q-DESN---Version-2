#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(coda)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
artifact <- "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm"
prep <- arg("--prep-dir", file.path(artifact, "authoritative/pricefm_stage_r50_mcmc_confirmation_launch_prep_20260809"))
out <- arg("--output-dir", file.path(artifact, "authoritative/pricefm_stage_r50_mcmc_confirmation_closeout_20260809"))
force <- tolower(arg("--force", "false")) %in% c("1", "true", "yes")
if (dir.exists(out) && length(list.files(out)) && !force) stop("Output exists: ", out, call. = FALSE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)

manifest <- read.csv(file.path(prep, "pricefm_stage_r50_launch_manifest.csv"), stringsAsFactors = FALSE)
if (nrow(manifest) != 56L) stop("R50 closeout requires 56 jobs", call. = FALSE)
summaries <- lapply(manifest$output_dir, function(path) {
  f <- file.path(path, "job_summary.json")
  if (!file.exists(f)) stop("Missing job summary: ", f, call. = FALSE)
  fromJSON(f)
})
if (!all(vapply(summaries, function(x) identical(x$status, "completed") && isTRUE(x$finite_draws), logical(1)))) {
  stop("R50 has incomplete or nonfinite jobs", call. = FALSE)
}

safe_rhat <- function(chains) {
  tryCatch(as.numeric(gelman.diag(mcmc.list(lapply(chains, mcmc)), autoburnin = FALSE, multivariate = FALSE)$psrf[, 1L]), error = function(e) NA_real_)
}
safe_ess <- function(chains) {
  tryCatch(as.numeric(effectiveSize(mcmc.list(lapply(chains, mcmc)))), error = function(e) NA_real_)
}
diag_rows <- list()
index <- 0L
for (component in unique(manifest$component)) {
  for (tau in sort(unique(manifest$tau))) {
    jobs <- manifest[manifest$component == component & abs(manifest$tau - tau) < 1e-12, ]
    fits <- lapply(jobs$output_dir, function(path) readRDS(file.path(path, "posterior_draws.rds")))
    for (parameter in c("sigma", "gamma", "rhs_tau", "rhs_c2", "beta_l2")) {
      chains <- lapply(fits, function(x) x$scalar[[parameter]])
      index <- index + 1L
      diag_rows[[index]] <- data.frame(component = component, tau = tau, parameter = parameter,
        max_rhat = max(safe_rhat(chains), na.rm = TRUE), min_ess = min(safe_ess(chains), na.rm = TRUE), gate_scope = "hard")
    }
    beta_chains <- lapply(fits, function(x) x$beta)
    index <- index + 1L
    diag_rows[[index]] <- data.frame(component = component, tau = tau, parameter = "beta_coefficients",
      max_rhat = max(safe_rhat(beta_chains), na.rm = TRUE), min_ess = min(safe_ess(beta_chains), na.rm = TRUE), gate_scope = "review_rank_deficient_design")
  }
}
diagnostics <- do.call(rbind, diag_rows)
diagnostics$passed <- ifelse(diagnostics$gate_scope == "hard",
  diagnostics$max_rhat <= 1.05 & diagnostics$min_ess >= 200,
  diagnostics$max_rhat <= 1.10 & diagnostics$min_ess >= 100)
write.csv(diagnostics, file.path(out, "pricefm_stage_r50_chain_diagnostics.csv"), row.names = FALSE)

predictions <- do.call(rbind, lapply(manifest$output_dir, function(path) read.csv(file.path(path, "posterior_mean_predictions.csv"), stringsAsFactors = FALSE)))
aggregate_pred <- aggregate(pred_scaled ~ component + chain + split + origin_id + horizon + tau, predictions, mean)
rows_dir <- file.path(dirname(manifest$output_dir[[1L]]), "frozen_adapter")
r47_model <- "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runs/pricefm_stage_r47_frozen_test_audit_20260808/r47_no3_f3_nestedhorizonsep_81e260ce/cells/region=NO_3/fold=3/model"
r48 <- read.csv(file.path(artifact, "authoritative/pricefm_stage_r48_frozen_test_audit_closeout_20260808/pricefm_stage_r48_mcmc_confirmation_queue.csv"), stringsAsFactors = FALSE)
pinball <- function(y, p, tau) ifelse(y >= p, tau * (y - p), (1 - tau) * (p - y))
blocks <- function(h) paste0(((h - 1L) %/% 24L) * 24L + 1L, "-", pmin(((h - 1L) %/% 24L) * 24L + 24L, 96L))

surface_rows <- list()
for (split in c("val", "test")) {
  truth <- read.csv(file.path(rows_dir, paste0("rows_", split, ".csv")), stringsAsFactors = FALSE)[, c("origin_id", "horizon", "y_scaled")]
  for (chain in sort(unique(aggregate_pred$chain))) {
    sh <- aggregate_pred[aggregate_pred$component == "shared_static" & aggregate_pred$chain == chain & aggregate_pred$split == split, ]
    bl <- aggregate_pred[aggregate_pred$component == "horizon_1_24" & aggregate_pred$chain == chain & aggregate_pred$split == split, ]
    names(sh)[names(sh) == "pred_scaled"] <- "shared"
    names(bl)[names(bl) == "pred_scaled"] <- "block"
    d <- merge(sh[, c("origin_id", "horizon", "tau", "shared")], truth, by = c("origin_id", "horizon"))
    d <- merge(d, bl[, c("origin_id", "horizon", "tau", "block")], by = c("origin_id", "horizon", "tau"), all.x = TRUE)
    d$pooled <- d$shared
    use <- d$horizon <= 24L
    d$pooled[use] <- 0.75 * d$shared[use] + 0.25 * d$block[use]
    d$chain <- chain
    d$split <- split
    d$shared_loss <- pinball(d$y_scaled, d$shared, d$tau)
    d$pooled_loss <- pinball(d$y_scaled, d$pooled, d$tau)
    d$horizon_group <- blocks(d$horizon)
    surface_rows[[length(surface_rows) + 1L]] <- d
  }
}
surface <- do.call(rbind, surface_rows)
chain_metrics <- aggregate(cbind(shared_loss, pooled_loss) ~ chain + split, surface, mean)
write.csv(chain_metrics, file.path(out, "pricefm_stage_r50_chain_prediction_metrics_scaled.csv"), row.names = FALSE)

mean_surface <- aggregate(cbind(shared, pooled, y_scaled) ~ split + origin_id + horizon + tau + horizon_group, surface, mean)
mean_surface$shared_loss <- pinball(mean_surface$y_scaled, mean_surface$shared, mean_surface$tau)
mean_surface$pooled_loss <- pinball(mean_surface$y_scaled, mean_surface$pooled, mean_surface$tau)
r47_metric <- read.csv(file.path(r47_model, "metric_summary.csv"), stringsAsFactors = FALSE)
r47_shared_test <- r47_metric[r47_metric$method_id == "qdesn_exal_rhs_ns_exact_chunked" & r47_metric$split == "test", ]
scale <- r47_shared_test$AQL[r47_shared_test$unit == "original"] / r47_shared_test$AQL[r47_shared_test$unit == "scaled"]
test <- mean_surface[mean_surface$split == "test", ]
val <- mean_surface[mean_surface$split == "val", ]
test_aql <- mean(test$pooled_loss) * scale
shared_test_aql <- mean(test$shared_loss) * scale
val_improves <- mean(val$pooled_loss) < mean(val$shared_loss)

quantile <- aggregate(cbind(shared_loss, pooled_loss) ~ tau, test, mean)
quantile$relative_delta <- quantile$pooled_loss / quantile$shared_loss - 1
quantile$harm_guard_pass <- quantile$relative_delta <= 0.005 + 1e-12
horizon <- aggregate(cbind(shared_loss, pooled_loss) ~ tau + horizon_group, test, mean)
horizon$relative_delta <- horizon$pooled_loss / horizon$shared_loss - 1
horizon$harm_guard_pass <- horizon$relative_delta <= 0.005 + 1e-12
write.csv(quantile, file.path(out, "pricefm_stage_r50_quantile_harm_audit.csv"), row.names = FALSE)
write.csv(horizon, file.path(out, "pricefm_stage_r50_horizon_harm_audit.csv"), row.names = FALSE)

chain_test <- chain_metrics[chain_metrics$split == "test", ]
chain_spread <- (max(chain_test$pooled_loss) - min(chain_test$pooled_loss)) / mean(chain_test$pooled_loss)
hard_convergence <- all(diagnostics$passed[diagnostics$gate_scope == "hard"])
beta_review <- all(diagnostics$passed[diagnostics$gate_scope != "hard"])
beats_qdesn <- test_aql < r48$authoritative_qdesn_AQL[[1L]]
beats_pricefm <- test_aql < r48$cached_pricefm_AQL[[1L]]
harm <- all(quantile$harm_guard_pass) && all(horizon$harm_guard_pass)
eligible <- hard_convergence && beta_review && chain_spread <= 0.005 && val_improves && harm && beats_qdesn && beats_pricefm
decision <- data.frame(
  region = "NO_3", fold = 3L, mcmc_pooled_test_AQL = test_aql, mcmc_shared_test_AQL = shared_test_aql,
  authoritative_qdesn_AQL = r48$authoritative_qdesn_AQL[[1L]], cached_pricefm_AQL = r48$cached_pricefm_AQL[[1L]],
  beats_authoritative_qdesn = beats_qdesn, beats_cached_pricefm = beats_pricefm,
  hard_convergence_pass = hard_convergence, beta_review_pass = beta_review,
  chain_prediction_spread = chain_spread, chain_stability_pass = chain_spread <= 0.005,
  validation_direction_pass = val_improves, test_harm_guard_pass = harm,
  promotion_eligible = eligible,
  decision = if (eligible) "eligible_for_registry_article_promotion_review" else "blocked_r50_mcmc_confirmation_gate",
  registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE
)
write.csv(decision, file.path(out, "pricefm_stage_r50_confirmation_decision.csv"), row.names = FALSE)
write.csv(if (eligible) decision else decision[FALSE, ], file.path(out, "pricefm_stage_r50_promotion_review_queue.csv"), row.names = FALSE)
summary <- list(status = "completed_mcmc_confirmation_closeout", jobs = 56L,
  promotion_candidates = if (eligible) 1L else 0L, decision = decision$decision,
  registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE)
writeLines(toJSON(summary, auto_unbox = TRUE, pretty = TRUE), file.path(out, "summary.json"))
writeLines(c("# PriceFM Stage-R50 MCMC confirmation closeout", "",
  "The closeout combines four independent chains for each frozen quantile/component, applies the frozen 0.25 prediction-pooling weight at horizons 1-24, and repeats the dual-reference and harm-guard gates.", "",
  "Registry and article mutation remain a separate reviewed action even when the promotion queue is nonempty."),
  file.path(out, "pricefm_stage_r50_mcmc_confirmation_closeout_report.md"))
cat(toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")
