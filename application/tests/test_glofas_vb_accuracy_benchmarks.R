# Generated targets only. A passing software test deliberately retains every
# approximation-accuracy failure; it is not application inference approval.
local({
  source("scripts/diagnostics/glofas_vb_accuracy_benchmarks.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_gaussian_reference.R", local = TRUE)
  original_sources <- c("application/R/latent_path_vb_al.R", "application/R/latent_path_vb_normal.R")
  before <- tools::md5sum(original_sources)
  old_rng <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  checks <- 0L
  ok <- function(condition) { stopifnot(isTRUE(condition)); checks <<- checks + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  out <- gvab_run_benchmarks()
  ok(identical(out$scientific_runs, 0L) && identical(out$authentic_reads, 0L))
  ok(identical(out$full_parameter_refits, 0L) && identical(out$production_change, FALSE))
  ok(nrow(out$checks) == 19L && all(out$checks$reference_validity == "PASS"))
  ok(all(out$checks$implementation_parity == "PASS"))
  ok(all(out$checks$numerical_stability == "PASS"))
  ok(all(out$checks$approximation_accuracy == "FAIL"))
  ok(nrow(out$normal_coefficient) == 3L && nrow(out$al_coefficient) == 9L &&
    nrow(out$unknown_scale) == 4L && nrow(out$two_horizon) == 3L)
  ok(all(out$blocked$status == "NOT_QUALIFIED") && nrow(out$blocked) == 6L)

  normal <- out$normal_coefficient
  ok(max(abs(normal$exact_theta_mean - normal$vb_theta_mean)) < 1e-9)
  ok(all(normal$vb_theta_variance < normal$exact_theta_variance))
  ok(all(normal$vb_future_variance < normal$exact_future_variance))
  ok(all(normal$exact_theta_future_covariance > 0) && all(normal$vb_theta_future_covariance == 0))
  empty <- normal[normal$n_members == 0, ]
  ok(abs(empty$exact_theta_variance - 1.1) < 1e-14)
  ok(abs(empty$vb_theta_variance - 1 / (1 / 1.1 + 1 / .8)) < 1e-12)
  # Exact joint covariance is representable in a joint Gaussian, but not in
  # the current separate theta/path API. This reference is not a new method.
  joint <- gcgr_normal_coupled_reference(.4, matrix(1.1), 1, .8)
  ok(abs(joint$coupled_KL) < 1e-12)
  ok(joint$independent_future_block_KL > .1)
  ok(abs(joint$independent_future_block_theta_covariance[1L] - empty$vb_theta_variance) < 1e-12)
  ok(max(abs(joint$covariance - matrix(c(1.1, 1.1, 1.1, 1.9), 2L))) < 1e-14)
  # Issued factors do legitimately update theta. No-member invariance must
  # not be incorrectly demanded after conditioning on members.
  ok(abs(normal$exact_theta_mean[normal$n_members == 51] - .4) > .1)
  ok(normal$exact_theta_variance[normal$n_members == 51] < .02)

  al <- out$al_coefficient
  empty <- al[al$n_members == 0, ]
  ok(max(abs(empty$exact_theta_mean - .1)) < 1e-9)
  ok(max(abs(empty$exact_theta_variance - .09)) < 1e-9)
  ok(all(empty$vb_theta_variance < empty$exact_theta_variance))
  ok(all(al$exact_theta_future_covariance > 0) && all(al$vb_theta_future_covariance == 0))
  ok(all(is.finite(al$exact_CDF_at_vb_quantile)) &&
    all(al$exact_CDF_at_vb_quantile > 0 & al$exact_CDF_at_vb_quantile < 1))
  # A symmetric marginal median may be exact while the parameter variance
  # and complete joint distribution remain inaccurate.
  ok(empty$absolute_CDF_error[empty$probability == .5] < 1e-8)
  ok(all(empty$absolute_CDF_error[empty$probability != .5] > .02))
  ok(sum(al$selected_quantile_accuracy == "PASS") == 2L)
  ok(all(empty$no_member_parameter_invariance == "FAIL"))

  scales <- out$unknown_scale
  ok(all(scales$exact_scale_shape == 3) && all(scales$exact_scale_rate == .4))
  ok(all(scales$vb_scale_shape > scales$exact_scale_shape))
  ok(all(scales$vb_scale_mean < scales$exact_scale_mean))
  ok(all(scales$vb_future_variance < scales$exact_future_variance))
  ok(all(abs(scales$vb_scale_shape / scales$vb_scale_rate - 3 / .4) < 1e-8))
  ok(sum(scales$selected_quantile_accuracy == "PASS") == 1L)
  # Independent integration over the precision, rather than reuse of the
  # analytic Student-t or AL/IG-mixture CDF, checks each predictive reference.
  for (i in seq_len(nrow(scales))) {
    r <- scales[i, ]; p <- r$probability
    b <- .4; a <- 3
    actual_quantile <- r$vb_future_mean + stats::qnorm(r$scored_probability) * sqrt(r$vb_future_variance)
    e <- actual_quantile - .3
    conditional_cdf <- if (r$family == "normal") {
      function(precision) stats::pnorm(e * sqrt(precision))
    } else if (e < 0) {
      function(precision) p * exp((1 - p) * e * precision)
    } else {
      function(precision) 1 - (1 - p) * exp(-p * e * precision)
    }
    numerical <- stats::integrate(function(precision) conditional_cdf(precision) *
      stats::dgamma(precision, shape = a, rate = b), 0, Inf,
      rel.tol = 1e-11, abs.tol = 1e-12)$value
    ok(abs(numerical - r$exact_CDF_at_vb_quantile) < 1e-9)
  }

  two <- out$two_horizon
  ok(max(two$normalization_error, two$tightening_error,
    two$independent_integration_order_error) < 1e-8)
  empty <- two[two$n_members == 0, ]
  ok(abs(empty$exact_theta_mean - .4) < 1e-10 && abs(empty$exact_theta_variance - .16) < 1e-10)
  ok(abs(empty$exact_y1_mean - .4) < 1e-10 && abs(empty$exact_y1_variance - .76) < 1e-10)
  ok(abs(empty$exact_theta_y1_covariance - .16) < 1e-10)
  ok(empty$vb_theta_variance < empty$exact_theta_variance)
  ok(all(abs(two$exact_theta_y1_covariance) > 1e-4) && all(two$vb_theta_y1_covariance == 0))
  ok(all(abs(two$exact_y1_y2_covariance) > 1e-4) && all(two$vb_y1_y2_covariance == 0))
  # Accuracy is not inferred from a single quantile: the 51-member lower
  # quantile passes .005 while its parameter variance/covariance still fail.
  ok(two$absolute_CDF_error[two$n_members == 51] < .005)
  ok(two$absolute_CDF_error[two$n_members == 0] > .005)
  ok(sum(two$selected_quantile_accuracy == "PASS") == 1L)
  ok(abs(two$exact_theta_mean[two$n_members == 51] - .4) > .3)

  engine <- gvab_engine()
  a <- gvab_iterate(engine, "normal", prior_mean = .4, prior_variance = 1.1,
    response_scale = .8, member_scale = .5)
  # Deliberate in-memory mutations must fail the independent parity oracle;
  # source files and scientific targets remain untouched.
  altered <- gvab_engine()
  theta_original <- altered$app_latent_update_theta
  altered$app_latent_update_theta <- function(...) {
    z <- theta_original(...); z$cov <- 1.05 * z$cov; z
  }
  b <- gvab_iterate(altered, "normal", prior_mean = .4, prior_variance = 1.1,
    response_scale = .8, member_scale = .5)
  ok(abs(a$theta_variance - b$theta_variance) > .01)
  altered <- gvab_engine()
  path_original <- altered$app_latent_update_future_gaussian_delta
  altered$app_latent_update_future_gaussian_delta <- function(...) {
    z <- path_original(...); z$cov <- 1.05 * z$cov; z
  }
  c <- gvab_iterate(altered, "normal", prior_mean = .4, prior_variance = 1.1,
    response_scale = .8, member_scale = .5)
  ok(abs(c$path_covariance[1L] - .8) > .01)
  reject(gvab_members(52))
  reject(gvab_iterate(engine, probability = 0))
  reject(gvab_iterate(engine, response_scale = -1))
  reject(gvab_iterate(engine, unknown_scale = TRUE))
  reject(gvab_iterate(engine, max_iterations = 10001))
  reject(gvab_rows(0, .1, c(0, 0), matrix(1, 2, 2)))
  # Bounded incomplete calculations remain incomplete, not qualified.
  short <- gvab_iterate(engine, "al", probability = .05, max_iterations = 1L)
  ok(!short$converged && short$iterations == 1L)
  ok(identical(unname(before), unname(tools::md5sum(original_sources))))
  new_rng <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  ok(identical(old_rng, new_rng))
  # Exercise the real export entry point. A missing path may have NA from
  # Sys.readlink: it must be admitted, while links and overwrites must not.
  source("scripts/audit_glofas_innovation_generated.R", local = TRUE)
  export_parent <- tempfile("giga_generated_test_", tmpdir = file.path(getwd(), "local_trackers"))
  dir.create(export_parent, recursive = TRUE, mode = "0700")
  on.exit(unlink(export_parent, recursive = TRUE), add = TRUE)
  export_path <- file.path(export_parent, "new_output")
  exported <- giga_main(c("--out-dir", export_path))
  ok(file.exists(file.path(export_path, "artifact_manifest.csv")))
  ok(length(list.files(export_path)) == 8L && !exported$reference_qualified)
  ok(exported$authentic_reads == 0L && exported$scientific_runs == 0L)
  reject(giga_main(c("--out-dir", export_path)))
  reject(giga_main(c("--out-dir", file.path(tempdir(), "not_in_ignored_tree"))))
  link_path <- file.path(export_parent, "output_link")
  ok(file.symlink(export_path, link_path))
  reject(giga_main(c("--out-dir", link_path)))
  cat(sprintf("GLOFAS_VB_ACCURACY_BENCHMARKS_PASS checks=%d cases=%d software_parity_passes=%d complete_target_accuracy_failures=%d original_reads=0 production_fits=0\n",
    checks, nrow(out$checks), sum(out$checks$implementation_parity == "PASS"),
    sum(out$checks$approximation_accuracy == "FAIL")))
})
