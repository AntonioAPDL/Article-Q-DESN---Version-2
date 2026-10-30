local({
  checker <- file.path(getwd(), "scripts", "check_joint_qdesn_pure_desn_article_projection.R")
  result <- system2(file.path(R.home("bin"), "Rscript"), c(checker, "--historical-only"),
                    stdout = TRUE, stderr = TRUE)
  status <- attr(result, "status")
  if (!is.null(status) && status != 0L) stop(paste(result, collapse = "\n"))
  stopifnot(any(grepl("JOINT_PURE_DESN_ARTICLE_PROJECTION_CHECK=PASS", result, fixed = TRUE)))
  # Historical source compatibility is bounded to a reviewed ancestor and two
  # code paths. It cannot authenticate a changed receipt or scientific output.
  source(file.path(getwd(), "scripts/independent_reporting_authority_checks.R"),
    local = TRUE)
  root <- normalizePath(getwd(), mustWork = TRUE)
  presentation <- jsonlite::read_json(file.path(root,
    "tables/qdesn_pro_review_presentation_manifest.json"))
  reference <- app_ind_authority_commits[["presentation"]]
  stopifnot(identical(reference, "282206caf176d5e8e13857dd1070f2fac02586fc"))
  app_ind_historical_hash(root, presentation$source_script,
    presentation$script_sha256, "presentation")
  reject <- function(expression) {
    caught <- tryCatch({ force(expression); NULL }, error = identity)
    stopifnot(inherits(caught, "error"))
  }
  wrong <- paste(rep("0", 64L), collapse = "")
  reject(app_ind_current_hash(root,
    "tables/qdesn_pro_review_presentation_manifest.json", wrong))
  reject(app_ind_historical_hash(root, presentation$source_script, wrong, "presentation"))
  reject(app_ind_historical_hash(root,
    "tables/joint_qdesn_pure_desn_v1_forecast_score_summary.csv", wrong, "presentation"))
  reject(app_ind_historical_hash(root,
    "figures/joint_qdesn_simulation/joint_qdesn_pro_review_forecast_dgp_acrps.pdf",
    wrong, "presentation"))
  reject(app_ind_git_text(root, presentation$source_script, "HEAD"))
  # The historical compatibility gate must not convert a failed current check
  # into success, even if that failed subprocess prints a success-like marker.
  historical <- file.path(getwd(), "scripts", "check_joint_qdesn_corrected_article_projection_v4.R")
  for (failure in c("nonzero_with_marker", "zero_without_marker")) {
    env <- new.env(parent = globalenv())
    env$commandArgs <- function(...) paste0("--file=", historical)
    env$system2 <- function(command, args, ...) {
      if (any(grepl("check_joint_qdesn_pure_desn_article_projection", args, fixed = TRUE))) {
        if (failure == "nonzero_with_marker") {
          return(structure("JOINT_PURE_DESN_ARTICLE_PROJECTION_V2_CHECK=PASS mocked", status = 1L))
        }
        return("No current validation receipt")
      }
      base::system2(command, args, ...)
    }
    caught <- tryCatch({ source(historical, local = env); NULL }, error = identity)
    stopifnot(inherits(caught, "error"), grepl("Current JOINT article checker", conditionMessage(caught)))
  }
  cat("test_joint_qdesn_pure_desn_article_projection: PASS\n")
})
