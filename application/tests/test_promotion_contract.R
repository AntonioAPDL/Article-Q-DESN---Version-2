ignored_config_path <- app_path("application", "runs", "ignored_final_config.yaml")
stopifnot(isTRUE(app_path_is_git_ignored(ignored_config_path)))

final_cfg <- list(execution = list(final_launch = list(enabled = TRUE)))
nonfinal_cfg <- list(execution = list(final_launch = list(enabled = FALSE)))

ignored_error <- tryCatch(
  {
    app_assert_promotion_config_allowed(final_cfg, ignored_config_path, allow_ignored_config = FALSE)
    FALSE
  },
  error = function(e) TRUE
)
stopifnot(isTRUE(ignored_error))

app_assert_promotion_config_allowed(final_cfg, ignored_config_path, allow_ignored_config = TRUE)
app_assert_promotion_config_allowed(nonfinal_cfg, ignored_config_path, allow_ignored_config = FALSE)

tmp_promotion_root <- tempfile("qdesn_promotion_")
run_dirs <- list(
  manifest = file.path(tmp_promotion_root, "manifest"),
  tables = file.path(tmp_promotion_root, "tables")
)
promotion_map <- app_build_promotion_provenance_map(run_dirs, file.path(tmp_promotion_root, "article_tables"), "toy_slug")
stopifnot(is.data.frame(promotion_map))
stopifnot(all(c("role", "source", "dest", "storage_class", "required") %in% names(promotion_map)))
stopifnot(any(promotion_map$role == "run_config_yaml"))
stopifnot(any(promotion_map$role == "qdesn_discrepancy_design_summary"))
stopifnot(all(promotion_map$storage_class == "provenance_snapshot"))
stopifnot(any(!app_as_bool_vec(promotion_map$required)))
