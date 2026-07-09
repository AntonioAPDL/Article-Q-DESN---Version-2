mg <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
stopifnot(!anyDuplicated(mg$fit_id))
stopifnot(any(mg$model_family == "raw_glofas"))
stopifnot(any(mg$model_family == "qdesn_reference_only"))
stopifnot(any(mg$model_family == "qdesn_glofas_discrepancy"))
stopifnot(any(mg$coefficient_prior == "ridge"))
stopifnot(any(mg$coefficient_prior == "rhs"))
qdesn_rows <- mg[mg$model_family %in% c("qdesn_reference_only", "qdesn_glofas_discrepancy"), , drop = FALSE]
required_qdesn <- qdesn_rows[app_as_bool_vec(qdesn_rows$required), , drop = FALSE]
stopifnot(nrow(required_qdesn) > 0L)
stopifnot(all(required_qdesn$coefficient_prior == "rhs"))
app_validate_qdesn_model_grid_prior_contract(mg)
hash <- app_hash_files(c(
  cfg$.__config_path__,
  app_config_path(cfg, "quantile_grid"),
  app_config_path(cfg, "model_grid")
))
stopifnot(is.character(hash), nchar(hash) >= 8L)
