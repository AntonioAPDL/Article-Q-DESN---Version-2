#!/usr/bin/env Rscript

sha256_file <- function(path) {
  output <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

sha256_text <- function(text) {
  path <- tempfile("pricefm-r67-source-contract-")
  on.exit(unlink(path), add = TRUE)
  connection <- file(path, open = "wb")
  writeBin(charToRaw(enc2utf8(text)), connection)
  close(connection)
  sha256_file(path)
}

assigned_expression <- function(path, name) {
  expressions <- as.list(parse(path, keep.source = FALSE))
  matches <- Filter(function(expression) {
    is.call(expression) &&
      identical(expression[[1L]], as.name("<-")) &&
      identical(expression[[2L]], as.name(name))
  }, expressions)
  if (length(matches) != 1L) {
    stop("Expected one assignment for ", name, " in ", path, call. = FALSE)
  }
  matches[[1L]]
}

assigned_hash <- function(path, name) {
  expression <- assigned_expression(path, name)
  sha256_text(paste(deparse(expression, width.cutoff = 500L), collapse = "\n"))
}

public_al_prefix_hash <- function(path) {
  assignment <- assigned_expression(path, "exalStaticLDVB")
  function_call <- assignment[[3L]]
  expressions <- as.list(function_call[[3L]])[-1L]
  target <- which(vapply(expressions, function(expression) {
    grepl("run_static_dqlm_cavi", paste(deparse(expression), collapse = ""), fixed = TRUE)
  }, logical(1L)))
  if (length(target) != 1L) {
    stop("Could not isolate the public AL return branch in ", path, call. = FALSE)
  }
  text <- paste(
    c(
      deparse(function_call[[2L]], width.cutoff = 500L),
      unlist(lapply(expressions[seq_len(target)], deparse, width.cutoff = 500L))
    ),
    collapse = "\n"
  )
  sha256_text(text)
}

description_fields <- function(root) {
  description <- read.dcf(file.path(root, "DESCRIPTION"))
  value <- function(name) if (name %in% colnames(description)) as.character(description[1L, name]) else ""
  list(
    package = value("Package"),
    version = value("Version"),
    repository = value("Repository"),
    packaged = value("Packaged"),
    date_publication = value("Date/Publication")
  )
}

source_contract <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  static_prior <- file.path(root, "R/static_beta_prior.R")
  static_ldvb <- file.path(root, "R/exalStaticLDVB.R")
  utils <- file.path(root, "R/utils.R")
  required <- c(static_prior, static_ldvb, utils, file.path(root, "NAMESPACE"))
  if (any(!file.exists(required))) {
    stop("Source tree is missing required CRAN static files: ", root, call. = FALSE)
  }
  custom_engine <- file.path(root, "R/exal_ldvb_engine.R")
  qdesn_prior <- file.path(root, "R/qdesn_rhs_ns_prior.R")
  structured <- file.path(root, "R/exal_sigmagam_structured.R")
  namespace <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  exports <- sub("^export\\((.*)\\)$", "\\1", grep("^export\\(", namespace, value = TRUE))
  list(
    root = root,
    description = description_fields(root),
    static_beta_prior_sha256 = sha256_file(static_prior),
    public_al_prefix_sha256 = public_al_prefix_hash(static_ldvb),
    static_al_solver_sha256 = assigned_hash(utils, ".run_static_dqlm_cavi"),
    structured_sigmagam_sha256 = if (file.exists(structured)) sha256_file(structured) else "",
    custom_qdesn_engine_present = file.exists(custom_engine),
    custom_qdesn_engine_sha256 = if (file.exists(custom_engine)) sha256_file(custom_engine) else "",
    custom_qdesn_rhs_ns_prior_present = file.exists(qdesn_prior),
    custom_qdesn_rhs_ns_prior_sha256 = if (file.exists(qdesn_prior)) sha256_file(qdesn_prior) else "",
    exact_chunking_surface_present = if (file.exists(custom_engine)) {
      any(grepl("exact_chunking|use_exact_chunking", readLines(custom_engine, warn = FALSE)))
    } else {
      FALSE
    },
    required_public_exports_present = all(c(
      "exalStaticLDVB", "exal_make_vb_control", "exal_make_vb_sigmagam_control"
    ) %in% exports),
    fork_only_exports_present = intersect(c(
      "beta_prior", "exal_ldvb_fit", "normal_desn_fit", "qdesn_fit_vb"
    ), exports),
    exports = sort(exports)
  )
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) {
  stop(
    paste(
      "Usage: pricefm_stage_r67_source_contract.R",
      "CRAN_1.1.0 CRAN_1.1.1 R65_FORK R66_FORK OUTPUT_JSON"
    ),
    call. = FALSE
  )
}

