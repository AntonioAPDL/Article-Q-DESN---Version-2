local({
  checker <- file.path(getwd(), "scripts", "check_joint_qdesn_pure_desn_article_projection.R")
  result <- system2(file.path(R.home("bin"), "Rscript"), checker,
                    stdout = TRUE, stderr = TRUE)
  status <- attr(result, "status")
  if (!is.null(status) && status != 0L) stop(paste(result, collapse = "\n"))
  stopifnot(any(grepl("JOINT_PURE_DESN_ARTICLE_PROJECTION_CHECK=PASS", result, fixed = TRUE)))
  # The historical compatibility gate must not convert a failed current check
  # into success, even if that failed subprocess prints a success-like marker.
  historical <- file.path(getwd(), "scripts", "check_joint_qdesn_corrected_article_projection_v4.R")
  for (failure in c("nonzero_with_marker", "zero_without_marker")) {
    env <- new.env(parent = globalenv())
    env$commandArgs <- function(...) paste0("--file=", historical)
    env$system2 <- function(command, args, ...) {
      if (any(grepl("check_joint_qdesn_pure_desn_article_projection.R", args, fixed = TRUE))) {
        if (failure == "nonzero_with_marker") {
          return(structure("JOINT_PURE_DESN_ARTICLE_PROJECTION_CHECK=PASS mocked", status = 1L))
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
