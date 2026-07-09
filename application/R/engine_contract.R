# Q-DESN engine boundary checks for the GloFAS application workflow.

app_qdesn_engine_name <- function(cfg) {
  as.character(cfg$dependencies$qdesn_engine %||% "exdqlm")[[1L]]
}

app_qdesn_engine_repo_hint <- function(cfg) {
  env_hint <- Sys.getenv("QDESN_ENGINE_REPO_HINT", unset = NA_character_)
  hint <- if (!is.na(env_hint) && nzchar(env_hint)) {
    env_hint
  } else {
    cfg$dependencies$qdesn_engine_repo_hint %||% NA_character_
  }
  hint <- as.character(hint)[[1L]]
  if (is.na(hint) || !nzchar(hint)) NA_character_ else hint
}

app_qdesn_required_exports <- function(require_discrepancy = FALSE) {
  out <- c("qdesn_fit", "qdesn_fit_vb", "qdesn_fit_mcmc", "qdesn_build_design")
  if (isTRUE(require_discrepancy)) out <- c(out, "qdesn_fit_discrepancy")
  out
}

app_qdesn_engine_repo_branch <- function(repo_hint) {
  if (is.na(repo_hint) || !nzchar(repo_hint) || !dir.exists(repo_hint)) {
    return(NA_character_)
  }
  out <- tryCatch(
    system2(
      "git",
      c("-C", repo_hint, "rev-parse", "--abbrev-ref", "HEAD"),
      stdout = TRUE,
      stderr = TRUE
    ),
    error = function(e) NA_character_
  )
  if (!length(out)) NA_character_ else out[[1L]]
}

app_qdesn_engine_repo_sha <- function(repo_hint) {
  if (is.na(repo_hint) || !nzchar(repo_hint) || !dir.exists(repo_hint)) {
    return(NA_character_)
  }
  out <- tryCatch(
    system2(
      "git",
      c("-C", repo_hint, "rev-parse", "HEAD"),
      stdout = TRUE,
      stderr = TRUE
    ),
    error = function(e) NA_character_
  )
  if (!length(out)) NA_character_ else out[[1L]]
}

app_qdesn_engine_load_mode <- function(cfg) {
  mode <- cfg$dependencies$qdesn_engine_load_mode %||% "namespace"
  mode <- tolower(as.character(mode)[[1L]])
  if (!mode %in% c("namespace", "local_source", "auto")) {
    stop(sprintf("Unsupported qdesn_engine_load_mode '%s'.", mode), call. = FALSE)
  }
  mode
}

app_qdesn_engine_description_version <- function(repo_hint) {
  desc_path <- file.path(repo_hint, "DESCRIPTION")
  if (!file.exists(desc_path)) return(NA_character_)
  desc <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
  if (is.null(desc) || !"Version" %in% colnames(desc)) return(NA_character_)
  as.character(desc[1L, "Version"])
}

app_qdesn_path_contains <- function(path, needles) {
  path <- as.character(path %||% NA_character_)[[1L]]
  if (is.na(path) || !nzchar(path)) return(FALSE)
  path_norm <- normalizePath(path, mustWork = FALSE)
  needles <- as.character(unlist(needles %||% character(), use.names = FALSE))
  needles <- needles[nzchar(needles)]
  if (!length(needles)) return(FALSE)
  any(vapply(needles, function(needle) {
    needle_norm <- normalizePath(needle, mustWork = FALSE)
    identical(path_norm, needle_norm) ||
      startsWith(path_norm, paste0(needle_norm, .Platform$file.sep)) ||
      grepl(needle, path_norm, fixed = TRUE)
  }, logical(1L)))
}

app_qdesn_version_at_least <- function(version, minimum) {
  version <- as.character(version %||% NA_character_)[[1L]]
  minimum <- as.character(minimum %||% NA_character_)[[1L]]
  if (is.na(minimum) || !nzchar(minimum)) return(TRUE)
  if (is.na(version) || !nzchar(version)) return(FALSE)
  isTRUE(utils::compareVersion(version, minimum) >= 0L)
}

