#!/usr/bin/env Rscript
# Authenticated reporting-only enrollment; never fits, scores, or publishes.
gnr_local_reporting_host <- function(host = unname(Sys.info()[["nodename"]])) {
  is.character(host) && length(host) == 1L &&
    host %in% c("muscat", "muscat.be.ucsc.edu")
}
gnr_main <- function(args = commandArgs(TRUE)) {
  if (identical(args, "--help")) {
    cat("Usage: Rscript scripts/enroll_glofas_normal_baselines.R --contract FILE --contract-sha256 SHA256 --execute\n")
    return(invisible(NULL))
  }
  stopifnot(length(args) == 5L, args[[1L]] == "--contract",
    args[[3L]] == "--contract-sha256", args[[5L]] == "--execute")
  source("application/scripts/_glofas_unit_member_bootstrap.R")
  source("application/R/glofas_family_transition.R")
  source("scripts/glofas_normal_reuse_enrollment.R")
  require <- app_gnr_require
  contract_path <- normalizePath(args[[2L]], mustWork = TRUE)
  require(file.info(contract_path)$size <= 1024^2 &&
    grepl("^[a-f0-9]{64}$", args[[4L]]) &&
    identical(unname(tools::sha256sum(contract_path)), args[[4L]]),
    "exact bounded enrollment contract")
  spec <- jsonlite::read_json(contract_path, simplifyVector = FALSE)
  require(identical(spec$schema_version, "glofas_normal_reporting_enrollment_v1") &&
    isTRUE(spec$allow_reporting_only) && identical(spec$allow_fitting, FALSE) &&
    identical(spec$allow_scoring, FALSE) && identical(spec$allow_publication, FALSE) &&
    is.character(spec$approved_by) && nzchar(spec$approved_by),
    "explicit reporting-only scope")
  root <- normalizePath(getwd(), mustWork = TRUE)
  require(!startsWith(contract_path, paste0(root, "/")), "external execution contract")
  git <- function(x) {
    out <- system2("git", c("--no-replace-objects", x), stdout = TRUE)
    require(is.null(attr(out, "status")), "Git verification failed")
    unname(out)
  }
  require(identical(git(c("rev-parse", "HEAD")), spec$source_commit) &&
    identical(git(c("rev-parse", "HEAD^{tree}")), spec$source_tree) &&
    length(git(c("status", "--porcelain", "--untracked-files=normal"))) == 0L,
    "clean frozen reporting source")
  expiry <- as.POSIXct(spec$expires_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  require(!is.na(expiry) && expiry > Sys.time() + 300, "finite complete execution lifetime")
  require(identical(spec$host, "muscat") &&
    gnr_local_reporting_host() && identical(unname(Sys.info()[["sysname"]]), "Linux") &&
    identical(as.character(getRversion()), "4.6.0"), "local reporting host and pinned R version")
  # The wrapper is intentionally not a production-task or authorization path.
  # It neither creates a claim in the fitting ledger nor modifies that ledger.
  limits <- readLines("/proc/self/limits", warn = FALSE)
  cpu <- grep("^Max cpu time", limits, value = TRUE)
  memory <- grep("^Max address space", limits, value = TRUE)
  number <- function(x, prefix) as.numeric(strsplit(trimws(sub(prefix, "", x)), "[[:space:]]+")[[1L]][1:2])
  require(length(cpu) == 1L && all(is.finite(number(cpu, "^Max cpu time"))) &&
    all(number(cpu, "^Max cpu time") <= 240) &&
    length(memory) == 1L && all(is.finite(number(memory, "^Max address space"))) &&
    all(number(memory, "^Max address space") <= 32 * 1024^3),
    "finite 240-CPU-second / 32-GiB process limits")
  affinity <- readLines("/proc/self/status", warn = FALSE)
  affinity <- trimws(sub("^Cpus_allowed_list:", "", grep("^Cpus_allowed_list:", affinity, value = TRUE)))
  require(identical(affinity, as.character(spec$logical_cpu)) && spec$logical_cpu == 26L,
    "one separately reserved administrative CPU, not an active fitting core")
  require(all(Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")) == "1"),
    "single-thread reporting environment")
  ancestor <- Sys.getpid(); bounded_wall <- FALSE
  for (level in seq_len(12L)) {
    status <- readLines(sprintf("/proc/%d/status", ancestor), warn = FALSE)
    parent <- as.integer(trimws(sub("^PPid:", "", grep("^PPid:", status, value = TRUE))))
    if (length(parent) != 1L || is.na(parent) || parent <= 1L) break
    cmd <- readBin(sprintf("/proc/%d/cmdline", parent), "raw", n = 65536L)
    if (length(cmd)) {
      # Decode NUL-separated arguments without evaluating shell text.
      nul <- which(cmd == as.raw(0)); starts <- c(1L, head(nul, -1L) + 1L)
      argv <- vapply(seq_along(nul), function(i) {
        if (nul[[i]] <= starts[[i]]) "" else rawToChar(cmd[starts[[i]]:(nul[[i]] - 1L)])
      }, character(1L))
      if (length(argv) >= 4L && basename(argv[[1L]]) == "timeout") {
        bounded_wall <- identical(argv[2:4], c("--signal=TERM", "--kill-after=1", "299"))
        break
      }
    }
    ancestor <- parent
  }
  require(bounded_wall, "whole-purpose external timeout299 plus at most one forced-termination second")
  output <- spec$output_root
  require(is.character(output) && length(output) == 1L &&
    startsWith(output, paste0(root, "/local_trackers/")) && !file.exists(output) &&
    !grepl("(^|/)\\.\\.(/|$)", output), "new ignored reporting namespace")
  require(length(git(c("check-ignore", "--", shQuote(output)))) == 1L,
    "reporting output is excluded from Git")
  for (path in c(contract_path, root, dirname(output))) {
    current <- "/"
    for (part in strsplit(path, "/", fixed = TRUE)[[1L]]) if (nzchar(part)) {
      current <- file.path(current, part)
      link <- Sys.readlink(current)
      require(is.na(link) || !nzchar(link), "no symlink namespace components")
    }
  }
  verify_file <- function(binding) {
    app_gnr_file_binding(binding)
    invisible(binding$path)
  }
  for (binding in spec$source_files) verify_file(binding)
  phase <- function(label) cat(sprintf("NORMAL_ENROLLMENT_PHASE=%s cpu_seconds=%.3f utc=%s\n",
    label, sum(proc.time()[1:2]), format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  phase("reading_original_design")
  original <- app_gnr_read_pinned_rds(spec$original_design)
  phase("reading_prepared_design")
  prepared <- app_gnr_read_pinned_rds(spec$prepared_design)
  phase("comparing_protected_design_values")
  identity <- app_gnr_compare_designs(original$object, prepared$object,
    expected_transition_contract = app_glofas_family_transition_contract())
  phase("protected_design_identity_verified")
  dates <- as.character(prepared$object$future_key$target_date)
  require(length(dates) == 28L && !anyDuplicated(dates), "complete prepared forecast dates")
  rm(prepared); gc(FALSE)
  require(identical(sort(names(spec$models)), c("normal_rhs", "normal_ridge")),
    "both baselines enrolled together")
  receipts <- list(); rows <- list(); bindings <- list()
  for (model in c("normal_ridge", "normal_rhs")) {
    phase(paste0("enrolling_", model))
    item <- spec$models[[model]]
    for (name in c("configuration", "model_grid", "target_receipt", "runtime_receipt")) {
      verify_file(item[[name]])
    }
    fit <- app_gnr_read_pinned_rds(item$fit)
    config <- yaml::read_yaml(item$configuration$path)
    grid <- read.csv(item$model_grid$path, stringsAsFactors = FALSE, check.names = FALSE)
    target <- jsonlite::read_json(item$target_receipt$path, simplifyVector = FALSE)
    runtime <- read.csv(item$runtime_receipt$path, stringsAsFactors = FALSE,
      check.names = FALSE, colClasses = "character", na.strings = character())
    for (name in c("configuration", "model_grid", "target_receipt", "runtime_receipt")) {
      verify_file(item[[name]])
    }
    expected <- item$expected
    expected$model <- model
    enrolled <- app_gnr_enroll_fit(fit, identity, original$binding, config,
      grid, target, runtime, expected)
    require(identical(as.character(enrolled$rows$target_date), rep(dates, 7L)),
      "analytic rows preserve every prepared forecast date in each probability block")
    receipts[[model]] <- enrolled$receipt
    rows[[model]] <- enrolled$rows
    bindings[[model]] <- item
    phase(paste0(model, "_report_verified"))
    rm(fit, enrolled); gc(FALSE)
  }
  # Source binding is rechecked after all retained reads and before any output.
  phase("final_input_reverification")
  for (binding in spec$source_files) verify_file(binding)
  app_gnr_file_binding(spec$original_design)
  app_gnr_file_binding(spec$prepared_design)
  for (item in spec$models) for (name in c("fit", "configuration", "model_grid",
      "target_receipt", "runtime_receipt")) verify_file(item[[name]])
  require(dir.create(output, recursive = TRUE), "fresh output directory creation")
  write.csv(do.call(rbind, rows), file.path(output, "normal_response_quantiles.csv"), row.names = FALSE)
  receipt <- list(schema_version = "glofas_normal_reporting_enrollment_receipt_v1",
    status = "TWO_BASELINES_ENROLLED_NOT_ARTICLE_AUTHORITY", source_commit = spec$source_commit,
    source_tree = spec$source_tree, execution_contract_sha256 = args[[4L]],
    original_design = original$binding, prepared_design = spec$prepared_design,
    design_identity = identity, models = receipts, input_bindings = bindings,
    source_files = spec$source_files, new_model_fits = 0L, scoring_calls = 0L,
    publication_performed = FALSE, completed_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  jsonlite::write_json(receipt, file.path(output, "normal_reuse_enrollment.json"),
    auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null")
  artifacts <- file.path(output, c("normal_response_quantiles.csv", "normal_reuse_enrollment.json"))
  manifest <- data.frame(relative_path = basename(artifacts),
    size_bytes = unname(file.info(artifacts)$size), sha256 = unname(tools::sha256sum(artifacts)))
  write.csv(manifest, file.path(output, "artifact_manifest.csv"), row.names = FALSE)
  require(sum(file.info(list.files(output, full.names = TRUE))$size) < 64 * 1024^2,
    "bounded reporting artifact bytes")
  cat("NORMAL_REUSE_ENROLLMENT_PASS baselines=2 rows=392 new_fits=0 scoring=0 publication=0\n")
  invisible(receipt)
}
if (sys.nframe() == 0L) gnr_main()
