# Runtime-only contracts for Search III orchestration and aggregation.

app_glofas_search3_reuse_registry_columns <- function() {
  c(
    "destination_job_id", "source_job_id", "source_runtime_root",
    "fit_summary_path", "fit_summary_sha256",
    "score_summary_path", "score_summary_sha256",
    "score_detail_path", "score_detail_sha256"
  )
}

app_glofas_search3_empty_reuse_registry <- function() {
  cols <- app_glofas_search3_reuse_registry_columns()
  out <- setNames(rep(list(character()), length(cols)), cols)
  as.data.frame(out, stringsAsFactors = FALSE)
}

app_glofas_search3_read_reuse_registry <- function(path, required = TRUE) {
  if (!file.exists(path)) {
    if (isTRUE(required)) stop(sprintf("Missing Search III reuse registry: %s", path), call. = FALSE)
    return(app_glofas_search3_empty_reuse_registry())
  }
  lines <- readLines(path, warn = FALSE)
  nonblank <- trimws(lines[nzchar(trimws(lines))])
  if (identical(nonblank, '""')) return(app_glofas_search3_empty_reuse_registry())
  out <- tryCatch(app_read_csv(path), error = function(e) {
    stop(sprintf("Malformed Search III reuse registry '%s': %s", path, conditionMessage(e)), call. = FALSE)
  })
  required_cols <- app_glofas_search3_reuse_registry_columns()
  missing <- setdiff(required_cols, names(out))
  if (length(missing)) {
    stop(sprintf("Search III reuse registry lacks columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  out[, required_cols, drop = FALSE]
}

app_glofas_search3_git_output <- function(args) {
  out <- suppressWarnings(system2("git", c("-C", app_repo_root(), args), stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0L) {
    stop(sprintf("Search III Git check failed: git %s", paste(args, collapse = " ")), call. = FALSE)
  }
  out
}

app_glofas_search3_sha256_text <- function(text) {
  path <- tempfile("search3_text_hash_")
  on.exit(unlink(path), add = TRUE)
  writeChar(as.character(text), path, eos = NULL, useBytes = TRUE)
  app_sha256_file(path)
}

app_glofas_search3_assert_campaign_source <- function(campaign_manifest, campaign_root) {
  original <- as.character(campaign_manifest$git_head)
  current <- app_glofas_search3_git_output(c("rev-parse", "HEAD"))[[1L]]
  if (identical(current, original)) return(invisible(list(original_head = original, execution_head = current, transition = FALSE)))

  transition_path <- file.path(campaign_root, "configs", "source_transition_registry.csv")
  transition <- app_read_csv(transition_path)
  required <- c("from_head", "to_head", "classification", "changed_paths", "changed_paths_sha256")
  if (any(!required %in% names(transition)) || nrow(transition) != 1L) {
    stop("Search III source drift requires exactly one complete source-transition row.", call. = FALSE)
  }
  row <- transition[1L, , drop = FALSE]
  if (!identical(as.character(row$from_head), original) ||
      !identical(as.character(row$to_head), current) ||
      !identical(as.character(row$classification), "orchestration_only")) {
    stop("Search III source transition does not authorize the current campaign HEAD.", call. = FALSE)
  }
  changed <- sort(app_glofas_search3_git_output(c("diff", "--name-only", paste0(original, "..", current))))
  recorded <- strsplit(as.character(row$changed_paths), ";", fixed = TRUE)[[1L]]
  recorded <- sort(recorded[nzchar(recorded)])
  if (!identical(changed, recorded)) stop("Search III source-transition changed-path set does not reproduce.", call. = FALSE)
  digest <- app_glofas_search3_sha256_text(paste(changed, collapse = "\n"))
  if (!identical(digest, as.character(row$changed_paths_sha256))) {
    stop("Search III source-transition changed-path hash does not reproduce.", call. = FALSE)
  }
  allowed <- c(
    "application/R/glofas_search3_runtime_contract.R",
    "application/scripts/427_prepare_glofas_search3.R",
    "application/scripts/431_check_glofas_search3.R",
    "application/scripts/432_run_glofas_search3_campaign.py",
    "application/scripts/433_seal_glofas_search3_stage.py",
    "application/tests/run_tests.R",
    "application/tests/test_glofas_search3_runtime_contract.R",
    "application/tests/test_glofas_search3_scheduler.py",
    "application/tests/test_glofas_search3_stage_seal.py"
  )
  if (length(setdiff(changed, allowed))) {
    stop("Search III source transition includes non-orchestration source paths.", call. = FALSE)
  }
  invisible(list(
    original_head = original, execution_head = current, transition = TRUE,
    transition_path = normalizePath(transition_path), transition_sha256 = app_sha256_file(transition_path)
  ))
}
