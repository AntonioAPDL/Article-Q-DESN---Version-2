#!/usr/bin/env Rscript

repo_root <- normalizePath(getwd(), mustWork = TRUE)
checker <- file.path(repo_root, "scripts",
  "check_joint_qdesn_shared_backbone_article_projection.R")
if (!file.exists(checker)) {
  stop("Shared-backbone article projection checker is missing.", call. = FALSE)
}
status <- system2(
  "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
  checker, stdout = TRUE, stderr = TRUE
)
exit_status <- attr(status, "status")
if (is.null(exit_status)) exit_status <- 0L
if (!identical(as.integer(exit_status), 0L) ||
    !any(grepl("JOINT_SHARED_BACKBONE_ARTICLE_PROJECTION_CHECK=PASS", status,
               fixed = TRUE))) {
  stop(paste(c("Shared-backbone article projection check failed:", status),
             collapse = "\n"), call. = FALSE)
}
cat("JOINT shared-backbone article projection test passed\n")
