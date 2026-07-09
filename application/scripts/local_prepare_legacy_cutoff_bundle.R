#!/usr/bin/env Rscript
# Purpose: materialize local legacy cutoff-specific GloFAS files into the
# application input schema.
# Inputs: legacy retrospective, ensemble, and USGS daily-average CSV files.
# Outputs: untracked schema-compatible files under application/data_local.
# Failure behavior: stops on missing files, missing columns, duplicate keys, or
# inconsistent ensemble horizons.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  legacy_root = "/data/jaguir26/muscat_data_backup/jaguir26/project1_ucsc_phd",
  cutoff_date = "2022-12-25",
  bundle_root = "application/data_local/frozen_inputs/legacy_dec25_2022",
  station_id = "11160500",
  location_id = "glofas_site11160500",
  allow_unverified_legacy = "false"
))

legacy_root <- app_resolve_path(args$legacy_root, must_work = TRUE)
cutoff_date <- as.Date(args$cutoff_date)
if (is.na(cutoff_date)) stop("--cutoff_date must be a valid date.", call. = FALSE)
bundle_root <- app_resolve_path(args$bundle_root, must_work = FALSE)
station_id <- as.character(args$station_id)
location_id <- as.character(args$location_id)
allow_unverified_legacy <- app_as_bool(args$allow_unverified_legacy)

if (!isTRUE(allow_unverified_legacy)) {
  stop(
    paste(
      "Refusing to materialize a local legacy GloFAS bundle without explicit acknowledgement.",
      "These files are useful for code-path diagnostics but are not the authoritative revised-article input bundle.",
      "Re-run with --allow_unverified_legacy true only for local diagnostic figures.",
      sep = "\n"
    ),
    call. = FALSE
  )
}

retros_path <- file.path(legacy_root, sprintf("retros_%s.csv", cutoff_date))
ensemble_path <- file.path(legacy_root, sprintf("glofas_ens_%s.csv", cutoff_date))
usgs_path <- file.path(legacy_root, "usgs_daily_avg.csv")
for (path in c(retros_path, ensemble_path, usgs_path)) {
  if (!file.exists(path)) stop(sprintf("Missing local legacy input: %s", path), call. = FALSE)
}

retros <- app_read_csv(retros_path)
ensemble_wide <- app_read_csv(ensemble_path)
usgs <- app_read_csv(usgs_path)

app_check_cols <- function(x, required, label) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing required columns: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
}

app_check_cols(retros, c("Date", "USGS", "GloFAS"), "legacy retrospective file")
app_check_cols(ensemble_wide, "Date", "legacy GloFAS ensemble file")
app_check_cols(usgs, c("Date", "Daily_Avg_Log_Streamflow"), "legacy USGS daily-average file")

retros$Date <- as.Date(retros$Date)
ensemble_wide$Date <- as.Date(ensemble_wide$Date)
usgs$Date <- as.Date(usgs$Date)
if (any(is.na(retros$Date)) || any(is.na(ensemble_wide$Date)) || any(is.na(usgs$Date))) {
  stop("At least one legacy input contains invalid Date values.", call. = FALSE)
}

member_cols <- grep("^Ensemble_Member_", names(ensemble_wide), value = TRUE)
if (!length(member_cols)) stop("The legacy GloFAS ensemble file has no Ensemble_Member_* columns.", call. = FALSE)

max_target <- max(ensemble_wide$Date, na.rm = TRUE)
ref_hist <- data.frame(
  date = retros$Date,
  station_id = station_id,
  streamflow = as.numeric(retros$USGS),
  stringsAsFactors = FALSE
)
ref_hist <- ref_hist[ref_hist$date <= cutoff_date, , drop = FALSE]
ref_future <- data.frame(
  date = usgs$Date,
  station_id = station_id,
  streamflow = as.numeric(usgs$Daily_Avg_Log_Streamflow),
  stringsAsFactors = FALSE
)
ref_future <- ref_future[ref_future$date > cutoff_date & ref_future$date <= max_target, , drop = FALSE]
reference_gauge <- rbind(ref_hist, ref_future)
reference_gauge <- reference_gauge[order(reference_gauge$date), , drop = FALSE]
if (anyDuplicated(paste(reference_gauge$station_id, reference_gauge$date))) {
  stop("Materialized reference gauge file would contain duplicate station-date rows.", call. = FALSE)
}
if (!nrow(ref_future)) {
  stop("No held-out USGS reference values were found after the cutoff and before the ensemble maximum target.", call. = FALSE)
}

glofas_retrospective <- data.frame(
  date = retros$Date,
  location_id = location_id,
  glofas_streamflow = as.numeric(retros$GloFAS),
  stringsAsFactors = FALSE
)
glofas_retrospective <- glofas_retrospective[glofas_retrospective$date <= cutoff_date, , drop = FALSE]
glofas_retrospective <- glofas_retrospective[order(glofas_retrospective$date), , drop = FALSE]
if (anyDuplicated(paste(glofas_retrospective$location_id, glofas_retrospective$date))) {
  stop("Materialized retrospective file would contain duplicate location-date rows.", call. = FALSE)
}

