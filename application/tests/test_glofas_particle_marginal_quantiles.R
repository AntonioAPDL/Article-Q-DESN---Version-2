local({
  source("scripts/diagnostics/glofas_particle_marginal_quantiles.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(x) ok(inherits(try(force(x), silent = TRUE), "try-error"))
  make <- function(offset, weights = c(.2, .3, .5)) list(
    complete = TRUE,
    paths = cbind(c(0, 1, 2) + offset, c(.5, 1.5, 2.5) + offset),
    weights = weights,
    initial_ancestor_ids = c(1L, 1L, 3L),
    diagnostics = data.frame(horizon = 1:2, effective_sample_size = c(2, 2)),
    completed_horizons = 2L,
    no_resampling_between_correction_and_next_member = TRUE)
  draws <- lapply(c(0, .1, .2, .3), make)
  out <- gpmq_format(draws, c(.0001, .5, .9999))
  ok(nrow(out) == 6L && all(out$outer_draws == 4L) &&
    all(out$total_particle_paths == 12L))
  ok(out$quantile_transformed[out$horizon == 1 & out$probability == .0001] == 0)
  ok(out$quantile_transformed[out$horizon == 1 & out$probability == .9999] == 2.3)
  ok(max(abs(out$quantile_original - expm1(out$quantile_transformed))) < 1e-15)
  ok(all(is.finite(out$outer_cluster_jackknife_mcse_transformed)))
  contract <- attr(out, "formatter_contract")
  ok(contract$terminal_weights && !contract$filtering_h_weights &&
    !contract$evidence_reweighted_outer_draws && !contract$gaussian_delta_used)
  # Terminal weights from the final member factors affect the pooled CDF.
  shifted <- draws
  shifted[[1L]]$weights <- c(.98, .01, .01)
  a <- gpmq_format(draws, .2)$quantile_transformed[1L]
  b <- gpmq_format(shifted, .2)$quantile_transformed[1L]
  ok(a != b)
  # Equal outer weighting is not evidence weighting and cloned ancestors are
  # paths inside one tree, not independent MCSE replicates.
  ok(all(out$outer_weight_policy == "equal_one_over_B_no_evidence_reweighting"))
  ok(all(out$particle_weight_policy ==
    "normalized_terminal_H_weights_within_outer_draw"))
  single <- gpmq_format(draws[1L], .5)
  ok(all(is.na(single$outer_cluster_jackknife_mcse_transformed)))
  bad <- draws; bad[[1L]]$complete <- FALSE
  reject(gpmq_format(bad, .5))
  bad <- draws; bad[[1L]]$diagnostics <- bad[[1L]]$diagnostics[1L, , drop = FALSE]
  reject(gpmq_format(bad, .5))
  reject(gpmq_format(draws, c(0, .5)))
  reject(gpmq_format(draws, .5, transform = "identity"))
  reject(gpmq_weighted_inverse_cdf(1:3, c(1, -1, 1), .5))
  cat(sprintf("GLOFAS_PARTICLE_MARGINAL_QUANTILES_PASS checks=%d authentic_reads=0 model_runs=0\n", n))
})
