#!/usr/bin/env Rscript
# Independent re-read of source packet and exact candidate table membership.
source("scripts/build_glofas_same_family_article_projection.R")
gsc_check_candidate <- function(packet_root,manifest_sha256,candidate_root) {
  z <- gsc_check_packet(packet_root,manifest_sha256)
  names <- c("candidate_family_scores.csv","candidate_score_table.tex","PROJECTION_CANDIDATE.json")
  gsc_require(setequal(list.files(candidate_root,all.files=TRUE,no..=TRUE),names),"candidate membership differs")
  d <- jsonlite::read_json(file.path(candidate_root,names[3L]),simplifyVector=FALSE)
  gsc_require(identical(d$status,"CANDIDATE_NOT_ARTICLE_AUTHORITY")&&
    identical(d$source_packet_manifest_sha256,manifest_sha256)&&identical(d$article_publication_authorized,FALSE),
    "candidate falsely claims scientific/publication authority")
  observed <- read.csv(file.path(candidate_root,names[1L]),stringsAsFactors=FALSE)
  gsc_require(isTRUE(all.equal(observed,z$summary,tolerance=0,check.attributes=FALSE)),"candidate score values differ")
  gsc_require(identical(readLines(file.path(candidate_root,names[2L])),gsc_candidate_tex(z$summary)),"candidate labels or values differ")
  invisible(TRUE)
}
if(sys.nframe()==0L) {
  a <- commandArgs(TRUE)
  gsc_require(length(a)==6L&&identical(a[c(1,3,5)],c("--packet","--manifest-sha256","--candidate")),
    "Usage: --packet ROOT --manifest-sha256 SHA --candidate ROOT")
  gsc_check_candidate(a[2L],a[4L],a[6L]);cat("GLOFAS_CANDIDATE_VERIFIED_NOT_ARTICLE_AUTHORITY\n")
}
