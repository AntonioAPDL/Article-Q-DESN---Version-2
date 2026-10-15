#!/usr/bin/env Rscript
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), "../.."))
source(file.path(root, "application/R/independent_forecast_calibration_v1.R"))
checks <- 0L; mutations <- 0L
check <- function(ok) { stopifnot(isTRUE(ok)); checks <<- checks + 1L }
reject <- function(expr) {
  failed <- inherits(tryCatch({ force(expr); NULL }, error = identity), "error")
  check(failed); mutations <<- mutations + 1L
}
grid <- ifc_grid()
check(nrow(grid) == 1000L && grid$target[1L] == 9001L && grid$target[1000L] == 10000L)
check(length(unique(grid$origin[1:300])) == 10L && length(unique(grid$origin[1:500])) == 17L &&
  grid$lead[500] == 20L && grid$lead[1000] == 10L)
spec <- data.frame(family = "normal", tau = .25, model_variant = "qdesn_al_rhs_ns", replay_id = "fixture")
locator <- data.frame(n_draws = 5L, chain_id = 1L, task_id = "fixture__c01")
fixture <- function(chain = 1L) list(schema = "independent_joint_quantile_forecast_paths_v1",
  q = matrix(rep(seq_len(1000L), 5L), 1000L, 5L), grid = grid,
  y = as.numeric(seq_len(1000L)), oracle = as.numeric(seq_len(1000L)) - 1,
  p = .25, chain_id = chain, source_draw_index = 101:105,
  reconstruction_id = sprintf("fixture__c%02d", chain), coupling = "native_shared_readout_draws")
x <- fixture(); check(isTRUE(ifc_validate_paths(x, spec, locator)))
point <- ifc_pool_point(lapply(1:3, fixture))
check(all(point == seq_len(1000L)))
z <- ifc_frequency(point, x$y, .25, grid, 300L)
check(z$n_hits == 300L && z$empirical_frequency == 1 && z$calibration_error_pp == 75)
z <- ifc_frequency(point - .5, x$y, .25, grid, 500L)
check(z$n_hits == 0L && z$n_origins == 17L && z$n_targets == 500L)
mixed <- rep(c(-1, 0), 500L) + x$y
check(ifc_frequency(mixed, x$y, .25, grid, 300L)$n_hits == 150L)
check(identical(ifc_frequency(2 * mixed + 7, 2 * x$y + 7, .25, grid, 500L),
  ifc_frequency(mixed, x$y, .25, grid, 500L)))
# Pooling medians differs from averaging chain medians; chain budgets are equal.
counterexample <- lapply(1:3, fixture)
for (i in 1:3) counterexample[[i]]$q[,] <- c(0, 0, 100)[i]
check(all(ifc_pool_point(counterexample) == 0))
check(mean(vapply(counterexample, function(y) median(y$q), numeric(1))) > 0)
prefix <- lapply(lapply(1:3, fixture), function(z) { z$q <- z$q[1:500, , drop = FALSE]; z })
check(identical(ifc_pool_point(prefix)[1:300], point[1:300]))
mutate_path <- function(fun) { bad <- fun(fixture()); reject(ifc_validate_paths(bad, spec, locator)) }
mutate_path(function(z) { z$q[1, 1] <- NA_real_; z })
mutate_path(function(z) { z$q <- z$q[, -1, drop = FALSE]; z })
mutate_path(function(z) { z$q <- z$q[-1, , drop = FALSE]; z })
mutate_path(function(z) { z$grid$target[2] <- z$grid$target[1]; z })
mutate_path(function(z) { z$grid$origin[1] <- 8999L; z })
mutate_path(function(z) { z$grid$lead[500] <- 30L; z })
mutate_path(function(z) { z$schema <- "other"; z })
mutate_path(function(z) { z$p <- .05; z })
mutate_path(function(z) { z$chain_id <- 2L; z })
mutate_path(function(z) { z$reconstruction_id <- "other"; z })
mutate_path(function(z) { z$coupling <- "historical_latent_gaussian_product_coupling"; z })
mutate_path(function(z) { z$source_draw_index[1] <- 0L; z })
mutate_path(function(z) { z$source_draw_index[1] <- z$source_draw_index[2]; z })
mutate_path(function(z) { z$source_draw_index[1] <- Inf; z })
mutate_path(function(z) { z$y[1] <- Inf; z })
mutate_path(function(z) { z$oracle <- z$oracle[-1]; z })
bad <- lapply(1:3, fixture); bad[[2]]$y[1] <- 99
reject(ifc_pool_point(bad))
bad <- lapply(1:3, fixture); bad[[2]]$oracle[1] <- 99
reject(ifc_pool_point(bad))
bad <- lapply(1:3, fixture); bad[[2]]$chain_id <- 1L
reject(ifc_pool_point(bad))
bad <- lapply(1:3, fixture); bad[[2]]$q <- bad[[2]]$q[, -1, drop = FALSE]
reject(ifc_pool_point(bad))
reject(ifc_frequency(point, x$y, .25, grid, 1000L))
summary <- expand.grid(family = c("normal", "laplace", "gausmix"), tau = c(.05, .25, .5),
  model_variant = c("dqlm", "exdqlm", "qdesn_al_rhs_ns", "qdesn_exal_rhs_ns"),
  cutoff = c(300L, 500L), stringsAsFactors = FALSE)
