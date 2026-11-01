# Negative CLI admission checks; all inputs are synthetic temporary contracts.
source("scripts/qualify_ind_auxiliary_filter.R")
caq_n <- 0L
caq_check <- function(ok) { stopifnot(isTRUE(ok)); caq_n <<- caq_n + 1L }
caq_error <- function(expr, text) {
  e <- tryCatch({force(expr); NULL}, error = identity)
  caq_check(inherits(e, "error") && grepl(text, conditionMessage(e), fixed = TRUE))
}
set.seed(8872); caq_rng <- .Random.seed
help <- capture.output(ind_caf_qualify("--help"))
caq_check(length(help) == 1L && grepl("Usage:", help, fixed = TRUE))
caq_error(ind_caf_qualify(character()), "length(args)")
contract <- list(schema_version = "ind_auxiliary_filter_qualification_v1",
  allow_qualification = TRUE, allow_refit = FALSE, allow_forecast = FALSE,
  allow_production = FALSE, posterior_column = 1L, observed_prefix_length = 500L,
  particle_resolutions = c(32L,64L,128L), seeds = c(71421L,71422L),
  checkpoint_indices = c(100L,250L,500L), ess_fraction = .5,
  limits = list(cpu_seconds = 300, wall_term_seconds = 299,
    wall_kill_after_seconds = 1, address_space_bytes = 16*1024^3, output_bytes = 8*1024^2),
  source_commit = paste(rep("0",40),collapse=""))
contract_path <- tempfile("synthetic_ind_filter_contract_", fileext = ".json")
caq_call <- function(spec, sha = NULL) {
  jsonlite::write_json(spec, contract_path, auto_unbox = TRUE, pretty = TRUE, digits = 17)
  if (is.null(sha)) sha <- unname(tools::sha256sum(contract_path))
  ind_caf_qualify(c("--contract", contract_path, "--sha256", sha, "--execute"))
}
caq_error(caq_call(contract, paste(rep("0",64),collapse="")), "bounded external purpose contract")
for (mutate in list(
  function(x) { x$allow_refit <- TRUE; x },
  function(x) { x$allow_forecast <- TRUE; x },
  function(x) { x$allow_production <- TRUE; x },
  function(x) { x$posterior_column <- 2L; x },
  function(x) { x$observed_prefix_length <- 501L; x },
  function(x) { x$particle_resolutions[1L] <- 32.9; x },
  function(x) { x$particle_resolutions <- c(16L,32L,64L); x },
  function(x) { x$seeds[1L] <- 71421.5; x },
  function(x) { x$checkpoint_indices <- c(100L,251L,500L); x },
  function(x) { x$ess_fraction <- .1; x }
)) caq_error(caq_call(mutate(contract)), "fixed prospective AL training-only probe")
for (key in names(contract$limits)) {
  x <- contract; x$limits[[key]] <- x$limits[[key]] + 1
  caq_error(caq_call(x), "unchanged externally enforced finite qualification limits")
}
caq_error(caq_call(contract), "clean frozen qualification source")
unlink(contract_path)
caq_check(identical(.Random.seed, caq_rng))
cat(sprintf("IND_AUXILIARY_QUALIFICATION_GUARD_CHECKS=%d PASS; protected_reads=0 qualified_runs=0\n", caq_n))