app_qdesn_engine_source_policy <- function(cfg, meta = NULL) {
  deps <- cfg$dependencies %||% list()
  repo_hint <- app_qdesn_engine_repo_hint(cfg)
  load_mode <- (meta$load_mode %||% app_qdesn_engine_load_mode(cfg))
  version <- meta$version %||% app_qdesn_engine_description_version(repo_hint)
  repo_sha <- meta$repo_git_sha %||% app_qdesn_engine_repo_sha(repo_hint)
  repo_branch <- app_qdesn_engine_repo_branch(repo_hint)

  expected_path <- as.character(deps$qdesn_engine_expected_repo_hint %||% NA_character_)[[1L]]
  required_branch <- as.character(deps$qdesn_engine_required_branch %||% NA_character_)[[1L]]
  required_commit <- as.character(deps$qdesn_engine_required_commit %||% NA_character_)[[1L]]
  required_load_mode <- as.character(deps$qdesn_engine_required_load_mode %||% NA_character_)[[1L]]
  min_version <- as.character(deps$qdesn_engine_min_version %||% NA_character_)[[1L]]
  disallowed <- deps$qdesn_engine_disallowed_paths %||% character()

  checks <- list()
  if (!is.na(required_load_mode) && nzchar(required_load_mode)) {
    checks[[length(checks) + 1L]] <- identical(load_mode, required_load_mode)
  }
  if (!is.na(expected_path) && nzchar(expected_path)) {
    checks[[length(checks) + 1L]] <- identical(
      normalizePath(repo_hint, mustWork = FALSE),
      normalizePath(expected_path, mustWork = FALSE)
    )
  }
  if (!is.na(required_branch) && nzchar(required_branch)) {
    checks[[length(checks) + 1L]] <- identical(repo_branch, required_branch)
  }
  if (!is.na(required_commit) && nzchar(required_commit)) {
    checks[[length(checks) + 1L]] <- identical(repo_sha, required_commit)
  }
  if (!is.na(min_version) && nzchar(min_version)) {
    checks[[length(checks) + 1L]] <- app_qdesn_version_at_least(version, min_version)
  }
  if (length(disallowed)) {
    checks[[length(checks) + 1L]] <- !app_qdesn_path_contains(repo_hint, disallowed)
  }

  ok <- if (length(checks)) all(unlist(checks, use.names = FALSE)) else TRUE
  details <- c(
    sprintf("load_mode=%s", load_mode %||% NA_character_),
    sprintf("repo_hint=%s", repo_hint %||% NA_character_),
    sprintf("branch=%s", repo_branch %||% NA_character_),
    sprintf("sha=%s", repo_sha %||% NA_character_),
    sprintf("version=%s", version %||% NA_character_)
  )
  if (!is.na(required_load_mode) && nzchar(required_load_mode)) {
    details <- c(details, sprintf("required_load_mode=%s", required_load_mode))
  }
  if (!is.na(expected_path) && nzchar(expected_path)) {
    details <- c(details, sprintf("expected_path=%s", expected_path))
  }
  if (!is.na(required_branch) && nzchar(required_branch)) {
    details <- c(details, sprintf("required_branch=%s", required_branch))
  }
  if (!is.na(required_commit) && nzchar(required_commit)) {
    details <- c(details, sprintf("required_commit=%s", required_commit))
  }
  if (!is.na(min_version) && nzchar(min_version)) {
    details <- c(details, sprintf("min_version=%s", min_version))
  }
  if (length(disallowed)) {
    details <- c(details, sprintf("disallowed_paths=%s", paste(disallowed, collapse = ";")))
  }

  list(
    ok = ok,
    message = if (ok) "Q-DESN engine source policy satisfied." else paste(details, collapse = " | "),
    repo_branch = repo_branch,
    expected_repo_hint = expected_path,
    required_branch = required_branch,
    required_commit = required_commit,
    required_load_mode = required_load_mode,
    min_version = min_version
  )
}

app_qdesn_contract_from_cfg <- function(cfg, model_row = NULL) {
  if (exists("app_application_model_contract", mode = "function")) {
    return(app_application_model_contract(cfg, model_row))
  }
  row_contract <- NULL
  if (!is.null(model_row) && "application_model_contract" %in% names(model_row)) {
    row_contract <- model_row$application_model_contract[[1L]]
  }
  as.character(row_contract %||% (cfg$application_model %||% list())$contract %||% "origin_state_bridge")[[1L]]
}

