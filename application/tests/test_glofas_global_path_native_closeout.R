local({
  source("scripts/diagnostics/glofas_global_path_native_closeout.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  controls <- jsonlite::read_json(
    "scripts/diagnostics/glofas_global_path_native_controls.json",
    simplifyVector = FALSE)
  summary <- data.frame(contract = c("a", "b", "c"),
    method = c("importance", "tempered", "tempered"),
    status = c("REFERENCE_GATE_PASS", "REFERENCE_GATE_FAIL", "REFERENCE_GATE_FAIL"),
    complete = TRUE, particles = c(2048, 256, 256),
    evaluations = c(2048, 1280, 1280),
    effective_sample_size = c(300, 200, 100),
    maximum_weight = c(.01, .0105, .03), normalized_entropy = c(.9, .9, .5),
    elapsed_seconds = 1)
  classified <- ggpc_classify(summary, controls)
  ok(identical(classified$classification,
    c("STRICT_PASS", "NEAR_PASS_WEIGHT_ONLY", "FAIL")))
  reporting <- expand.grid(contract = c("a", "b"), horizon = 1:3,
    reporting_operator = c("one", "two"), stringsAsFactors = FALSE)
  reporting$estimate <- reporting$horizon + ifelse(reporting$reporting_operator ==
    "two", .5, 0)
  differences <- ggpc_operator_differences(reporting)
  ok(nrow(differences) == 2L &&
    all(abs(differences$mean_absolute_difference - .5) < 1e-12) &&
    all(abs(differences$maximum_absolute_difference - .5) < 1e-12))
  bad <- summary; bad$particles <- NULL
  ok(inherits(try(ggpc_classify(bad, controls), silent = TRUE), "try-error"))
  cat(sprintf("GLOFAS_GLOBAL_PATH_NATIVE_CLOSEOUT_PASS checks=%d authentic_reads=0\n", n))
})
