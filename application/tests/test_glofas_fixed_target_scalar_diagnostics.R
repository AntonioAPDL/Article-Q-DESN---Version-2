# Generated-only, standalone or suite-loaded diagnostic regression.
local({
  test_repo <- if (exists("repo_root", inherits = TRUE)) {
    normalizePath(get("repo_root", inherits = TRUE), mustWork = TRUE)
  } else if (file.exists("scripts/diagnostics/glofas_fixed_target_scalar_diagnostics.R")) {
    normalizePath(".", mustWork = TRUE)
  } else {
    script <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    if (length(script) != 1L) stop("Cannot locate diagnostic repository.")
    normalizePath(file.path(dirname(sub("^--file=", "", script)), "..", ".."),
                  mustWork = TRUE)
  }
  source(file.path(test_repo, "scripts/diagnostics/glofas_fixed_target_scalar_diagnostics.R"),
         local = environment())
  results <- app_gftd_scalar_diagnostics(test_repo)
  stopifnot(nrow(results) == 42L,
            all(results$reference_validity == "PASS"),
            all(results$implementation_parity == "PASS"),
            all(results$numerical_stability == "PASS"),
            all(is.finite(results$reported_quantile)),
            all(results$variance > 0))
  stopifnot(max(results$mixture_cdf_at_location_error) <= 1e-8,
            max(results$mixture_cdf_reference_error) <= 1e-8,
            max(results$mixture_cdf_tightening_error) <= 1e-8,
            max(results$mixture_cdf_estimated_absolute_error) <= 1e-8)

  # An expected accuracy failure is retained, not converted into a pass because
  # the implemented algorithm agrees with its own fixed-point equations.
  tail <- results$p %in% c(.05, .95)
  stopifnot(all(results$approximation_accuracy[tail] == "FAIL"),
            all(results$cdf_error[tail] > .08),
            all(results$approximation_accuracy[results$p == .5] == "PASS"))
  primary <- subset(results, sigma == 1 & jitter == 0)
  stopifnot(abs(primary$exact_cdf_at_reported_quantile[primary$p == .05] -
                  .137242999595) < 1e-10,
            abs(primary$exact_cdf_at_reported_quantile[primary$p == .95] -
                  .862757000405) < 1e-10,
            sum(!is.na(results$member_cancellation_error)) == 7L,
            max(results$member_cancellation_error, na.rm = TRUE) < 1e-12)

  for (p in c(.05, .2, .5, .8, .95)) {
    contrast <- app_gftd_scalar_marginal_gaussian_reference(p, sigma = .7, mu = 1.2)
    stopifnot(abs(contrast$quantile - 1.2) < 1e-12,
              grepl("not_a_qualified", contrast$role))
  }
  # The numerical Normal-mixture CDF, not the analytic AL CDF, independently
  # confirms location targeting and scale invariance at nonzero responses.
  for (p in c(.05, .5, .95)) for (z in c(-1, 0, 1)) {
    unit <- app_gftd_scalar_mixture_cdf_reference(z, p)$value
    for (sigma in c(.1, 10)) {
      scaled <- app_gftd_scalar_mixture_cdf_reference(.3 + sigma * z, p,
                                                      sigma = sigma, mu = .3)$value
      stopifnot(abs(unit - scaled) < 1e-10)
    }
  }
  information <- app_gftd_scalar_no_information_reference(2, .5)
  stopifnot(abs(information$exact_theta_variance - information$exact_expected) < 1e-12,
            abs(information$product_vb_theta_variance -
                  information$product_vb_expected) < 1e-12,
            information$product_vb_theta_variance < information$exact_theta_variance)

  # A corrupted production constant must fail reference/parity checks, rather
  # than being accepted merely because the generated iteration stabilizes.
  bad_engine <- app_gftd_scalar_production_namespace(test_repo)
  original_constants <- bad_engine$app_latent_al_constants
  bad_engine$app_latent_al_constants <- function(p0) {
    out <- original_constants(p0)
    out$B <- 1.02 * out$B
    out
  }
  bad <- app_gftd_scalar_diagnostics(test_repo, probabilities = .5,
    scales = 1, jitters = 0, production_env = bad_engine)
  stopifnot(identical(bad$implementation_parity, "FAIL"),
            identical(bad$reference_validity, "FAIL"))

  # The coordinator-facing schema must not collapse the accuracy failure into
  # the successful numerical/implementation status.
  required <- c("reference_validity", "implementation_parity", "numerical_stability",
                "approximation_accuracy", "production_relevance")
  stopifnot(all(required %in% names(results)),
            any(results$implementation_parity == "PASS" &
                  results$approximation_accuracy == "FAIL"))

  # Input validation is part of the reference's integrity gate.
  stopifnot(inherits(try(app_gftd_scalar_reference(0), silent = TRUE), "try-error"),
            inherits(try(app_gftd_scalar_reference(.5, sigma = 0), silent = TRUE), "try-error"),
            inherits(try(app_gftd_scalar_reference(.5, jitter = -1), silent = TRUE), "try-error"))
  message("GloFAS fixed-target scalar diagnostics: ", nrow(results),
          " generated cases; parity and numerical stability PASS; ",
          sum(results$approximation_accuracy == "FAIL"),
          " approximation-accuracy FAIL results retained.")
})
