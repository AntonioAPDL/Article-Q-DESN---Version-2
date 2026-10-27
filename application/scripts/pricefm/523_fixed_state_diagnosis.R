#!/usr/bin/env Rscript
# Prepared evaluator. The Python coordinator must validate explicit root funding,
# manifest/source/runtime/target pins and CPU affinity before invoking this script.
# No model fit, optimizer continuation, pass-flag overlay, or registry write exists.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 4L)
root <- normalizePath(args[[1L]], mustWork = TRUE)
manifest_path <- normalizePath(args[[2L]], mustWork = TRUE)
target_name <- args[[3L]]; out <- args[[4L]]
stopifnot(!file.exists(out), identical(Sys.getenv('R154_FIXED_STATE_ROOT_ADMITTED'), '1'))
hash <- function(p) digest::digest(p, file = TRUE, algo = 'sha256')
grant_path <- Sys.getenv('R154_FIXED_STATE_GRANT')
stopifnot(nzchar(grant_path), file.exists(grant_path),
  identical(hash(grant_path), Sys.getenv('R154_FIXED_STATE_GRANT_SHA256')))
grant <- jsonlite::read_json(grant_path, simplifyVector = TRUE)
stopifnot(identical(grant$status, 'ROOT_ADMITTED_FIXED_STATE_EXPANSION_ONLY'),
  identical(grant$target, target_name), target_name %in% c('iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75', 'iq_AT_r134_7a422c0c3473f81f_t1.632090846764e-03_s1_al0.50'),
  identical(grant$manifest_sha256, hash(manifest_path)),
  identical(grant$authorizes_fixed_state_reconstruction, TRUE),
  identical(grant$authorizes_posterior_fits, FALSE),
  identical(grant$authorizes_production_acceptance, FALSE),
  grant$maximum_CPU_seconds > 0, grant$maximum_CPU_seconds <= 800,
  grant$maximum_total_diagnostic_CPU_seconds == 2700,
  grant$reserved_source_preparation_CPU_seconds == 300,
  grant$reserved_fixed_reference_CPU_seconds == 100,
  grant$prior_charged_CPU_seconds == 995.588691,
  grant$maximum_wall_seconds > 0, grant$maximum_wall_seconds <= 7200,
  grant$cores == 1L, length(grant$affinity) == 1L,
  grant$memory_GiB > 0, grant$memory_GiB <= 8,
  grant$disk_GiB > 0, grant$disk_GiB <= 2)
stopifnot(Sys.time() < as.POSIXct(substr(grant$expires_UTC, 1L, 19L),
  format = '%Y-%m-%dT%H:%M:%S', tz = 'UTC'))
stopifnot(identical(sub('\\..*', '', grant$host), sub('\\..*', '', Sys.info()[['nodename']])) )
cpu_line <- readLines('/proc/self/status')
cpu_line <- cpu_line[startsWith(cpu_line, 'Cpus_allowed_list:')]
stopifnot(identical(trimws(sub('Cpus_allowed_list:', '', cpu_line)), as.character(grant$affinity)))
stopifnot(identical(grant$permit_id, 'muscat_cpu30'), identical(as.integer(grant$affinity), 30L),
  identical(hash(grant$global_contract$path), grant$global_contract$sha256))
global <- jsonlite::read_json(grant$global_contract$path, simplifyVector = TRUE)
stopifnot(global$max_new_numerical == 1L, nrow(global$permits) == 1L,
  identical(global$permits$id[[1L]], grant$permit_id), global$permits$cpu[[1L]] == 30L)
lock_fd <- Sys.getenv('R154_GLOBAL_PERMIT_LOCK_FD')
stopifnot(grepl('^[0-9]+$', lock_fd),
  identical(Sys.readlink(file.path('/proc/self/fd', lock_fd)),
    file.path(global$lock_dir, paste0(grant$permit_id, '.lock'))))
for (row in seq_len(nrow(grant$source_bindings)))
  stopifnot(identical(hash(grant$source_bindings$path[[row]]), grant$source_bindings$sha256[[row]]))
stopifnot(all(Sys.getenv(c('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
  'BLIS_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS', 'NUMEXPR_NUM_THREADS')) == '1'))
manifest <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
stopifnot(grant$maximum_CPU_seconds <= manifest$budget$target_CPU_ceilings[[target_name]])
target <- Filter(function(x) identical(x$name, target_name), manifest$targets)
stopifnot(length(target) == 1L); target <- target[[1L]]; c <- target$contract
stopifnot(identical(hash(manifest$source_manifest$path), manifest$source_manifest$sha256))
execution <- manifest$execution[[target_name]]
resolve <- function(p) { if (!is.null(execution$aliases[[p]])) execution$aliases[[p]] else p }
original_contract <- c
for (key in c('design_dir', 'output_dir', 'parent_dir', 'cran_adapter', 'cran_manifest', 'fixedpoint_helper'))
  c[[key]] <- resolve(c[[key]])