app_qdesn_is_latent_path_contract <- function(cfg, model_row = NULL) {
  identical(app_qdesn_contract_from_cfg(cfg, model_row), "latent_path_ensemble_likelihood")
}

app_qdesn_engine_requires_discrepancy_export <- function(cfg, model_grid = NULL) {
  if (!is.null(model_grid) && nrow(model_grid)) {
    enabled <- if ("enabled" %in% names(model_grid)) {
      app_as_bool_vec(model_grid$enabled)
    } else {
      rep(TRUE, nrow(model_grid))
    }
    qrows <- model_grid[
      model_grid$model_family == "qdesn_glofas_discrepancy" & enabled,
      ,
      drop = FALSE
    ]
    if (!nrow(qrows)) return(FALSE)
    return(any(vapply(seq_len(nrow(qrows)), function(i) {
      !app_qdesn_is_latent_path_contract(cfg, qrows[i, , drop = FALSE])
    }, logical(1L))))
  }
  any((cfg$dependencies$qdesn_engine_required_for %||% character()) == "qdesn_glofas_discrepancy") &&
    !app_qdesn_is_latent_path_contract(cfg)
}

.app_qdesn_engine_cache <- new.env(parent = emptyenv())

app_qdesn_local_source_files <- function(repo_hint) {
  required <- file.path(repo_hint, "R", c(
    "00_utils.R",
    "RcppExports.R",
    "utils.R",
    "qdesn_rhs_ns_prior.R",
    "qdesn_rhs_prior.R",
    "priors_beta.R",
    "exal_inference_config.R",
    "exal_mcmc_fit.R",
    "qdesn_vb.R",
    "qdesn_mcmc.R",
    "qdesn_design_only.R"
  ))
  optional <- file.path(repo_hint, "R", "qdesn_discrepancy.R")
  c(required, optional[file.exists(optional)])
}

app_load_qdesn_local_source_engine <- function(repo_hint) {
  if (is.na(repo_hint) || !nzchar(repo_hint) || !dir.exists(repo_hint)) {
    stop("Local Q-DESN engine source path is missing or does not exist.", call. = FALSE)
  }
  repo_hint <- normalizePath(repo_hint, mustWork = TRUE)
  sha <- app_qdesn_engine_repo_sha(repo_hint) %||% "unknown"
  cache_key <- paste(repo_hint, sha, sep = "::")
  if (exists(cache_key, envir = .app_qdesn_engine_cache, inherits = FALSE)) {
    return(get(cache_key, envir = .app_qdesn_engine_cache, inherits = FALSE))
  }

  if (!requireNamespace("Rcpp", quietly = TRUE)) {
    stop(
      "Local source loading of the exdqlm branch requires the R package 'Rcpp' ",
      "because the branch's compiled sampler is called through RcppExports.R.",
      call. = FALSE
    )
  }

  so_path <- file.path(repo_hint, "src", "exdqlm.so")
  if (!file.exists(so_path)) {
    stop(sprintf("Local source engine is missing compiled shared object: %s", so_path), call. = FALSE)
  }
  loaded_dll <- getLoadedDLLs()[["exdqlm"]]
  if (is.null(loaded_dll)) {
    dyn.load(so_path)
  } else {
    loaded_path <- normalizePath(loaded_dll[["path"]], mustWork = FALSE)
    expected_path <- normalizePath(so_path, mustWork = TRUE)
    if (!identical(loaded_path, expected_path)) {
      stop(
        sprintf(
          "An exdqlm shared object is already loaded from %s, but the configured local source path is %s.",
          loaded_path,
          expected_path
        ),
        call. = FALSE
      )
    }
  }

  files <- app_qdesn_local_source_files(repo_hint)
  missing_files <- files[!file.exists(files)]
  if (length(missing_files)) {
    stop(sprintf("Local source engine is missing required R files: %s", paste(missing_files, collapse = ", ")), call. = FALSE)
  }

  env <- new.env(parent = globalenv())
  for (path in files) sys.source(path, envir = env)

  rcpp_exports <- readLines(file.path(repo_hint, "R", "RcppExports.R"), warn = FALSE)
  symbols <- unique(unlist(regmatches(rcpp_exports, gregexpr("_exdqlm_[A-Za-z0-9_]+", rcpp_exports))))
  for (symbol in symbols) {
    assign(symbol, getNativeSymbolInfo(symbol, PACKAGE = "exdqlm"), envir = env)
  }

  attr(env, "qdesn_engine_meta") <- list(
    engine = "exdqlm",
    load_mode = "local_source",
    installed = FALSE,
    loaded = TRUE,
    version = app_qdesn_engine_description_version(repo_hint),
    repo_hint = repo_hint,
    repo_git_sha = sha,
    repo_branch = app_qdesn_engine_repo_branch(repo_hint)
  )
  assign(cache_key, env, envir = .app_qdesn_engine_cache)
  env
}

