latent_cfg <- app_read_config(app_path("application/config/glofas_latent_path_al_vb_dec25_main.yaml"))
engine_report <- app_check_qdesn_engine_api(
  latent_cfg,
  require_discrepancy = FALSE,
  stop_on_failure = FALSE
)
stopifnot(is.list(engine_report))
stopifnot(identical(engine_report$engine, latent_cfg$dependencies$qdesn_engine))
stopifnot(isTRUE(engine_report$ok))
stopifnot(isTRUE(engine_report$source_policy_ok))
stopifnot(!"qdesn_fit_discrepancy" %in% engine_report$required_exports)
stopifnot(identical(engine_report$repo_git_sha, latent_cfg$dependencies$qdesn_engine_required_commit))
stopifnot(identical(engine_report$repo_branch, latent_cfg$dependencies$qdesn_engine_required_branch))
engine_row <- app_qdesn_engine_contract_row(engine_report)
stopifnot(all(c(
  "engine", "installed", "required_exports", "missing_exports", "repo_branch",
  "load_mode", "version", "repo_hint", "repo_git_sha",
  "source_policy_ok", "source_policy_message", "expected_repo_hint",
  "required_branch", "required_commit", "required_load_mode",
  "min_version", "ok", "message"
) %in% names(engine_row)))
stopifnot(identical(engine_row$load_mode, "local_source"))
stopifnot(identical(engine_row$repo_hint, latent_cfg$dependencies$qdesn_engine_repo_hint))
stopifnot(identical(engine_row$required_commit, latent_cfg$dependencies$qdesn_engine_required_commit))

origin_report <- app_check_qdesn_engine_api(
  cfg,
  require_discrepancy = TRUE,
  stop_on_failure = FALSE
)
stopifnot(!isTRUE(origin_report$ok))
stopifnot("qdesn_fit_discrepancy" %in% origin_report$required_exports)
stopifnot("qdesn_fit_discrepancy" %in% origin_report$missing_exports)

stopifnot(identical(app_map_qdesn_prior("rhs"), "rhs_ns"))
stopifnot(identical(app_map_qdesn_prior("rhs_ns"), "rhs_ns"))
stopifnot(identical(app_map_qdesn_prior("ridge"), "ridge"))
stopifnot(identical(app_map_qdesn_prior(NA), "rhs_ns"))

stats_cfg <- cfg
stats_cfg$dependencies$qdesn_engine <- "stats"
stats_cfg$dependencies$qdesn_engine_repo_hint <- NULL
stats_report <- app_check_qdesn_engine_api(
  stats_cfg,
  require_discrepancy = TRUE,
  stop_on_failure = FALSE
)
stopifnot(isTRUE(stats_report$installed))
stopifnot(!isTRUE(stats_report$ok))
stopifnot("qdesn_fit" %in% stats_report$missing_exports)

stale_cfg <- latent_cfg
stale_cfg$dependencies$qdesn_engine_repo_hint <- "/data/jaguir26/local/src/exdqlm__wt__glofas_discrepancy_qdesn"
stale_report <- app_check_qdesn_engine_api(
  stale_cfg,
  require_discrepancy = FALSE,
  stop_on_failure = FALSE
)
stopifnot(!isTRUE(stale_report$ok))
stopifnot(!isTRUE(stale_report$source_policy_ok))
stopifnot(grepl("expected_path=", stale_report$source_policy_message, fixed = TRUE))
