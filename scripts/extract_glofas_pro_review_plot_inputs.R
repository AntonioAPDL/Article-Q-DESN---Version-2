#!/usr/bin/env Rscript
# Plotting-only extraction from the frozen Search III truth-free design.
# This reads, but never changes, the authority ledger, design, or truth sidecar.
options(stringsAsFactors = FALSE, digits = 17)
args <- commandArgs(trailingOnly = TRUE)
value <- function(flag) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) stop("Required argument: ", flag)
  args[[at + 1L]]
}
ledger_path <- normalizePath(value("--authority-ledger"), mustWork = TRUE)
output_dir <- value("--output-dir")
stopifnot(requireNamespace("jsonlite", quietly = TRUE))
sha <- function(path) strsplit(system2("sha256sum", shQuote(path), stdout = TRUE), " +")[[1L]][1L]
ledger <- read.csv(ledger_path, check.names = FALSE)
pins <- c(truth_free_design = "a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9",
          scoring_only_truth_sidecar = "24be9fa631bca346a04a7a855bff5ef3ebc7bf5c748fbade7a213d88fdfe63e6")
sources <- lapply(names(pins), function(role) {
  row <- ledger[ledger$role == role, , drop = FALSE]
  stopifnot(nrow(row) == 1L, row$sha256 == pins[[role]], file.exists(row$path))
  stopifnot(file.info(row$path)$size == row$size_bytes, sha(row$path) == pins[[role]])
  row
})
names(sources) <- names(pins)
cat("Frozen plotting source hashes verified; reading design only.\n")
design <- readRDS(sources$truth_free_design$path)
stopifnot(is.data.frame(design$base_panel), is.data.frame(design$latent_data$g_ensemble))
history <- design$base_panel
stopifnot(all(c("target_date", "y_transformed", "g_transformed") %in% names(history)))
history <- history[c("target_date", "y_transformed", "g_transformed")]
history$target_date <- as.Date(history$target_date)
origin <- as.Date("2022-12-25")
history <- history[history$target_date >= origin - 29 & history$target_date <= origin, ]
history <- history[order(history$target_date), ]
stopifnot(!anyDuplicated(history$target_date), nrow(history) == 30L,
          all(history$target_date == seq(origin - 29, origin, by = "day")),
          all(is.finite(history$y_transformed)), all(is.finite(history$g_transformed)))
ensemble <- design$latent_data$g_ensemble
fields <- c("origin_date", "target_date", "horizon", "member", "g_transformed")
stopifnot(all(fields %in% names(ensemble)))
has_weight <- "ensemble_weight" %in% names(ensemble)
ensemble <- ensemble[c(fields, if (has_weight) "ensemble_weight")]
ensemble$origin_date <- as.Date(ensemble$origin_date)
ensemble$target_date <- as.Date(ensemble$target_date)
ensemble <- ensemble[ensemble$origin_date == origin & ensemble$horizon %in% 1:28, ]
ensemble <- ensemble[order(ensemble$horizon, ensemble$member), ]
stopifnot(nrow(ensemble) == 1428L, length(unique(ensemble$member)) == 51L,
          all(table(ensemble$horizon) == 51L), all(is.finite(ensemble$g_transformed)),
          all(ensemble$target_date == origin + ensemble$horizon),
          !anyDuplicated(ensemble[c("origin_date", "target_date", "member")]))
# No weights are invented: native weights are retained if the field exists.
if (has_weight) stopifnot(all(is.finite(ensemble$ensemble_weight)), all(ensemble$ensemble_weight > 0))
sidecar <- readRDS(sources$scoring_only_truth_sidecar$path)
stopifnot(is.data.frame(sidecar$panel), all(c("target_date", "y_transformed") %in% names(sidecar$panel)))
truth <- sidecar$panel[c("target_date", "y_transformed")]
truth$target_date <- as.Date(truth$target_date)
truth <- truth[truth$target_date %in% seq(origin + 1, origin + 28, by = "day"), ]
truth <- truth[order(truth$target_date), ]
stopifnot(nrow(truth) == 28L, !anyDuplicated(truth$target_date), all(is.finite(truth$y_transformed)))
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
outputs <- c(history = "glofas_search3_review_history_plot_inputs.csv",
             ensemble = "glofas_search3_review_ensemble_plot_inputs.csv",
             scoring_truth = "glofas_search3_review_truth_plot_inputs.csv")
for (role in names(outputs)) write.csv(get(switch(role, history = "history", ensemble = "ensemble", scoring_truth = "truth")),
  file.path(output_dir, outputs[[role]]), row.names = FALSE, na = "")
receipt <- list(schema = "glofas-frozen-plotting-extract-v1", purpose = "Presentation only; no fit, score, smoothing, or selection",
  origin_date = as.character(origin), history_dates = c(as.character(origin - 29), as.character(origin)),
  forecast_dates = c(as.character(origin + 1), as.character(origin + 28)),
  historical_rows = nrow(history), issued_member_rows = nrow(ensemble), issued_members = length(unique(ensemble$member)),
  scoring_truth_rows = nrow(truth), missing_dates = 0L,
  transform = "Existing y_transformed and g_transformed ordinates: log(1 + flow), flow in cubic metres per second; no repeated transform",
  historical_product = "Frozen consolidated GloFAS v3.1/LISFLOOD historical product",
  issued_product_version = "Unavailable in authenticated date/member fields; no version inferred",
  issued_release_timestamp = "Unavailable; origin_date retained without invented time or timezone",
  native_ensemble_weight_present = has_weight,
  native_fields = list(history = names(history), ensemble = names(ensemble), scoring_truth = names(truth)),
  source_authority = lapply(sources, function(row) list(role = row$role, filename = basename(row$path), size_bytes = row$size_bytes, sha256 = row$sha256)),
  extraction_script_sha256 = sha(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])),
  outputs = lapply(outputs, function(filename) list(file = filename, sha256 = sha(file.path(output_dir, filename)))))
jsonlite::write_json(receipt, file.path(output_dir, "glofas_search3_review_plot_input_provenance.json"),
                     pretty = TRUE, auto_unbox = TRUE, digits = 17)
cat("GLOFAS_PLOT_INPUTS_VERIFIED history=30 ensemble=1428 members=51 truth=28\n")