for (item in target$bindings) stopifnot(identical(hash(resolve(item$path)), item$sha256))
source(c$fixedpoint_helper)
source(file.path(root, 'application/R/522_certificate_reference.R'))
ns <- r129_namespace(c$cran_library)
read_f64 <- function(path, n) {
  stopifnot(file.info(path)$size == n * 8)
  con <- file(path, 'rb'); on.exit(close(con))
  x <- readBin(con, double(), n, size = 8L, endian = 'little')
  stopifnot(length(x) == n, all(is.finite(x))); x
}
design <- jsonlite::read_json(file.path(c$design_dir, 'design.json'), simplifyVector = TRUE)
dt <- jsonlite::read_json(file.path(c$design_dir, 'terminal.json'), simplifyVector = TRUE)
for (name in names(dt$files)) stopifnot(identical(hash(file.path(c$design_dir, name)), dt$files[[name]]))
stopifnot(design$n == target$n, design$p == target$p)
started <- proc.time()
X <- matrix(read_f64(file.path(c$design_dir, 'X.bin'), design$n * design$p), design$n, byrow = TRUE)
y <- read_f64(file.path(c$design_dir, 'y.bin'), design$n)
m <- read_f64(file.path(c$output_dir, 'beta_mean.bin'), design$p)
V <- matrix(read_f64(file.path(c$output_dir, 'beta_cov.bin'), design$p^2), design$p, byrow = TRUE)
terminal <- jsonlite::read_json(file.path(c$output_dir, 'terminal.json'), simplifyVector = TRUE)
stored <- jsonlite::read_json(file.path(c$output_dir, 'fixedpoint_certificate.json'), simplifyVector = TRUE)
# The unchanged source recipe is reconstructed once; its absent intermediate
# vectors cannot be labeled bitwise original optimizer state or exact resume.
recipe <- r129_certificate(ns, X, y, m, V, terminal$sigma, c$tau, c$tau0,
  limits = unlist(c$certificate_limits), max_rhs_iter = c$max_rhs_iter)
prior <- r129_prior(ns, length(m), c$tau0)
Vs <- .5 * (V + t(V))
reference <- r522_elbo_reference(prior, recipe$reconstructed_rhs_state,
  m, Vs, terminal$sigma, y, X, c$tau)
current <- r129_elbo(ns, prior, recipe$reconstructed_rhs_state, m, Vs, terminal$sigma, y, X, c$tau)
P <- crossprod(X * sqrt((current$kappa / current$B) * current$ell)) +
  diag(prior$beta_system_vb(recipe$reconstructed_rhs_state)$prec_diag, length(m))
b <- (current$kappa / current$B) *
  (crossprod(X, current$ell * y) - current$A * colSums(X))
gaussian <- r522_gaussian_reference(P, as.numeric(b))
# Compare original-unit output; do not accept a different coordinate residual.
original_U <- chol(P)
original_solved <- as.numeric(backsolve(original_U, forwardsolve(t(original_U), b)))
new_V <- chol2inv(original_U)
new_b <- 1 + sum(current$nu) + sum(current$ell * current$second -
  2 * current$A * current$residual + current$A^2 * current$nu) / (2 * current$B)
rhs_next <- prior$update_vb(recipe$reconstructed_rhs_state, list(m = original_solved, V = new_V))
next_reference <- r522_elbo_reference(prior, rhs_next, original_solved, new_V,
  new_b / (current$a - 1), y, X, c$tau)
gaussian$beta_delta_vs_original_triangular_rms <- sqrt(mean((gaussian$beta - original_solved)^2))
gaussian$predictor_delta_vs_original_triangular_rms <- sqrt(mean(as.numeric(X %*%
  (gaussian$beta - original_solved))^2))
gaussian[c('beta', 'covariance', 'diagonal_scale')] <- NULL
measure_names <- names(stored$measures)
measure_differences <- setNames(lapply(measure_names, function(k)
  recipe$measures[[k]] - stored$measures[[k]]), measure_names)
elapsed <- proc.time() - started
keep <- c('measures', 'limits', 'rhs_reconstruction', 'raw_reconstructed_elbo',
  'raw_next_elbo', 'precision_condition', 'mean_solve_relative_residual',
  'inverse_mean_relative_residual', 'inverse_vs_solve_max_beta')
result <- list(record_kind = 'diagnostic_only_no_production_acceptance_authority',
  target = target_name, manifest_sha256 = hash(manifest_path),
  original_contract_sha256 = hash(resolve(target$bindings[[1L]]$path)),
  original_certificate_sha256 = hash(file.path(c$output_dir, 'fixedpoint_certificate.json')),
  original_host = target$host, execution_host = Sys.info()[['nodename']],
  original_source_manifest_sha256 = manifest$source_manifest$sha256,
  cross_host_alias_applied = !identical(sub('\\..*', '', target$host), sub('\\..*', '', Sys.info()[['nodename']])),
  state_kind = 'source_equivalent_fixed_state_not_optimizer_resume',
  original_intermediate_vectors_retained = FALSE,
  bitwise_original_intermediate_state_recovered = FALSE,
  original_recipe_measurements = within(recipe[keep], limits <- as.list(limits)),
  differences_from_stored_measures = measure_differences,
  raw_objective_differences_from_stored = list(
    current = recipe$raw_reconstructed_elbo - stored$raw_reconstructed_elbo,
    next_value = recipe$raw_next_elbo - stored$raw_next_elbo),
  original_RHS_iteration_counts = stored$rhs_reconstruction,
  half_order_reference = within(reference, terms <- as.list(terms)),
  half_order_next_reference = within(next_reference, terms <- as.list(terms)),
  original_vs_half_order_current_objective = reference$objective - current$elbo,
  original_vs_half_order_next_objective = next_reference$objective - recipe$raw_next_elbo,
  reference_objective_relative_change_diagnostic_only =
    abs(next_reference$objective - reference$objective) / max(1, abs(reference$objective)),
  gaussian_reference = gaussian,
  numerical_cause_established = FALSE, optimizer_updates = 0L, posterior_fits = 0L,
  production_certificates_written = 0L, production_passflags_written = 0L,
  process_CPU_seconds = unname(elapsed[['user.self']] + elapsed[['sys.self']]),
  elapsed_wall_seconds = unname(elapsed[['elapsed']]))
encoded <- jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = 'null')
con <- file(out, open = 'wx'); on.exit(close(con)); writeLines(encoded, con)
cat('Fixed-state diagnosis recorded; no production authority\n')