app_qdesn_namespace_engine <- function(engine) {
  if (!requireNamespace(engine, quietly = TRUE)) return(NULL)
  asNamespace(engine)
}

app_resolve_qdesn_engine_env <- function(cfg) {
  engine <- app_qdesn_engine_name(cfg)
  repo_hint <- app_qdesn_engine_repo_hint(cfg)
  mode <- app_qdesn_engine_load_mode(cfg)

  if (identical(mode, "local_source")) {
    return(app_load_qdesn_local_source_engine(repo_hint))
  }

  ns <- app_qdesn_namespace_engine(engine)
  if (!is.null(ns)) return(ns)

  if (identical(mode, "auto") && !is.na(repo_hint) && dir.exists(repo_hint)) {
    return(app_load_qdesn_local_source_engine(repo_hint))
  }

  NULL
}

app_qdesn_engine_env_meta <- function(env, cfg) {
  engine <- app_qdesn_engine_name(cfg)
  repo_hint <- app_qdesn_engine_repo_hint(cfg)
  mode <- app_qdesn_engine_load_mode(cfg)
  if (is.null(env)) {
    return(list(
      engine = engine,
      load_mode = mode,
      installed = requireNamespace(engine, quietly = TRUE),
      loaded = FALSE,
      version = NA_character_,
      repo_hint = repo_hint,
      repo_git_sha = app_qdesn_engine_repo_sha(repo_hint),
      repo_branch = app_qdesn_engine_repo_branch(repo_hint)
    ))
  }
  meta <- attr(env, "qdesn_engine_meta", exact = TRUE)
  if (is.list(meta)) return(meta)
  list(
    engine = engine,
    load_mode = "namespace",
    installed = TRUE,
    loaded = TRUE,
    version = as.character(utils::packageVersion(engine)),
    repo_hint = repo_hint,
    repo_git_sha = app_qdesn_engine_repo_sha(repo_hint),
    repo_branch = app_qdesn_engine_repo_branch(repo_hint)
  )
}

app_check_qdesn_engine_api <- function(
  cfg,
  require_discrepancy = FALSE,
  stop_on_failure = FALSE
) {
  engine <- app_qdesn_engine_name(cfg)
  repo_hint <- app_qdesn_engine_repo_hint(cfg)
  load_mode <- app_qdesn_engine_load_mode(cfg)
  exports <- app_qdesn_required_exports(require_discrepancy = require_discrepancy)
  missing_exports <- exports
  load_error <- NULL
  env <- tryCatch(
    app_resolve_qdesn_engine_env(cfg),
    error = function(e) {
      load_error <<- conditionMessage(e)
      NULL
    }
  )
  meta <- app_qdesn_engine_env_meta(env, cfg)
  policy <- app_qdesn_engine_source_policy(cfg, meta)

  if (!is.null(env)) {
    missing_exports <- exports[!vapply(exports, exists, logical(1L), envir = env, inherits = FALSE)]
  }

  api_ok <- !is.null(env) && !length(missing_exports)
  ok <- api_ok && isTRUE(policy$ok)
  message <- if (ok) {
    "ok"
  } else if (!is.null(load_error)) {
    load_error
  } else if (!isTRUE(policy$ok)) {
    paste("Q-DESN engine source policy failed:", policy$message)
  } else if (is.null(env)) {
    sprintf("Q-DESN engine '%s' is not available under load mode '%s'.", engine, load_mode)
  } else {
    sprintf(
      "Q-DESN engine '%s' is missing required exports: %s.",
      engine,
      paste(missing_exports, collapse = ", ")
    )
  }

  report <- list(
    ok = ok,
    engine = engine,
    installed = isTRUE(meta$installed),
    loaded = isTRUE(meta$loaded),
    load_mode = meta$load_mode %||% load_mode,
    version = meta$version %||% NA_character_,
    repo_hint = repo_hint,
    repo_hint_exists = !is.na(repo_hint) && dir.exists(repo_hint),
    repo_git_sha = meta$repo_git_sha %||% app_qdesn_engine_repo_sha(repo_hint),
    repo_branch = meta$repo_branch %||% app_qdesn_engine_repo_branch(repo_hint),
    source_policy_ok = isTRUE(policy$ok),
    source_policy_message = policy$message,
    expected_repo_hint = policy$expected_repo_hint,
    required_branch = policy$required_branch,
    required_commit = policy$required_commit,
    required_load_mode = policy$required_load_mode,
    min_version = policy$min_version,
    required_exports = exports,
    missing_exports = missing_exports,
    require_discrepancy = isTRUE(require_discrepancy),
    message = message,
    env = env
  )

  if (!ok && isTRUE(stop_on_failure)) {
    stop(message, call. = FALSE)
  }

  report
}

