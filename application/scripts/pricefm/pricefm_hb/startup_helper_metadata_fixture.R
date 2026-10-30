# Metadata only.  Default utils must bootstrap unchanged before this script.
# This file does not load a scientific package, dataset, model or optimizer.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, grepl("^[0-9a-f]{32}$", args[[1L]]))
stopifnot("utils" %in% loadedNamespaces())
uname <- unname(Sys.which("uname"))
stopifnot(length(uname) == 1L, nzchar(uname), file.exists(uname))
answer <- system2(uname, "-s", stdout = TRUE, stderr = TRUE)
exit <- attr(answer, "status", exact = TRUE)
stopifnot(is.null(exit) || identical(exit, 0L))
stopifnot(identical(as.character(answer), "Linux"))
quote_json <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub('"', '\\"', x, fixed = TRUE)
  paste0('"', x, '"')
}
fields <- c(
  '"status":"PASS_R_STARTUP_METADATA_FIXTURE"',
  '"role":"R_STARTUP_METADATA_ONLY"',
  paste0('"nonce":', quote_json(args[[1L]])),
  paste0('"R_version":', quote_json(as.character(getRversion()))),
  paste0('"R_home":', quote_json(R.home())),
  paste0('"hostname":', quote_json(unname(Sys.info()[["nodename"]]))),
  paste0('"SLURM_JOB_ID":', quote_json(Sys.getenv("SLURM_JOB_ID"))),
  paste0('"SLURMD_NODENAME":', quote_json(Sys.getenv("SLURMD_NODENAME"))),
  paste0('"uname_path":', quote_json(normalizePath(uname, mustWork = TRUE))),
  '"uname_result":"Linux"', '"default_utils_loaded":true',
  '"models":0', '"optimizer_invocations":0', '"scientific_data_read":false')
cat(paste0("{", paste(fields, collapse = ","), "}\n"))
