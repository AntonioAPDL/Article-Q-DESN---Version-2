# Authoritative upstream source-bundle audit for the GloFAS application.

app_authoritative_cutoff_dir <- function(bundle_root, cutoff_date, requirements) {
  root <- app_resolve_path(bundle_root, must_work = TRUE)
  cutoff_date <- as.Date(cutoff_date)
  if (is.na(cutoff_date)) stop("cutoff_date must be a valid date.", call. = FALSE)
  pattern <- requirements$cutoff_directory_pattern %||% "cutoff_date=%Y-%m-%d"
  expected <- format(cutoff_date, pattern)
  path <- file.path(root, expected)
  if (dir.exists(path)) return(path)

  candidates <- list.dirs(root, recursive = TRUE, full.names = TRUE)
  candidates <- candidates[basename(candidates) == expected]
  if (length(candidates)) return(candidates[[1L]])

  stop(
    sprintf("Could not find authoritative cutoff directory '%s' under %s.", expected, root),
    call. = FALSE
  )
}

app_authoritative_lineage_text <- function(cutoff_dir, extra_roots = character(), max_read_bytes = 1e6) {
  roots <- c(cutoff_dir, extra_roots)
  roots <- roots[file.exists(roots)]
  files <- unlist(lapply(roots, function(root) {
    list.files(root, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  }), use.names = FALSE)
  files <- files[file.exists(files)]
  keep <- tolower(tools::file_ext(files)) %in% c("json", "txt", "md", "csv", "yaml", "yml")
  files <- files[keep]
  if (!length(files)) return("")
  info <- file.info(files)
  chunks <- vapply(files, function(path) {
    size <- info[path, "size"]
    lines <- if (is.finite(size) && size <= max_read_bytes) {
      tryCatch(readLines(path, warn = FALSE, n = 2000L), error = function(e) character())
    } else {
      character()
    }
    paste(c(path, lines), collapse = "\n")
  }, character(1L))
  tolower(paste(chunks, collapse = "\n"))
}

app_authoritative_required_lineage_rows <- function(cutoff_dir, requirements) {
  required <- requirements$required_lineage_files %||% character()
  if (!length(required)) return(data.frame())
  files <- list.files(cutoff_dir, recursive = TRUE, full.names = FALSE, all.files = FALSE)
  rows <- lapply(required, function(name) {
    found <- any(basename(files) == name)
    data.frame(
      check_type = "lineage_file",
      component = name,
      required = TRUE,
      status = if (found) "ok" else "failed",
      detail = if (found) "required lineage file present" else sprintf("missing %s", name),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_authoritative_component_rows <- function(cutoff_dir, lineage_text, requirements) {
  components <- requirements$components %||% list()
  files <- tolower(paste(list.files(cutoff_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE), collapse = "\n"))
  haystack <- paste(files, lineage_text, sep = "\n")
  rows <- lapply(names(components), function(id) {
    spec <- components[[id]]
    patterns <- unlist(spec$patterns %||% character(), use.names = FALSE)
    hits <- patterns[vapply(patterns, function(pat) grepl(pat, haystack, perl = TRUE, ignore.case = TRUE), logical(1L))]
    required <- isTRUE(spec$required %||% TRUE)
    ok <- length(hits) > 0L
    data.frame(
      check_type = "source_component",
      component = id,
      required = required,
      status = if (ok) "ok" else if (required) "failed" else "missing_optional",
      detail = if (ok) {
        sprintf("%s matched pattern(s): %s", spec$label %||% id, paste(hits, collapse = "; "))
      } else {
        sprintf("%s not found in copied lineage text or file paths.", spec$label %||% id)
      },
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_version_spec <- function(cutoff_date, requirements) {
  rule <- requirements$glofas_version_rule %||% list()
  lisflood_start <- as.Date(rule$lisflood_start_date %||% "2021-05-26")
  cutoff_date <- as.Date(cutoff_date)
  if (cutoff_date < lisflood_start) {
    expected <- rule$before_start_expected %||% "glofas_hist_v21_htessel_cons"
    aliases <- unlist(rule$before_start_aliases %||% character(), use.names = FALSE)
    disallowed <- unlist(rule$before_start_disallowed %||% character(), use.names = FALSE)
  } else {
    expected <- rule$on_or_after_start_expected %||% "glofas_hist_v31_lisflood_cons"
    aliases <- unlist(rule$on_or_after_start_aliases %||% character(), use.names = FALSE)
    disallowed <- unlist(rule$on_or_after_disallowed %||% "glofas_hist_v21_htessel_cons", use.names = FALSE)
  }
  list(
    expected = tolower(as.character(expected)),
    aliases = unique(tolower(c(as.character(expected), aliases))),
    disallowed = unique(tolower(disallowed)),
    lisflood_start = lisflood_start
  )
}

app_has_any_fixed <- function(text, patterns) {
  patterns <- patterns[nzchar(patterns)]
  if (!length(patterns)) return(FALSE)
  any(vapply(patterns, function(pat) grepl(pat, text, fixed = TRUE), logical(1L)))
}

app_authoritative_glofas_version_row <- function(cutoff_date, lineage_text, requirements) {
  spec <- app_glofas_version_spec(cutoff_date, requirements)
  text <- tolower(lineage_text)
  has_expected <- app_has_any_fixed(text, spec$aliases)
  has_disallowed <- app_has_any_fixed(text, spec$disallowed)
  ok <- has_expected
  detail <- if (ok) {
    sprintf("Expected GloFAS source '%s' is documented for cutoff %s.", spec$expected, as.Date(cutoff_date))
  } else if (has_disallowed) {
    sprintf(
      "Disallowed GloFAS source evidence was found for cutoff %s; expected '%s'.",
      as.Date(cutoff_date),
      spec$expected
    )
  } else if (grepl("glofas", text, fixed = TRUE)) {
    sprintf(
      "GloFAS version evidence found but expected '%s' was not confirmed for cutoff %s.",
      spec$expected,
      as.Date(cutoff_date)
    )
  } else {
    sprintf("No GloFAS hydrological-model version evidence found; expected '%s'.", spec$expected)
  }
  data.frame(
    check_type = "glofas_version",
    component = "glofas_hydrological_model",
    required = TRUE,
    status = if (ok) "ok" else "failed",
    detail = detail,
    stringsAsFactors = FALSE
  )
}

app_audit_authoritative_source_bundle <- function(
    bundle_root,
    cutoff_date,
    requirements_path,
    extra_roots = character()) {
  requirements <- app_read_yaml(requirements_path)
  cutoff_dir <- app_authoritative_cutoff_dir(bundle_root, cutoff_date, requirements)
  extra_roots <- extra_roots[nzchar(extra_roots)]
  extra_roots <- vapply(extra_roots, app_resolve_path, character(1L), must_work = FALSE)
  extra_roots <- extra_roots[dir.exists(extra_roots) | file.exists(extra_roots)]
  cutoff_lineage_text <- app_authoritative_lineage_text(cutoff_dir)
  lineage_text <- app_authoritative_lineage_text(cutoff_dir, extra_roots = extra_roots)
  rows <- rbind(
    app_authoritative_required_lineage_rows(cutoff_dir, requirements),
    app_authoritative_component_rows(cutoff_dir, lineage_text, requirements),
    app_authoritative_glofas_version_row(cutoff_date, cutoff_lineage_text, requirements)
  )
  required_failed <- rows$required & rows$status != "ok"
  list(
    ok = !any(required_failed),
    bundle_root = app_resolve_path(bundle_root, must_work = TRUE),
    cutoff_dir = cutoff_dir,
    extra_roots = extra_roots,
    cutoff_date = as.character(as.Date(cutoff_date)),
    audit = rows
  )
}

app_write_authoritative_source_audit <- function(result, run_dirs) {
  app_write_csv(result$audit, file.path(run_dirs$tables, "authoritative_source_bundle_audit.csv"))
  failed <- result$audit[result$audit$required & result$audit$status != "ok", , drop = FALSE]
  lines <- c(
    "Authoritative GloFAS source-bundle audit",
    sprintf("bundle_root: %s", result$bundle_root),
    sprintf("cutoff_dir: %s", result$cutoff_dir),
    sprintf(
      "extra_roots: %s",
      if (length(result$extra_roots)) paste(result$extra_roots, collapse = "; ") else "none"
    ),
    sprintf("cutoff_date: %s", result$cutoff_date),
    sprintf("status: %s", if (result$ok) "ok" else "failed"),
    "",
    if (nrow(failed)) "Failed required checks:" else "All required checks passed.",
    if (nrow(failed)) paste(sprintf("- %s: %s", failed$component, failed$detail), collapse = "\n") else ""
  )
  writeLines(lines, file.path(run_dirs$tables, "authoritative_source_bundle_audit_summary.txt"))
  invisible(failed)
}
