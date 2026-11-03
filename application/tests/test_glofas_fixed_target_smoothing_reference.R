# Generated only: exact target reference, never application-data retuning.
local({
  source("application/R/glofas_fixed_target_smoothing_reference.R", local = TRUE)
  result <- gftsr_run_smoothing_diagnostics()
  stopifnot(result$scientific_runs == 0L, result$authentic_reads == 0L,
            all(result$checks$reference_validity == "PASS"),
            all(result$checks$numerical_stability == "PASS"),
            nrow(result$quantiles) == 14L,
            max(abs(result$quantiles$exact_cdf - result$quantiles$probability)) < 1e-8)
  one <- subset(result$cases, n_members == 1)
  many <- subset(result$cases, n_members == 51)
  stopifnot(abs(one$exact_median_y1) < .05,
            many$exact_median_y1 < -1.9,
            many$exact_median_y1 > -2.1,
            abs(many$exact_median_y1 - one$exact_median_y1) > 1.8,
            abs(many$mean_field_y2_mean) < 1e-12,
            abs(one$mean_field_y2_mean) < 1e-12,
            any(result$checks$implementation_parity == "NOT_ASSESSED"))
  # The exact reference is independent of the production coordinate helper.
  c1 <- gftsr_contract(51L)
  stopifnot(abs(gftsr_piecewise_cdf(-Inf, c1)) < 1e-14,
            abs(gftsr_piecewise_cdf(Inf, c1) - 1) < 1e-14,
            abs(gftsr_cdf(-Inf, c1)) < 1e-14,
            abs(gftsr_cdf(Inf, c1) - 1) < 1e-14,
            inherits(try(gftsr_contract(0), silent = TRUE), "try-error"))
  message("GloFAS generated smoothing reference: ", nrow(result$checks),
          " checks; exact median n=1: ", signif(one$exact_median_y1, 8),
          "; n=51: ", signif(many$exact_median_y1, 8),
          ". No application-weight change implied.")
})