app_qdesn_engine_contract_row <- function(report) {
  data.frame(
    engine = report$engine,
    load_mode = report$load_mode %||% NA_character_,
    installed = report$installed,
    loaded = report$loaded %||% report$installed,
    version = report$version %||% NA_character_,
    require_discrepancy = report$require_discrepancy,
    required_exports = paste(report$required_exports, collapse = ";"),
    missing_exports = paste(report$missing_exports, collapse = ";"),
    repo_hint = report$repo_hint %||% NA_character_,
    repo_hint_exists = report$repo_hint_exists,
    repo_git_sha = report$repo_git_sha %||% NA_character_,
    repo_branch = report$repo_branch %||% NA_character_,
    source_policy_ok = report$source_policy_ok %||% NA,
    source_policy_message = report$source_policy_message %||% NA_character_,
    expected_repo_hint = report$expected_repo_hint %||% NA_character_,
    required_branch = report$required_branch %||% NA_character_,
    required_commit = report$required_commit %||% NA_character_,
    required_load_mode = report$required_load_mode %||% NA_character_,
    min_version = report$min_version %||% NA_character_,
    ok = report$ok,
    message = report$message,
    stringsAsFactors = FALSE
  )
}

app_require_qdesn_engine <- function(cfg, require_discrepancy = FALSE) {
  report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = require_discrepancy,
    stop_on_failure = TRUE
  )
  report$engine
}

app_qdesn_engine_env <- function(cfg, require_discrepancy = FALSE) {
  report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = require_discrepancy,
    stop_on_failure = TRUE
  )
  report$env
}

app_qdesn_engine_function <- function(cfg, name, require_discrepancy = FALSE) {
  env <- app_qdesn_engine_env(cfg, require_discrepancy = require_discrepancy)
  if (!exists(name, envir = env, inherits = FALSE)) {
    stop(sprintf("Q-DESN engine does not expose %s().", name), call. = FALSE)
  }
  get(name, envir = env, inherits = FALSE)
}

app_map_qdesn_prior <- function(prior) {
  prior <- tolower(as.character(prior[[1L]] %||% "rhs"))
  if (is.na(prior) || !nzchar(prior)) prior <- "rhs"
  switch(
    prior,
    rhs = "rhs_ns",
    rhs_ns = "rhs_ns",
    ridge = "ridge",
    stop(sprintf("Unsupported Q-DESN coefficient prior '%s'.", prior), call. = FALSE)
  )
}

app_model_row_value <- function(model_row, name, default = NULL) {
  if (!name %in% names(model_row)) return(default)
  value <- model_row[[name]][[1L]]
  if (length(value) == 0L || is.na(value)) default else value
}

app_normalize_qdesn_method <- function(method) {
  method <- tolower(as.character(method[[1L]] %||% "mcmc"))
  if (identical(method, "vb_ld")) return("vb")
  method
}

