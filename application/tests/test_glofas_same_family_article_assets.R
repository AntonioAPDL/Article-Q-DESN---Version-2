# Generated presentation fixtures only. No authentic fit, design or truth is read.
(function() {
  env <- new.env(parent = globalenv())
  sys.source("scripts/check_glofas_same_family_article_assets.R", envir = env)
  # Nested scripts use source(); retain an isolated lexical environment for tests.
  for (name in ls(globalenv(), pattern = "^gsaa_")) assign(name, get(name, globalenv()), env)
  for (name in ls(env, pattern = "^gsaa_")) if (is.function(env[[name]])) environment(env[[name]]) <- env
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x));checks <<- checks + 1L;invisible(TRUE) }
  reject <- function(expr, pattern = NULL) {
    error <- tryCatch({ force(expr);NULL }, error = identity)
    ok(inherits(error, "error"))
    if (!is.null(pattern)) ok(grepl(pattern, conditionMessage(error), fixed = TRUE))
  }
  base <- normalizePath("local_trackers", mustWork = TRUE)
  tmp <- tempfile("glofas_assets_generated_", tmpdir = base);dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE) # Only this newly created fixture directory.
  families <- gsc_families();tau <- gsc_tau();dates <- gsc_dates()
  rows <- expand.grid(family = families, horizon = 1:28, tau = tau, stringsAsFactors = FALSE)
  rows$target_date <- as.character(dates[rows$horizon])
  rows$quantile_transformed <- 3 + .01 * rows$horizon + .35 * qnorm(rows$tau)
  # Retain a real crossing in generated figures rather than silently ordering it.
  j <- which(rows$family == "MQ AL" & rows$horizon == 1L & rows$tau == .20)
  rows$quantile_transformed[j] <- 4
  rows$quantile <- expm1(rows$quantile_transformed)
  truth <- data.frame(target_date = as.character(dates), horizon = 1:28, y_transformed = 3.2 + .15 * sin(1:28))
  metrics <- gspm_metrics(rows, truth)
  history <- data.frame(target_date = as.character(seq(as.Date("2022-11-26"), as.Date("2022-12-25"), by = "day")),
    y_transformed = 3 + .1 * sin(1:30), g_transformed = 3.1 + .12 * sin(1:30))
  members <- expand.grid(horizon = 1:28, member = sprintf("member%02d", 1:51), stringsAsFactors = FALSE)
  members$target_date <- as.character(dates[members$horizon])
  members$g_transformed <- 3.1 + .01 * members$horizon + as.numeric(factor(members$member)) / 100
  fitted <- expand.grid(family = families[-1L], target_date = history$target_date, tau = tau, stringsAsFactors = FALSE)
  fitted$quantile_transformed <- 3 + .3 * qnorm(fitted$tau)
  fitted$quantile <- expm1(fitted$quantile_transformed)
  fitted$time_role <- "historical_fitted_conditional_quantile"
  fitted$estimand <- "VB_mean_conditional_quantile_on_log1p_scale"
  for (k in c("future_path_factor_used", "posterior_predictive_quantile", "quantile_functional_credible_interval",
    "extra_response_noise_added", "isotonic_adjustment")) fitted[[k]] <- FALSE
  ok(env$gsaa_history_grid(fitted))
  bad <- fitted[-1L, ];reject(env$gsaa_history_grid(bad), "all six")
  bad <- fitted;bad$target_date[1L] <- "2022-12-26";reject(env$gsaa_history_grid(bad), "historical dates")
  bad <- fitted;bad$isotonic_adjustment[1L] <- TRUE;reject(env$gsaa_history_grid(bad), "historical dates")
  bad <- fitted;bad$quantile[1L] <- bad$quantile[1L] + 1;reject(env$gsaa_history_grid(bad), "historical dates")
  bad <- fitted;bad$posterior_predictive_quantile[1L] <- TRUE;reject(env$gsaa_history_grid(bad), "historical dates")
  convergence <- data.frame(task_id = gsc_tasks(), numerical_gates_pass = TRUE,
    iterations = c(rep(100L, 14), NA_integer_, NA_integer_), outer_iterations = c(rep(NA_integer_, 14), 11L, 22L),
    terminal_consecutive_passes = c(rep(NA_integer_, 14), 3L, 3L), wall_seconds = seq(1000, 16000, length.out = 16),
    cpu_seconds = seq(900, 15000, length.out = 16), max_rss_bytes = rep(1024^3, 16))
  convergence_file <- file.path(tmp, "convergence.csv");write.csv(convergence, convergence_file, row.names = FALSE)
  pin <- function(path) list(path = path, size_bytes = as.numeric(file.info(path)$size), sha256 = unname(tools::sha256sum(path)))
  original <- pin(convergence_file);con <- env$gsaa_convergence(original);ok(nrow(con) == 16)
  bad <- convergence;bad$terminal_consecutive_passes[16] <- 2
  write.csv(bad, convergence_file, row.names = FALSE);reject(env$gsaa_convergence(pin(convergence_file)), "three complete passes")
  bad <- convergence;bad$numerical_gates_pass[1] <- FALSE
  write.csv(bad, convergence_file, row.names = FALSE);reject(env$gsaa_convergence(pin(convergence_file)), "sixteen accepted")
  write.csv(convergence, convergence_file, row.names = FALSE)
  reject(env$gsaa_convergence(list(path = convergence_file, size_bytes = 1, sha256 = strrep("0", 64))), "pinned regular")
  z <- list(rows = rows, truth = truth, metrics = metrics, history = history, members = members, fitted = fitted,
    convergence = con, lineage = list(scientific_source = gsc_identity(), packet_manifest_sha256 = strrep("a", 64),
      extraction_manifest_sha256 = strrep("b", 64), fitted_history_manifest_sha256 = strrep("c", 64),
      convergence_sha256 = original$sha256, derived_metrics_manifest_sha256 = NULL))
  table <- env$gsaa_tables(z)
  ok(length(table) == 4L && length(table$main_scores) == 13L)
  ok(any(grepl("Crossings", table$main_scores)) && !any(grepl("Reduction", table$main_scores)))
  ok(any(grepl("MQ--DESN (exAL)", table$main_scores, fixed = TRUE)))
  alias <- env$gsaa_aliases(z)
  ok(any(grepl("GlofasApplicationCurrentIssuedSupplementScoreTable", alias, fixed = TRUE)))
  ok(!any(grepl("renewcommand{\\GlofasApplicationCurrentSupplementScoreTable}", alias, fixed = TRUE)))
  ok(identical(env$gsaa_style()$quantiles, rev(env$gsaa_style()$quantiles)))
  ok(env$gsaa_style()$quantile_line_mm == .15 && env$gsaa_style()$quantile_lwd == .57)
  ok(env$gsaa_style()$future_points == 1L && env$gsaa_style()$historical_points == 16L)
  ok(length(env$gsaa_expected_files()) == 19L)
  reject(env$gsaa_output(file.path(tmp, "..", "unsafe")), "fresh ignored")
  broken <- file.path(tmp, "broken_candidate")
  ok(file.symlink(file.path(tmp, "nonexistent_target"), broken))
  reject(env$gsaa_output(broken), "fresh ignored")
  unlink(broken) # Only this newly created generated broken link.
  reject(env$gsaa_cli(character()), "exact packet")
  # Rendering/derivative checks use an explicitly substituted pure generated input
  # bundle. Authentication gates are not bypassed in production code.
  real_inputs <- env$gsaa_inputs
  env$gsaa_inputs <- function(...) z
  out <- file.path(tmp, "candidate")
  args <- list("synthetic", strrep("a", 64), "synthetic", strrep("b", 64), "synthetic", strrep("c", 64), original)
  result <- do.call(env$gsaa_build, c(args, list(output_root = out)))
  ok(dir.exists(out) && gsc_hash_string(result$manifest_sha256))
  ok(do.call(env$gsaa_check, c(args, list(candidate_root = out))))
  ok(file.info(file.path(out, "figures/glofas_application/glofas_same_family_20261103_main.pdf"))$size > 10000)
  for (kind in c("main", "all_families", "calibration", "convergence")) {
    qa <- env$gsaa_pdf_geometry(file.path(out, "figures/glofas_application",
      paste0(env$gsaa_prefix(), "_", kind, ".pdf")), main = kind == "main")
    ok(qa$effective_minimum_points >= 8)
  }
  tiny <- file.path(tmp, "tiny_text.pdf")
  env$gsaa_pdf(tiny, 6.65, 7.6, {
    graphics::par(mar = rep(0, 4));graphics::plot.new()
    graphics::text(.5, .5, "Tiny lettering", cex = .3)
  })
  reject(env$gsaa_pdf_geometry(tiny), "smaller than eight points")
  clipped <- file.path(tmp, "clipped_text.pdf")
  env$gsaa_pdf(clipped, 6.65, 7.6, {
    graphics::par(mar = rep(0, 4));graphics::plot.new()
    graphics::text(0, .5, "Clipped label", adj = 1, xpd = NA)
  })
  reject(env$gsaa_pdf_geometry(clipped), "extends outside")
  overlapping <- file.path(tmp, "overlapping_legend.pdf")
  env$gsaa_pdf(overlapping, 6.65, 7.6, {
    graphics::par(mar = rep(0, 4));graphics::plot.new()
    graphics::text(.5, .2, "Date");graphics::text(.5, .201, "Quantile")
  })
  reject(env$gsaa_pdf_geometry(overlapping, main = TRUE), "overlap")
  csv <- read.csv(file.path(out, "tables/glofas_same_family_20261103_quantile_paths.csv"))
  ok(identical(csv$quantile_transformed[j], rows$quantile_transformed[j]))
  mpath <- file.path(out, env$gsaa_manifest_relative())
  reseal <- function() {
    m <- read.csv(mpath, stringsAsFactors = FALSE);p <- file.path(out, m$relative_path)
    m$size_bytes <- as.numeric(file.info(p)$size);m$sha256 <- unname(tools::sha256sum(p));write.csv(m, mpath, row.names = FALSE)
  }
  tf <- file.path(out, "tables/glofas_same_family_20261103_main_scores.tex")
  original_table <- readLines(tf);writeLines("Changed labels", tf);reseal()
  reject(do.call(env$gsaa_check, c(args, list(candidate_root = out))), "table labels")
  writeLines(original_table, tf);reseal()
  af <- file.path(out, "tables/glofas_same_family_20261103_display_aliases.tex")
  original_alias <- readLines(af);writeLines("Changed aliases", af);reseal()
  reject(do.call(env$gsaa_check, c(args, list(candidate_root = out))), "aliases changed")
  writeLines(original_alias, af);reseal()
  cf <- file.path(out, "tables/glofas_same_family_20261103_family_metrics.csv")
  original_csv <- read.csv(cf);changed <- original_csv;changed$grid_acrps_log1p[1] <- 0
  write.csv(changed, cf, row.names = FALSE);reseal()
  reject(do.call(env$gsaa_check, c(args, list(candidate_root = out))), "numerical/source CSV")
  write.csv(original_csv, cf, row.names = FALSE);reseal()
  decision_file <- file.path(out, env$gsaa_decision_relative())
  decision <- jsonlite::read_json(decision_file, simplifyVector = FALSE)
  changed <- decision;changed$style$quantile_line_mm <- .3
  jsonlite::write_json(changed, decision_file, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null");reseal()
  reject(do.call(env$gsaa_check, c(args, list(candidate_root = out))), "requested thin lines")
  jsonlite::write_json(decision, decision_file, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null");reseal()
  changed <- decision;changed$article_publication_authorized <- TRUE
  jsonlite::write_json(changed, decision_file, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null");reseal()
  reject(do.call(env$gsaa_check, c(args, list(candidate_root = out))), "candidate authority")
  jsonlite::write_json(decision, decision_file, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null");reseal()
  writeLines("unapproved", file.path(out, "fit.rds"))
  reject(do.call(env$gsaa_check, c(args, list(candidate_root = out))), "membership")
  unlink(file.path(out, "fit.rds")) # Only this generated mutation file.
  ok(do.call(env$gsaa_check, c(args, list(candidate_root = out))))
  env$gsaa_inputs <- real_inputs
  cat("GloFAS same-family article-assets generated tests PASS:", checks, "checks\n")
})()
