#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
source(app_path("application/R/joint_qvp_qdesn.R"))

near_precision <- diag(c(1, 1, -1.0e-10))
no_repair <- suppressWarnings(try(app_joint_qvp_precision_draw(
  rep(0, 3), near_precision, max_dense_dim = 0L, repair = FALSE
), silent = TRUE))
stopifnot(inherits(no_repair, "try-error"))

env <- new.env(parent = emptyenv())
set.seed(20260908)
draw_a <- suppressWarnings(app_joint_qvp_precision_draw(
  rep(0, 3), near_precision, max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8,
  diagnostic_env = env
))
diag_a <- env$last_precision_draw
stopifnot(
  length(draw_a) == 3L,
  all(is.finite(draw_a)),
  identical(diag_a$status[[1L]], "repaired"),
  diag_a$jitter_relative[[1L]] <= 1.0e-8,
  diag_a$jitter_absolute[[1L]] > 0
)

env_b <- new.env(parent = emptyenv())
set.seed(20260908)
draw_b <- suppressWarnings(app_joint_qvp_precision_draw(
  rep(0, 3), near_precision, max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8,
  diagnostic_env = env_b
))
stopifnot(identical(round(draw_a, 12), round(draw_b, 12)))

hard_precision <- diag(c(1, 1, -0.1))
hard_failure <- suppressWarnings(try(app_joint_qvp_precision_draw(
  rep(0, 3), hard_precision, max_dense_dim = 0L, repair = TRUE,
  repair_start_rel = 1.0e-12, repair_max_rel = 1.0e-8
), silent = TRUE))
stopifnot(inherits(hard_failure, "try-error"))

direct_env <- new.env(parent = emptyenv())
set.seed(9)
direct <- app_joint_qvp_precision_draw(
  rep(0, 3), diag(c(1, 2, 3)), max_dense_dim = 0L,
  repair = TRUE, diagnostic_env = direct_env
)
stopifnot(
  all(is.finite(direct)),
  identical(direct_env$last_precision_draw$status[[1L]], "direct"),
  direct_env$last_precision_draw$jitter_relative[[1L]] == 0
)

cat("JOINT QVP precision draw repair tests passed\n")
