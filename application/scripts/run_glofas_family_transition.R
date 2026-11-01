#!/usr/bin/env Rscript
# Exactly one claimed fitting unit; never a self-scheduling production launcher.
script_file <- sub("^--file=", "", grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
repo <- normalizePath(file.path(dirname(script_file),"..",".."),mustWork=TRUE)
setwd(repo)
source("application/scripts/_glofas_unit_member_bootstrap.R")
source("application/R/glofas_family_transition.R")
args <- app_parse_args(list(request="",authorization="",authorization_sha256=""))
for (key in names(args)[grepl("-",names(args),fixed=TRUE)]) {
  args[[gsub("-","_",key,fixed=TRUE)]] <- args[[key]]
}
if (!nzchar(args$request) || !nzchar(args$authorization) ||
    !grepl("^[0-9a-f]{64}$",args$authorization_sha256)) {
  app_gft_stop("NO_LAUNCH: supply a claimed request and exact external source-bound authorization SHA256.")
}
dispatch <- list()
for (pair in list(c("claim_ticket","claim_ticket_path"),c("claim_ticket_sha256","claim_ticket_sha256"),
    c("ledger","ledger_path"),c("python","controller_python"))) {
  if (!is.null(args[[pair[1L]]]) && nzchar(args[[pair[1L]]])) dispatch[[pair[2L]]]<-args[[pair[1L]]]
}
if (!is.null(args$source_manifest)) {
  envelope<-app_gft_json(args$request)
  if (!identical(normalizePath(args$source_manifest,mustWork=TRUE),
      normalizePath(envelope$source_manifest_path,mustWork=TRUE))) app_gft_stop("CLI source inventory disagrees with frozen request.")
}
app_glofas_family_transition_run_request(normalizePath(args$request,mustWork=TRUE),
  normalizePath(args$authorization,mustWork=TRUE),args$authorization_sha256,repo,dispatch)
cat("TRANSITION_TASK_COMPLETED_PENDING_COORDINATOR_ACCEPTANCE\n")