app_model_row_likelihood_family <- function(model_row, cfg) {
  likelihood <- app_model_row_value(model_row, "likelihood_family")
  if (!is.null(likelihood) && !is.na(likelihood) && nzchar(as.character(likelihood)) &&
      !identical(tolower(as.character(likelihood)), "none")) {
    return(tolower(as.character(likelihood[[1L]])))
  }

  method <- app_normalize_qdesn_method(app_model_row_value(
    model_row,
    "inference_method",
    cfg$inference$default_method %||% "mcmc"
  ))
  diagnostic_method <- app_normalize_qdesn_method(cfg$inference$diagnostic_method %||% "")
  if (nzchar(diagnostic_method) && identical(method, diagnostic_method)) {
    diagnostic_likelihood <- cfg$inference$diagnostic_likelihood_family %||% NULL
    if (!is.null(diagnostic_likelihood) && !is.na(diagnostic_likelihood) &&
        nzchar(as.character(diagnostic_likelihood))) {
      return(tolower(as.character(diagnostic_likelihood[[1L]])))
    }
  }

  likelihood <- cfg$inference$likelihood_family %||% "al"
  tolower(as.character(likelihood[[1L]]))
}

app_qdesn_engine_discrepancy_capabilities <- function(engine_report) {
  env <- engine_report$env %||% NULL
  if (!is.null(env) && exists("qdesn_discrepancy_capabilities", envir = env, inherits = FALSE)) {
    caps <- tryCatch(
      get("qdesn_discrepancy_capabilities", envir = env, inherits = FALSE)(),
      error = function(e) NULL
    )
    if (is.data.frame(caps) && all(c("method", "likelihood_family", "fit_supported") %in% names(caps))) {
      caps$method <- vapply(caps$method, app_normalize_qdesn_method, character(1L))
      caps$likelihood_family <- tolower(as.character(caps$likelihood_family))
      caps$fit_supported <- app_as_bool_vec(caps$fit_supported)
      return(caps)
    }
  }

  # Legacy origin-state discrepancy fallback. The current latent-path workflow
  # is article-side and is handled separately in
  # app_qdesn_discrepancy_inference_support().
  data.frame(
    method = "mcmc",
    likelihood_family = "al",
    fit_supported = isTRUE(engine_report$ok),
    support_status = if (isTRUE(engine_report$ok)) "implemented" else "engine_unavailable",
    notes = "Legacy fallback capability contract for qdesn_fit_discrepancy: AL-MCMC only.",
    stringsAsFactors = FALSE
  )
}

app_qdesn_discrepancy_inference_support <- function(cfg, model_grid, engine_report = NULL) {
  if (is.null(engine_report)) {
    engine_report <- app_check_qdesn_engine_api(
      cfg,
      require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, model_grid),
      stop_on_failure = FALSE
    )
  }

  qrows <- model_grid[
    model_grid$model_family == "qdesn_glofas_discrepancy",
    ,
    drop = FALSE
  ]
  if (!nrow(qrows)) return(data.frame())

  caps <- app_qdesn_engine_discrepancy_capabilities(engine_report)
  rows <- vector("list", nrow(qrows))
  for (i in seq_len(nrow(qrows))) {
    row <- qrows[i, , drop = FALSE]
    method_requested <- tolower(as.character(row$inference_method[[1L]]))
    method <- app_normalize_qdesn_method(method_requested)
    likelihood <- app_model_row_likelihood_family(row, cfg)
    prior <- app_map_qdesn_prior(row$coefficient_prior[[1L]])
    latent_article_side <- app_qdesn_is_latent_path_contract(cfg, row) &&
      identical(method, "vb") &&
      identical(likelihood, "al") &&
      prior %in% c("rhs_ns", "ridge") &&
      isTRUE(engine_report$ok)
    hit <- caps[
      caps$method == method &
        caps$likelihood_family == likelihood &
        app_as_bool_vec(caps$fit_supported),
      ,
      drop = FALSE
    ]
    supported <- nrow(hit) > 0L || isTRUE(latent_article_side)
    support_note <- if (isTRUE(latent_article_side)) {
      "Article-side latent-path AL-VB fitter; configured engine supplies the fixed DESN feature map."
    } else if (supported && "notes" %in% names(hit)) {
      hit$notes[[1L]]
    } else {
      "supported by the configured Q-DESN engine"
    }
    rows[[i]] <- data.frame(
      fit_id = row$fit_id[[1L]],
      model_id = row$model_id[[1L]],
      model_family = row$model_family[[1L]],
      quantile_level = as.numeric(row$quantile_level[[1L]]),
      requested_inference_method = method_requested,
      engine_method = method,
      likelihood_family = likelihood,
      coefficient_prior = row$coefficient_prior[[1L]],
      engine_prior = prior,
      required = app_as_bool(row$required[[1L]]),
      enabled = app_as_bool(row$enabled[[1L]]),
      fit_supported = supported,
      support_status = if (isTRUE(latent_article_side)) {
        "implemented_article_side"
      } else if (supported) {
        "implemented"
      } else {
        "unsupported_by_current_engine"
      },
      support_detail = if (supported) {
        support_note %||% "supported by the configured Q-DESN engine"
      } else {
        sprintf(
          "Configured engine currently supports discrepancy pairs: %s.",
          paste(sprintf("method=%s, likelihood=%s", caps$method, caps$likelihood_family), collapse = "; ")
        )
      },
      engine = engine_report$engine,
      engine_repo_sha = engine_report$repo_git_sha %||% NA_character_,
      stringsAsFactors = FALSE
    )
  }
  app_bind_rows_fill(rows)
}

