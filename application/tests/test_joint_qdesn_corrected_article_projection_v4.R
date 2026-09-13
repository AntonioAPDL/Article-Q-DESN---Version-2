repo_root <- normalizePath(getwd(), mustWork = TRUE)
checker <- file.path(
  repo_root, "scripts", "check_joint_qdesn_corrected_article_projection_v4.R"
)
output <- system2(
  "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
  checker,
  stdout = TRUE,
  stderr = TRUE
)
status <- attr(output, "status")
if (is.null(status)) status <- 0L
stopifnot(identical(as.integer(status), 0L))
stopifnot(any(grepl(
  "JOINT_CORRECTED_ARTICLE_PROJECTION_V4_CHECK=PASS", output,
  fixed = TRUE
)))
cat("test_joint_qdesn_corrected_article_projection_v4: PASS\n")
