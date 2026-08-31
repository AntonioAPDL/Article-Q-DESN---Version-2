repo_root <- normalizePath(
  getOption("qdesn.repo_root", Sys.getenv("QDESN_REPO_ROOT", unset = ".")),
  mustWork = TRUE
)

checker <- file.path(
  repo_root,
  "scripts",
  "check_joint_qdesn_phase181_article_projection.R"
)
stopifnot(file.exists(checker))

output <- system2(
  "Rscript",
  c(shQuote(checker), shQuote(repo_root)),
  stdout = TRUE,
  stderr = TRUE
)
status <- attr(output, "status")
if (!is.null(status) && status != 0L) {
  stop(paste(output, collapse = "\n"))
}
stopifnot(any(grepl(
  "JOINT_QDESN_PHASE181_ARTICLE_CHECK=PASS",
  output,
  fixed = TRUE
)))

cat("Joint QDESN Phase181 article projection tests passed.\n")