contracts <- list(
  cran_1_1_0 = source_contract(args[[1L]]),
  cran_1_1_1 = source_contract(args[[2L]]),
  r65_fork = source_contract(args[[3L]]),
  r66_fork = source_contract(args[[4L]])
)

comparisons <- list(
  cran_110_vs_111_static_beta_prior_identical = identical(
    contracts$cran_1_1_0$static_beta_prior_sha256,
    contracts$cran_1_1_1$static_beta_prior_sha256
  ),
  cran_110_vs_111_public_al_prefix_identical = identical(
    contracts$cran_1_1_0$public_al_prefix_sha256,
    contracts$cran_1_1_1$public_al_prefix_sha256
  ),
  cran_110_vs_111_static_al_solver_identical = identical(
    contracts$cran_1_1_0$static_al_solver_sha256,
    contracts$cran_1_1_1$static_al_solver_sha256
  ),
  cran_110_vs_111_structured_sigmagam_identical = identical(
    contracts$cran_1_1_0$structured_sigmagam_sha256,
    contracts$cran_1_1_1$structured_sigmagam_sha256
  ),
  cran_111_vs_r65_static_beta_prior_identical = identical(
    contracts$cran_1_1_1$static_beta_prior_sha256,
    contracts$r65_fork$static_beta_prior_sha256
  ),
  cran_111_vs_r65_public_al_prefix_identical = identical(
    contracts$cran_1_1_1$public_al_prefix_sha256,
    contracts$r65_fork$public_al_prefix_sha256
  ),
  cran_111_vs_r65_static_al_solver_identical = identical(
    contracts$cran_1_1_1$static_al_solver_sha256,
    contracts$r65_fork$static_al_solver_sha256
  ),
  cran_111_vs_r65_structured_sigmagam_identical = identical(
    contracts$cran_1_1_1$structured_sigmagam_sha256,
    contracts$r65_fork$structured_sigmagam_sha256
  ),
  cran_111_vs_r66_static_beta_prior_identical = identical(
    contracts$cran_1_1_1$static_beta_prior_sha256,
    contracts$r66_fork$static_beta_prior_sha256
  ),
  cran_111_vs_r66_public_al_prefix_identical = identical(
    contracts$cran_1_1_1$public_al_prefix_sha256,
    contracts$r66_fork$public_al_prefix_sha256
  ),
  cran_111_vs_r66_static_al_solver_identical = identical(
    contracts$cran_1_1_1$static_al_solver_sha256,
    contracts$r66_fork$static_al_solver_sha256
  ),
  cran_111_vs_r66_structured_sigmagam_identical = identical(
    contracts$cran_1_1_1$structured_sigmagam_sha256,
    contracts$r66_fork$structured_sigmagam_sha256
  ),
  r65_vs_r66_structured_sigmagam_identical = identical(
    contracts$r65_fork$structured_sigmagam_sha256,
    contracts$r66_fork$structured_sigmagam_sha256
  ),
  r65_custom_engine_absent_from_cran =
    !contracts$cran_1_1_1$custom_qdesn_engine_present &&
    contracts$r65_fork$custom_qdesn_engine_present,
  r65_exact_chunking_absent_from_cran =
    !contracts$cran_1_1_1$exact_chunking_surface_present &&
    contracts$r65_fork$exact_chunking_surface_present,
  r66_custom_engine_absent_from_cran =
    !contracts$cran_1_1_1$custom_qdesn_engine_present &&
    contracts$r66_fork$custom_qdesn_engine_present,
  r66_exact_chunking_absent_from_cran =
    !contracts$cran_1_1_1$exact_chunking_surface_present &&
    contracts$r66_fork$exact_chunking_surface_present
)

payload <- list(
  status = "source_contract_complete",
  contracts = contracts,
  comparisons = comparisons,
  version_only_al_rhs_reuse_supported = all(unlist(comparisons[c(
    "cran_110_vs_111_static_beta_prior_identical",
    "cran_110_vs_111_public_al_prefix_identical",
    "cran_110_vs_111_static_al_solver_identical"
  )])),
  old_custom_fits_may_be_relabelled_as_cran = FALSE
)

dir.create(dirname(args[[5L]]), recursive = TRUE, showWarnings = FALSE)
cat(
  jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
  "\n",
  file = args[[5L]],
  sep = ""
)
