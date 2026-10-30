# Figure-level provenance for generated application diagnostics.

app_figure_manifest_row <- function(
  figure_id,
  output_path,
  source_script,
  run_id,
  input_manifest,
  panel_hash,
  config_path,
  notes = ""
) {
  data.frame(
    figure_id = figure_id,
    output_path = output_path,
    source_script = source_script,
    run_id = run_id,
    input_manifest = input_manifest,
    panel_hash = panel_hash,
    config_path = config_path,
    git_sha = app_git_sha(short = FALSE),
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    notes = notes,
    stringsAsFactors = FALSE
  )
}

app_write_figure_manifest <- function(rows, path) {
  if (!length(rows)) {
    app_write_csv(data.frame(), path)
    return(invisible(path))
  }
  app_write_csv(do.call(rbind, rows), path)
  invisible(path)
}
