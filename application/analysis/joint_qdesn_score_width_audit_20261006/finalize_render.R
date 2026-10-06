joint_width_finalize_render <- function(source_root, output) {
  stopifnot(!file.exists(file.path(output, "artifact_manifest.csv")))
  app_joint_prior_verify_freeze(source_root)
  ct <- readRDS(file.path(source_root, "contract.rds"))
  inputs <- app_read_csv(file.path(output, "input_manifest.csv"))
  stopifnot(all(file.exists(inputs$path)),
    all(as.numeric(file.info(inputs$path)$size) == inputs$size_bytes),
    all(vapply(inputs$path, app_sha256_file, character(1L)) == inputs$sha256))
  cells <- app_read_csv(file.path(output, "cell_audit.csv"))
  stopifnot(nrow(cells) == 24L, all(cells$reconstruction_max_error < 1e-8))
  old <- options(bitmapType = "cairo")
  on.exit(options(old), add = TRUE)
  warnings <- character()
  withCallingHandlers(joint_width_plot(output), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  app_write_csv(data.frame(message = unique(warnings)), file.path(output, "render_warnings.csv"))
  writeLines(c("Read-only JOINT uncertainty attribution; no changes to frozen scores or fits.",
    paste("Source root:", normalizePath(source_root)),
    paste("Frozen HEAD:", readLines(file.path(source_root, "source_head.txt"))),
    "All 24 confirmation cells and all 81,000 retained posterior draw rows were used.",
    "Native joint dependence preserved; independent coupling reproduces the frozen seed rule.",
    "Loss and horizon decompositions reproduce frozen scores within 1e-8.",
    "Common-design and weak-design projections use the raw readout, not contracted quantiles.",
    "Weak projected variances are not additive shares: cross-direction covariance remains.",
    "Between-chain fractions and temporal halves after independent permutation are descriptive only.",
    "Quantile-band truth is origin-marginal DGP truth; bands are quantile-function uncertainty.",
    "First origin was predeclared. No model or challenger has been promoted.",
    "Initial PNG export failed because X11 was unavailable; plots were rerendered from completed CSVs with cairo.",
    "The original reconstruction code and its input hashes remain unchanged.",
    paste("Analysis UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    capture.output(sessionInfo())), file.path(output, "METHODS.txt"))
  script <- app_path("local_trackers/joint_score_width_audit_20261006/finalize_render.R")
  app_write_csv(data.frame(path = script, sha256 = app_sha256_file(script)),
    file.path(output, "render_source.csv"))
  paths <- list.files(output, full.names = TRUE)
  app_joint_shared_write_manifest(output, setNames(paths, basename(paths)))
  stopifnot(all(app_joint_shared_verify_manifest(output)$verified))
  cat("AUDIT_AND_PLOTS_COMPLETE; unique render warnings:", length(unique(warnings)), "\n")
  if (length(warnings)) print(unique(warnings))
}