summary$replay_id <- paste0("source_", match(ifc_key(summary), unique(ifc_key(summary))))
summary$inference <- "mcmc"; summary$metric_role <- "forecast_check"
summary$n_draws <- 30L; summary$n_chains <- 3L
check(nrow(ifc_select_specs(summary)) == 36L)
bad <- summary; bad$replay_id[bad$cutoff == 500L][1L] <- "different"
reject(ifc_select_specs(bad))
bad <- summary; bad$n_draws[bad$cutoff == 500L][1L] <- 33L
reject(ifc_select_specs(bad))
reject(ifc_select_specs(summary[-1L, ]))
check(ifc_policy(file.path(root, "application/config/independent_forecast_calibration_v1.json"))$point_summary == "posterior_median")
# Exercise the authenticated reader with a wholly synthetic receipt packet.
# No fitted posterior, production worker, or retained scientific runtime is read.
synthetic <- tempfile("ifc_synthetic_receipt_")
dir.create(synthetic)
payload <- file.path(synthetic, "protected_joint_forecast_paths.rds")
saveRDS(fixture(), payload)
contract_path <- file.path(synthetic, "contract.json")
jsonlite::write_json(list(task = list(task_id = locator$task_id, replay_id = spec$replay_id,
  chain_id = 1L, n_draws = 5L, model_variant = spec$model_variant,
  family = spec$family, p = spec$tau)), contract_path, auto_unbox = TRUE)
manifest_path <- file.path(synthetic, "retention_manifest.csv")
write.csv(data.frame(path = payload, sha256 = ifc_sha(payload), bytes = file.info(payload)$size),
  manifest_path, row.names = FALSE)
status_path <- file.path(synthetic, "task_status.json")
status <- list(status = "COMPLETE", task_id = locator$task_id,
  contract_sha256 = ifc_sha(contract_path), retention_manifest_sha256 = ifc_sha(manifest_path))
jsonlite::write_json(status, status_path, auto_unbox = TRUE)
local_locator <- cbind(locator, data.frame(job_root = synthetic, contract_path = contract_path,
  contract_sha256 = ifc_sha(contract_path)))
pin_paths <- c(payload, status_path, manifest_path)
pins <- data.frame(path = pin_paths, sha256 = vapply(pin_paths, ifc_sha, character(1)),
  bytes = file.info(pin_paths)$size)
authenticated <- ifc_read_chain(local_locator, spec, pins)
check(nrow(authenticated$object$q) == 500L && authenticated$receipt$payload_sha256 == ifc_sha(payload))
check(!any(grepl(synthetic, unlist(authenticated$receipt), fixed = TRUE)))
reject(ifc_verify_file(payload, paste(rep("0", 64), collapse = "")))
reject(ifc_verify_file(payload, ifc_sha(payload), file.info(payload)$size + 1))
status$status <- "RUNNING"
jsonlite::write_json(status, status_path, auto_unbox = TRUE)
reject(ifc_read_chain(local_locator, spec, pins))
status$status <- "COMPLETE"; status$contract_sha256 <- paste(rep("0", 64), collapse = "")
jsonlite::write_json(status, status_path, auto_unbox = TRUE)
reject(ifc_read_chain(local_locator, spec, pins))
status$contract_sha256 <- ifc_sha(contract_path)
status$retention_manifest_sha256 <- paste(rep("0", 64), collapse = "")
jsonlite::write_json(status, status_path, auto_unbox = TRUE)
reject(ifc_read_chain(local_locator, spec, pins))
reject(ifc_verify_pin(payload, pins[pins$path != payload, ]))
bad_pins <- pins; bad_pins$sha256[bad_pins$path == payload] <- paste(rep("0", 64), collapse = "")
reject(ifc_verify_pin(payload, bad_pins))
check(!ifc_verify_pin(file.path(synthetic, "unrecorded_status.json"), pins, required = FALSE))
cat(sprintf("PASS: %d calibration checks, including %d expected mutation rejections; no runtime evidence loaded.\n", checks, mutations))
