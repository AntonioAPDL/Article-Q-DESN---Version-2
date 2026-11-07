# Generated-only tail admission checks. No retained payload is read and no
# scientific model is fit.
local({
  source("scripts/glofas_global_path_tail_reader.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(x, pattern = NULL) {
    e <- tryCatch({ force(x); NULL }, error = function(e) e)
    ok(inherits(e, "error"))
    if (!is.null(pattern)) ok(grepl(pattern, conditionMessage(e), fixed = TRUE))
  }
  controls <- jsonlite::read_json(
    "scripts/diagnostics/glofas_global_path_tail_controls.json",
    simplifyVector = FALSE)
  ok(ggtr_task("gft-al-p005") == .05 && ggtr_task("gft-al-p095") == .95)
  reject(ggtr_task("gft-al-p050"), "two admitted")
  ok(is.list(ggtr_controls(controls, "gft-al-p005", "measure")))
  changed <- controls; changed$tasks$`gft-al-p005`$fit_sha256 <- strrep("a", 64L)
  reject(ggtr_controls(changed, "gft-al-p005", "measure"),
    "tail task identity changed")
  reject(ggtr_controls(controls, "gft-al-p005", "execute"),
    "source-bound measurement")
  H <- 3L
  callback <- function(path) list(reference_location = path / 2,
    ensemble_location = path / 3)
  contracts <- gffd_grid("generated", .05, matrix(seq(-.2, .2,
    length.out = 6L), H, 2L), .8, .4, rep(0, H), diag(H),
    "generated-tail-parameters", "generated-tail-features")
  built <- list(mean = rep(0, H), covariance = diag(rep(.2, H)),
    adapter = list(contracts = contracts, callback = callback))
  measurement <- ggrr_measure(built, controls)
  ok(nrow(measurement) == 12L && all(is.finite(measurement$total_log_density)))
  launcher <- readLines("scripts/launch_glofas_global_path_tail.sh", warn = FALSE)
  ok(any(grepl("--kill-after=1s", launcher, fixed = TRUE)) &&
    any(grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE)) &&
    any(grepl("--fsize=", launcher, fixed = TRUE)))
  ok(length(ggtr_sources()) == length(unique(ggtr_sources())) &&
    all(file.exists(ggtr_sources())))
  cat(sprintf(paste0("GLOFAS_GLOBAL_PATH_TAIL_READER_GENERATED_PASS checks=%d ",
    "authentic_reads=0 model_runs=0\n"), n))
})
