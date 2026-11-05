#!/usr/bin/env Rscript
# Generated targets only. No application payload, fitting or publication.
giga_main <- function(args = commandArgs(TRUE)) {
  stopifnot(length(args) == 2L, identical(args[1L], "--out-dir"))
  root <- normalizePath(".", mustWork = TRUE)
  parent <- normalizePath(dirname(args[2L]), mustWork = TRUE)
  out <- file.path(parent, basename(args[2L]))
  stopifnot(startsWith(parent, paste0(root, "/local_trackers/")),
    !file.exists(out), !nzchar(Sys.readlink(out)),
    system2("git", c("check-ignore", "-q", shQuote(out))) == 0L)
  stopifnot(requireNamespace("jsonlite", quietly = TRUE))
  source("scripts/diagnostics/glofas_vb_accuracy_benchmarks.R", local = TRUE)
  result <- gvab_run_benchmarks(root)
  stopifnot(all(result$checks$reference_validity == "PASS"),
    all(result$checks$implementation_parity == "PASS"),
    all(result$checks$numerical_stability == "PASS"),
    result$authentic_reads == 0L, result$scientific_runs == 0L)
  stopifnot(dir.create(out, mode = "0700"))
  table_names <- c("checks", "normal_coefficient", "al_coefficient", "unknown_scale", "two_horizon", "blocked")
  for (name in table_names) utils::write.csv(result[[name]], file.path(out, paste0(name, ".csv")), row.names = FALSE)
  result[table_names] <- NULL
  result$status <- "GENERATED_HELPER_PARITY_PASS_APPROXIMATION_DEPARTURES_RETAINED"
  result$reference_qualified <- FALSE
  result$production_launch_authorized <- FALSE
  result$publication_authorized <- FALSE
  result$R_version <- R.version.string
  result$source_commit <- unname(system2("git", c("rev-parse", "HEAD"), stdout = TRUE))
  sources <- c("scripts/audit_glofas_innovation_generated.R",
    "scripts/diagnostics/glofas_vb_accuracy_benchmarks.R",
    "scripts/diagnostics/glofas_coupled_parameter_reference.R",
    "application/R/latent_path_vb_al.R", "application/R/latent_path_vb_normal.R")
  result$source_sha256 <- as.list(tools::sha256sum(sources))
  jsonlite::write_json(result, file.path(out, "DECISION.json"), auto_unbox = TRUE,
    pretty = TRUE, digits = 17, null = "null")
  entries <- sort(list.files(out))
  inventory <- data.frame(relative_path = entries,
    size_bytes = as.numeric(file.info(file.path(out, entries))$size),
    sha256 = unname(tools::sha256sum(file.path(out, entries))))
  utils::write.csv(inventory, file.path(out, "artifact_manifest.csv"), row.names = FALSE)
  cat("GLOFAS_INNOVATION_GENERATED_AUDIT_COMPLETE original_reads=0 production_fits=0\n")
  invisible(result)
}
if (sys.nframe() == 0L) giga_main()
