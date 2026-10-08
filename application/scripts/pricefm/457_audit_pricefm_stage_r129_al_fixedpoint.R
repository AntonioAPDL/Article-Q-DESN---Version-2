#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
at <- match('--config', args); stopifnot(!is.na(at), at < length(args))
config <- normalizePath(args[[at + 1L]], mustWork = TRUE)
c <- jsonlite::read_json(config, simplifyVector = TRUE)
hash <- function(path) digest::digest(path, file = TRUE, algo = 'sha256')
stopifnot(identical(c$stage, 'R129'), identical(c$action, 'saved_median_certificate'),
  identical(c$test_opened, FALSE), !dir.exists(c$output_dir))
for (name in names(c$input_sha256)) stopifnot(identical(hash(name), c$input_sha256[[name]]))
stopifnot(identical(hash(c$helper), c$helper_sha256))
source(c$helper)
ns <- r129_namespace(c$cran_library)
d <- jsonlite::read_json(file.path(c$design_dir, 'design.json'), simplifyVector = TRUE)
design_terminal <- jsonlite::read_json(file.path(c$design_dir, 'terminal.json'), simplifyVector = TRUE)
for (name in names(design_terminal$files)) {
  stopifnot(identical(hash(file.path(c$design_dir, name)), design_terminal$files[[name]]))
}
stopifnot(!any(startsWith(d$feature_names, 'input::')))
t <- jsonlite::read_json(file.path(c$parent_dir, 'terminal.json'), simplifyVector = TRUE)
stopifnot(isTRUE(t$finite_core), t$tau == .5, t$tau0 == c$tau0,
  d$p == t$p, d$n == t$n, identical(t$posterior_target_sha256, c$posterior_target_sha256))
read_bin <- function(path, size) {
  con <- file(path, 'rb'); on.exit(close(con))
  v <- readBin(con, double(), size, size = 8, endian = 'little')
  stopifnot(length(v) == size, all(is.finite(v))); v
}
X <- matrix(read_bin(file.path(c$design_dir, 'X.bin'), d$n * d$p), d$n, byrow = TRUE)
y <- read_bin(file.path(c$design_dir, 'y.bin'), d$n)
m <- read_bin(file.path(c$parent_dir, 'beta_mean.bin'), d$p)
V <- matrix(read_bin(file.path(c$parent_dir, 'beta_cov.bin'), d$p * d$p), d$p, byrow = TRUE)
started <- proc.time()[['elapsed']]
result <- r129_certificate(ns, X, y, m, V, t$sigma, .5, c$tau0,
  limits = c$limits, max_rhs_iter = c$max_rhs_iter)
dir.create(c$output_dir, recursive = TRUE)
saveRDS(result[c('reconstructed_rhs_state', 'likelihood_scale_state', 'latent_state')],
  file.path(c$output_dir, 'reconstructed_variational_state.rds'), compress = 'xz')
result[c('reconstructed_rhs_state', 'latent_state', 'beta_covariance', 'prior_center')] <- NULL
result$original_formal_converged <- isTRUE(t$formal_converged)
result$original_iterations <- t$iterations
result$posterior_target_sha256 <- t$posterior_target_sha256
result$elapsed_seconds <- proc.time()[['elapsed']] - started
result$test_opened <- FALSE
result$no_model_fit_performed <- TRUE
result$source_config_sha256 <- hash(config)
jsonlite::write_json(result, file.path(c$output_dir, 'certificate.json'), auto_unbox = TRUE,
  pretty = TRUE, digits = 17, null = 'null')
cat(jsonlite::toJSON(result, auto_unbox = TRUE, null = 'null'), '\n')
