#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application", "R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts", "_joint_qdesn_persistent_tail_v8_bootstrap.R"))

# Numerical support violations use an exact tail-stable draw, never clipping.
calls <- 0L
one_bad <- function(n, mean, sd, lower, upper) {
  calls <<- calls + 1L
  c(-0.25, 0.4, 0.6)
}
fallback_calls <- 0L
known_fallback <- function(n, mean, sd, lower, upper) {
  fallback_calls <<- fallback_calls + 1L
  stopifnot(n == 1L, identical(mean, 0), identical(lower, 0))
  out <- 0.37
  attr(out, "tail_proposal_count") <- 2L
  out
}
draw <- app_joint_qvp_rtruncnorm_support_safe(3L, mean = 0, sd = 1,
  lower = 0, draw_fun = one_bad, tail_fallback_fun = known_fallback)
stopifnot(identical(as.numeric(draw), c(0.37, 0.4, 0.6)),
  attr(draw, "support_redraw_count") == 1L,
  attr(draw, "tail_fallback_count") == 1L,
  attr(draw, "tail_proposal_count") == 2L,
  calls == 1L, fallback_calls == 1L,
  draw[[1L]] != 0)

# Persistent generator defects fail closed instead of creating a boundary atom.
always_bad <- function(n, mean, sd, lower, upper) rep(-1, n)
error <- tryCatch({
  app_joint_qvp_rtruncnorm_support_safe(2L, mean = 0, sd = 1,
    lower = 0, max_redraw_rounds = 2L, draw_fun = always_bad,
    tail_fallback_fun = always_bad)
  NULL
}, error = identity)
stopifnot(inherits(error, "error"),
  grepl("repeatedly violated", conditionMessage(error), fixed = TRUE))

# The production generator satisfies its declared nonnegative support.
set.seed(20261127)
production <- app_joint_qvp_rtruncnorm_support_safe(1000L,
  mean = seq(-8, 8, length.out = 1000L), sd = 1, lower = 0)
stopifnot(length(production) == 1000L, all(is.finite(production)),
  all(production >= 0), attr(production, "support_redraw_count") >= 0L)

# Extreme standardized tails remain interior and finite without cancellation.
thresholds <- c(-8, 0, 2, 8, 20, 100, 1e4, 1e8)
set.seed(20261128)
extreme <- app_joint_qvp_rtruncnorm_tail_stable(length(thresholds),
  mean = -thresholds, sd = 1, lower = 0)
stopifnot(all(is.finite(extreme)), all(extreme > 0),
  attr(extreme, "max_standardized_tail_threshold") == max(thresholds),
  attr(extreme, "tail_proposal_count") >= length(thresholds))

# Reflection uses the same exact one-sided kernel for an upper truncation.
set.seed(20261129)
lower_draw <- app_joint_qvp_rtruncnorm_tail_stable(100L,
  mean = -8, sd = 1, lower = 0)
set.seed(20261129)
upper_draw <- app_joint_qvp_rtruncnorm_tail_stable(100L,
  mean = 8, sd = 1, upper = 0)
stopifnot(identical(as.numeric(lower_draw), -as.numeric(upper_draw)))

# Monte Carlo moments agree with the analytic one-sided normal moments.
set.seed(20261130)
a <- 8
sample <- app_joint_qvp_rtruncnorm_tail_stable(50000L,
  mean = -a, sd = 1, lower = 0)
mills <- exp(stats::dnorm(a, log = TRUE) - stats::pnorm(a,
  lower.tail = FALSE, log.p = TRUE))
expected_mean <- mills - a
expected_var <- 1 + a * mills - mills^2
stopifnot(abs(mean(sample) - expected_mean) < 0.003,
  abs(stats::var(sample) - expected_var) < 0.001,
  !any(sample == 0))

# Finite intervals use exact, strictly interior rejection in central and tail regimes.
set.seed(20261201)
right_interval <- app_joint_qvp_rtruncnorm_interval_stable(1000L,
  mean = -100, sd = 1, lower = 0, upper = 0.01)
extreme_narrow_right <- app_joint_qvp_rtruncnorm_interval_stable(1000L,
  mean = -1e8, sd = 1, lower = 0, upper = 1e-12)
set.seed(20261202)
left_interval <- app_joint_qvp_rtruncnorm_interval_stable(1000L,
  mean = 100, sd = 1, lower = -0.01, upper = 0)
central_interval <- app_joint_qvp_rtruncnorm_interval_stable(1000L,
  mean = 0, sd = 1, lower = -0.1, upper = 0.1)
wide_interval <- app_joint_qvp_rtruncnorm_interval_stable(1000L,
  mean = 0, sd = 1, lower = -1e8, upper = 1e8)
stopifnot(all(right_interval > 0 & right_interval < 0.01),
  all(extreme_narrow_right > 0 & extreme_narrow_right < 1e-12),
  all(left_interval > -0.01 & left_interval < 0),
  all(central_interval > -0.1 & central_interval < 0.1),
  all(is.finite(wide_interval)), max(abs(wide_interval)) < 10,
  !any(right_interval %in% c(0, 0.01)))

# Repeated ordered updates cannot create equal neighboring intercepts.
set.seed(20261203)
alpha <- c(-1, 0, 1)
for (iteration in seq_len(10000L)) {
  for (k in seq_along(alpha)) {
    lower <- if (k == 1L) -Inf else alpha[[k - 1L]] + 1e-8
    upper <- if (k == length(alpha)) Inf else alpha[[k + 1L]] - 1e-8
    alpha[[k]] <- app_joint_qvp_rtruncnorm_ordered_stable(1L,
      mean = (-2 + k), sd = 10, lower = lower, upper = upper)
  }
  stopifnot(all(diff(alpha) > 0))
}

cat("JOINT_EXAL_LATENT_SUPPORT_REDRAW_TEST_PASS expectations=35 production_runs=0\n")
