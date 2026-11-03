# The generated-only driver must preserve the known adverse approximation result.
source("scripts/audit_glofas_fixed_target_diagnostics.R")
report <- gftd_generated_report()
stopifnot(identical(report$software_status, "PASS"),
          identical(report$approximation_accuracy_status, "FAIL"),
          identical(report$scientific_campaign_authorized, FALSE),
          identical(report$scientific_runs, 0L),
          identical(report$authentic_reads, 0L),
          identical(report$future_truth_read, FALSE),
          any(report$generated_checks$approximation_accuracy == "FAIL"),
          all(report$generated_checks$reference_validity == "PASS"))
bad <- try(gftd_generated_main(c("--out-dir", tempdir(), "--read-model")), silent = TRUE)
stopifnot(inherits(bad, "try-error"))
message("GloFAS fixed-target generated driver tests: PASS")
