# Standalone generated-only diagnostic test; no retained objects or fits.
local({
  source("scripts/diagnostics/glofas_fixed_target_affine_diagnostics.R", local = TRUE)
  out <- gfta_run_affine_diagnostics()
  stopifnot(identical(out$scientific_runs, 0L), identical(out$authentic_reads, 0L))
  stopifnot(nrow(out$checks) >= 30L)
  stopifnot(all(out$checks$reference_validity == "PASS"))
  stopifnot(all(out$checks$implementation_parity == "PASS"))
  stopifnot(all(out$checks$numerical_stability == "PASS"))
  stopifnot(any(out$checks$production_relevance == "reference_fixture_only"))
  stopifnot(all(vapply(out$fixtures[grep("gaussian", names(out$fixtures))], function(x)
    x$jitter_covariance_error > 0, logical(1L))))
  # Deliberately increased jitter changes operational covariance but is not a
  # prior centred at zero and must not change the incremental mean fixed point.
  a <- out$fixtures$`gaussian_h2_j1e-08`
  b <- out$fixtures$`gaussian_h2_j5e-03`
  stopifnot(!is.null(a), !is.null(b), max(abs(a$mean - b$mean)) < 1e-10)
  stopifnot(max(abs(a$operational_covariance - b$operational_covariance)) > 1e-5)
  # A generated source-mutation control must be detected by the independent
  # oracle. It does not edit the production file or any retained object.
  broken <- gfta_engine()
  original <- broken$app_latent_update_future_gaussian_delta
  broken$app_latent_update_future_gaussian_delta <- function(...) {
    z <- original(...)
    z$cov <- z$cov * 1.1
    z
  }
  bad <- gfta_run_affine_diagnostics(broken)
  stopifnot(any(bad$checks$implementation_parity == "FAIL"))
  stopifnot(any(bad$checks$implementation_parity[grepl("operational_covariance", bad$checks$test_id)] == "FAIL"))
  cat("GloFAS fixed-target affine diagnostics: ", nrow(out$checks), " checks PASS; generated-only.\n", sep = "")
})
