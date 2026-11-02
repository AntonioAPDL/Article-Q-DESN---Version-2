#!/usr/bin/env Rscript
# Read-only compact feature-value comparison; no model loading or fitting.
source("scripts/ind_qdesn_native_catalog.R")
ind_qnc_feature_cli <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript scripts/check_ind_qdesn_feature_replay.R --reference FILE --reference-sha256 SHA --replay FILE --replay-sha256 SHA\n")
    return(invisible(NULL))
  }
  ind_qnc_require(length(args)==8L&&identical(args[c(1L,3L,5L,7L)],
    c("--reference","--reference-sha256","--replay","--replay-sha256")),"exact pinned comparison arguments required")
  read_pin <- function(path,sha) {
    ind_qnc_require(is.character(path)&&length(path)==1L&&startsWith(path,"/")&&
      file.exists(path)&&!isTRUE(file.info(path)$isdir)&&identical(Sys.readlink(path),"")&&
      identical(normalizePath(path,mustWork=TRUE),path)&&file.info(path)$size<=8*1024^2&&
      is.character(sha)&&length(sha)==1L&&grepl("^[a-f0-9]{64}$",sha)&&
      identical(unname(tools::sha256sum(path)),sha),"compact8MiB nonsymlink fixture pin failed")
    readRDS(path)
  }
  reference <- read_pin(args[2L],args[4L]);replay <- read_pin(args[6L],args[8L])
  out <- ind_qnc_feature_replay(reference,replay)
  ind_qnc_require(identical(unname(tools::sha256sum(args[2L])),args[4L])&&
    identical(unname(tools::sha256sum(args[6L])),args[8L]),"fixture bytes changed during comparison")
  out$reference_file_sha256 <- args[4L];out$replay_file_sha256 <- args[8L]
  cat(jsonlite::toJSON(out,auto_unbox=TRUE,digits=17),"\n")
  invisible(out)
}
if(sys.nframe()==0L)ind_qnc_feature_cli()
