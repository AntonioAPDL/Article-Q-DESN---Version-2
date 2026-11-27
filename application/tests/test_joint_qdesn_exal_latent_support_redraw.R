#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application", "R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts", "_joint_qdesn_persistent_tail_v8_bootstrap.R"))

# Numerical support violations are redrawn from the same truncated law, never clipped.
calls <- 0L
one_bad_then_valid <- function(n, mean, sd, lower, upper) {
  calls <<- calls + 1L
  if (calls == 1L) return(c(-0.25, 0.4, 0.6))
  stopifnot(n == 1L, identical(mean, 0), identical(lower, 0))
  0.37
}
draw <- app_joint_qvp_rtruncnorm_support_safe(3L, mean = 0, sd = 1,
  lower = 0, draw_fun = one_bad_then_valid)
stopifnot(identical(as.numeric(draw), c(0.37, 0.4, 0.6)),
  attr(draw, "support_redraw_count") == 1L, calls == 2L,
  draw[[1L]] != 0)

# Persistent generator defects fail closed instead of creating a boundary atom.
always_bad <- function(n, mean, sd, lower, upper) rep(-1, n)
error <- tryCatch({
  app_joint_qvp_rtruncnorm_support_safe(2L, mean = 0, sd = 1,
    lower = 0, max_redraw_rounds = 2L, draw_fun = always_bad)
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

cat("JOINT_EXAL_LATENT_SUPPORT_REDRAW_TEST_PASS expectations=12 production_runs=0\n")
