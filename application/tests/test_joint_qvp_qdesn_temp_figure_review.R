temp_review_root <- tempfile("joint_qvp_temp_review_sources_")
dir.create(temp_review_root, recursive = TRUE, showWarnings = FALSE)
temp_review_out <- tempfile("joint_qvp_temp_review_out_")

temp_review_write_png <- function(path) {
  writeBin(as.raw(c(137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0)), path)
  invisible(path)
}
temp_review_write_manifest <- function(dir, labels, paths) {
  manifest <- data.frame(
    label = labels,
    relative_path = paths,
    size_bytes = as.numeric(file.info(file.path(dir, paths))$size),
    sha256 = vapply(file.path(dir, paths), app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(manifest, file.path(dir, "figure_manifest.csv"), row.names = FALSE)
}

toy_dir <- file.path(temp_review_root, "toy")
suite_dir <- file.path(temp_review_root, "suite")
deep_dir <- file.path(temp_review_root, "deep")
wide_dir <- file.path(temp_review_root, "wide")
dir.create(toy_dir, recursive = TRUE)
dir.create(suite_dir, recursive = TRUE)
dir.create(deep_dir, recursive = TRUE)
dir.create(wide_dir, recursive = TRUE)

toy_labels <- c("fit_overlay", "error_hit", "elbo_trace", "parameter_traces")
toy_files <- paste0("toy_", toy_labels, ".png")
for (path in file.path(toy_dir, toy_files)) temp_review_write_png(path)
temp_review_write_manifest(toy_dir, toy_labels, toy_files)

suite_cases <- c("case_a", "case_b")
for (case_id in suite_cases) {
  temp_review_write_png(file.path(suite_dir, paste0(case_id, "_error_hit.png")))
  temp_review_write_png(file.path(suite_dir, paste0(case_id, "_fit_overlay.png")))
}

deep_files <- c("deep_case_fit_overlay.png", "deep_case_error_hit.png")
for (path in file.path(deep_dir, deep_files)) temp_review_write_png(path)
temp_review_write_manifest(deep_dir, sub("[.]png$", "", deep_files), deep_files)

wide_labels <- c("wide_elbo_trace", "wide_parameter_traces", "wide_fit_overlay")
wide_files <- paste0(wide_labels, ".png")
for (path in file.path(wide_dir, wide_files)) temp_review_write_png(path)
temp_review_write_manifest(wide_dir, wide_labels, wide_files)

temp_review_result <- app_joint_qvp_collect_temp_figure_review(
  out_dir = temp_review_out,
  toy_dir = toy_dir,
  suite_dir = suite_dir,
  deep_dir = deep_dir,
  wide_dir = wide_dir,
  suite_case_ids = suite_cases,
  generated_time = as.POSIXct("2026-07-02 00:00:00", tz = "UTC")
)

stopifnot(nrow(temp_review_result$figure_index) == 13L)
stopifnot(identical(
  as.integer(table(temp_review_result$figure_index$stage)[c(
    "01_toy_fit_validation",
    "02_suite_fit_validation",
    "03_deep_mcmc_reference",
    "04_wide_reference_temp_diagnostics"
  )]),
  c(4L, 4L, 2L, 3L)
))
stopifnot(file.exists(temp_review_result$paths[["figure_review_index"]]))
stopifnot(file.exists(temp_review_result$paths[["index_html"]]))
stopifnot(file.exists(temp_review_result$paths[["artifact_manifest"]]))

temp_review_manifest <- utils::read.csv(
  temp_review_result$paths[["artifact_manifest"]],
  stringsAsFactors = FALSE
)
stopifnot(nrow(temp_review_manifest) == 16L)
for (ii in seq_len(nrow(temp_review_manifest))) {
  artifact_path <- file.path(temp_review_result$out_dir, temp_review_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), temp_review_manifest$sha256[[ii]]))
}

temp_review_readme <- readLines(temp_review_result$paths[["readme"]], warn = FALSE)
stopifnot(any(grepl("Figure count: 13", temp_review_readme, fixed = TRUE)))