app_qdesn_inference_support_all_fit_ready <- function(support_report, required_only = TRUE) {
  if (!nrow(support_report)) return(TRUE)
  rows <- support_report
  if (isTRUE(required_only)) rows <- rows[app_as_bool_vec(rows$required), , drop = FALSE]
  if (!nrow(rows)) return(TRUE)
  all(app_as_bool_vec(rows$fit_supported))
}

app_qdesn_inference_support_allows_input_gate <- function(cfg, support_report) {
  if (app_qdesn_inference_support_all_fit_ready(support_report, required_only = TRUE)) {
    return(TRUE)
  }
  isTRUE(cfg$execution$inference_support$allow_unsupported_design_gate %||% FALSE) &&
    !isTRUE(cfg$execution$inference_support$require_supported_for_input_check %||% FALSE)
}

app_require_qdesn_inference_support_for_fit <- function(cfg, model_grid, run_dirs = NULL) {
  engine_report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, model_grid),
    stop_on_failure = FALSE
  )
  support <- app_qdesn_discrepancy_inference_support(cfg, model_grid, engine_report)
  if (!is.null(run_dirs) && nrow(support)) {
    app_write_csv(
      app_qdesn_engine_contract_row(engine_report),
      file.path(run_dirs$manifest, "qdesn_engine_contract.csv")
    )
    app_write_csv(support, file.path(run_dirs$manifest, "qdesn_inference_support.csv"))
  }
  unsupported <- support[
    app_as_bool_vec(support$required) & !app_as_bool_vec(support$fit_supported),
    ,
    drop = FALSE
  ]
  if (nrow(unsupported)) {
    stop(
      paste(
        "The configured Q-DESN engine does not support all required discrepancy fits.",
        paste(sprintf(
          "%s requires method=%s, likelihood=%s.",
          unsupported$fit_id,
          unsupported$requested_inference_method,
          unsupported$likelihood_family
        ), collapse = " "),
        "Run the input/design gate, enable the article-side latent-path fitter, or implement the legacy package-side fitter before launching these rows."
      ),
      call. = FALSE
    )
  }
  invisible(support)
}

app_validate_qdesn_model_grid_prior_contract <- function(model_grid) {
  qdesn_rows <- model_grid[
    model_grid$model_family %in% c("qdesn_reference_only", "qdesn_glofas_discrepancy"),
    ,
    drop = FALSE
  ]
  if (!nrow(qdesn_rows)) return(invisible(TRUE))

  bad <- setdiff(unique(qdesn_rows$coefficient_prior), c("ridge", "rhs"))
  if (length(bad)) {
    stop(sprintf("Unsupported Q-DESN coefficient priors in model grid: %s", paste(bad, collapse = ", ")), call. = FALSE)
  }

  required_qdesn <- qdesn_rows[app_as_bool_vec(qdesn_rows$required), , drop = FALSE]
  if (nrow(required_qdesn) && any(required_qdesn$coefficient_prior != "rhs")) {
    stop("Required Q-DESN application fits must use coefficient_prior = 'rhs'.", call. = FALSE)
  }

  invisible(TRUE)
}
