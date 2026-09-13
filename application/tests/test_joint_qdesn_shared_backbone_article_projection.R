#!/usr/bin/env Rscript

# Compatibility entry point for earlier commands. The corrected v4 projection
# supersedes the historical shared-backbone article assets.
source(file.path(
  normalizePath(getwd(), mustWork = TRUE), "application", "tests",
  "test_joint_qdesn_corrected_article_projection_v4.R"
))