ensemble_long <- do.call(
  rbind,
  lapply(seq_along(member_cols), function(j) {
    data.frame(
      origin_date = cutoff_date,
      target_date = ensemble_wide$Date,
      horizon = as.integer(ensemble_wide$Date - cutoff_date),
      member = sprintf("m%03d", j),
      glofas_streamflow = as.numeric(ensemble_wide[[member_cols[[j]]]]),
      stringsAsFactors = FALSE
    )
  })
)
ensemble_long <- ensemble_long[order(ensemble_long$target_date, ensemble_long$member), , drop = FALSE]
if (any(ensemble_long$horizon <= 0L, na.rm = TRUE)) {
  stop("Materialized ensemble file contains non-positive forecast horizons.", call. = FALSE)
}
if (any(as.integer(ensemble_long$target_date - ensemble_long$origin_date) != ensemble_long$horizon, na.rm = TRUE)) {
  stop("Materialized ensemble file has inconsistent target-date and horizon definitions.", call. = FALSE)
}
if (anyDuplicated(paste(ensemble_long$origin_date, ensemble_long$target_date, ensemble_long$horizon, ensemble_long$member))) {
  stop("Materialized ensemble file would contain duplicate origin-target-horizon-member rows.", call. = FALSE)
}

reference_path <- file.path(bundle_root, "reference", "reference_gauge.csv")
retros_out_path <- file.path(bundle_root, "glofas", "glofas_retrospective.csv")
ensemble_out_path <- file.path(bundle_root, "glofas", "glofas_ensemble.csv")
metadata_dir <- file.path(bundle_root, "metadata")

app_write_csv(reference_gauge, reference_path)
app_write_csv(glofas_retrospective, retros_out_path)
app_write_csv(ensemble_long, ensemble_out_path)

source_map <- data.frame(
  input_id = c("reference_gauge", "glofas_retrospective", "glofas_ensemble"),
  provenance_status = "local_legacy_unverified",
  local_source = c(
    paste(retros_path, usgs_path, sep = "; "),
    retros_path,
    ensemble_path
  ),
  output_path = c(reference_path, retros_out_path, ensemble_out_path),
  role = c("reference observations", "retrospective GloFAS path", "GloFAS ensemble forecasts"),
  notes = c(
    "Historical reference uses the legacy retrospective file through cutoff; held-out reference uses the local USGS daily-average file after cutoff.",
    "Values are treated as already transformed and are passed through the application config with identity transforms.",
    "Wide member columns are converted to long format with one row per member and target date."
  ),
  stringsAsFactors = FALSE
)
app_write_csv(source_map, file.path(metadata_dir, "source_map.csv"))

summary_lines <- c(
  sprintf("bundle_root: %s", bundle_root),
  sprintf("cutoff_date: %s", cutoff_date),
  sprintf("station_id: %s", station_id),
  sprintf("location_id: %s", location_id),
  sprintf("reference rows: %d", nrow(reference_gauge)),
  sprintf("reference date range: %s to %s", min(reference_gauge$date), max(reference_gauge$date)),
  sprintf("retrospective rows: %d", nrow(glofas_retrospective)),
  sprintf("retrospective date range: %s to %s", min(glofas_retrospective$date), max(glofas_retrospective$date)),
  sprintf("ensemble rows: %d", nrow(ensemble_long)),
  sprintf("ensemble members: %d", length(unique(ensemble_long$member))),
  sprintf("ensemble target range: %s to %s", min(ensemble_long$target_date), max(ensemble_long$target_date)),
  sprintf("horizon range: %d to %d", min(ensemble_long$horizon), max(ensemble_long$horizon)),
  "provenance status: local_legacy_unverified",
  "audit warning: do not use this bundle for manuscript-facing GloFAS claims until it is replaced by the authoritative revised-article frozen input bundle.",
  "transform note: legacy values are treated as already transformed; use identity transforms in the source-figure config."
)
app_ensure_dir(metadata_dir)
writeLines(summary_lines, file.path(metadata_dir, "data_start_filter_summary.txt"))
writeLines(
  c(
    "WARNING: local legacy GloFAS diagnostic bundle",
    "",
    "This bundle was materialized from legacy local files. It is not the",
    "authoritative revised-article frozen input bundle and should not be used",
    "for manuscript-facing application claims.",
    "",
    "Replace it with the jerez authoritative input bundle before final data",
    "figures, model fitting, scoring, or manuscript promotion."
  ),
  file.path(metadata_dir, "PROVENANCE_WARNING.txt")
)

cat(bundle_root, "\n")
