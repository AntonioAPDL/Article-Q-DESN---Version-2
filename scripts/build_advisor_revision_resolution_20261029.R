#!/usr/bin/env Rscript
# Serialize the frozen review crosswalk without publishing private annotation text.
args <- commandArgs(TRUE)
if (length(args) != 1L || !file.exists(args[[1L]])) {
  stop("Supply the frozen ignored REVISION_EXECUTION_MATRIX.csv path.")
}
matrix <- read.csv(args[[1L]], stringsAsFactors=FALSE, check.names=FALSE)
stopifnot(nrow(matrix)==115L, !anyDuplicated(matrix$issue_id),
  sum(matrix$register=="METHODS_POINT_REGISTER.md")==64L,
  sum(matrix$register=="EMPIRICAL_POINT_REGISTER.md")==51L)
status <- rep("IMPLEMENTED_IN_REVIEW_DRAFT", nrow(matrix))
status[matrix$issue_id=="E51"] <- "PRESERVED_UNCHANGED_BY_SCOPE"
status[matrix$issue_id=="E36"] <- "BLOCKED_MISSING_AUTHENTIC_ONE_STEP_INPUTS"
status[matrix$issue_id=="C06"] <- "PARTIAL_SETTINGS_AUTHENTICATED_MATCHED_TIMING_UNAVAILABLE"
status[matrix$issue_id %in% c("A03","E43","E44","E46","E47","E48")] <-
  "MODEL_TEXT_REVISED_CORRECTED_RESULT_PACKET_PENDING"
evidence <- ifelse(matrix$register=="METHODS_POINT_REGISTER.md",
  "main.tex Sections 1-4; qdesn-supplement.tex Sections 1-9; reader and mathematical regression checks",
  "main.tex empirical sections; supplementary design and evaluation sections; frozen numerical invariance checks")
evidence[matrix$issue_id=="C06"] <- paste(
  "tables/independent_current_computation_{sources,receipts,inputs}_20261029.csv;",
  "docs/implementation_notes/independent_current_computation_evidence_20261029.md")
evidence[matrix$issue_id=="E36"] <- paste(
  "Complete 32-cell posterior/design/oracle evidence is unavailable locally;",
  "no new one-step numerical comparison or interval was invented.")
evidence[matrix$issue_id %in% c("A03","E43","E44","E46","E47","E48")] <- paste(
  "Unit-member target and source-count derivations; historical results explicitly labeled;",
  "18 new fits required before atomic result replacement.")
out <- data.frame(issue_id=matrix$issue_id, source_ids=matrix$source_ids,
  destination=matrix$exact_destination, planned_action=matrix$bounded_action,
  acceptance_criterion=matrix$acceptance_criterion, status=status,
  implementation_evidence=evidence, stringsAsFactors=FALSE)
dir.create("docs/reproducibility", showWarnings=FALSE, recursive=TRUE)
write.csv(out, "docs/reproducibility/advisor_revision_resolution_20261029.csv",
  row.names=FALSE, na="")
cat("ADVISOR_RESOLUTION_CROSSWALK=115 records; implementation is not scientific or publication closure.\n")
