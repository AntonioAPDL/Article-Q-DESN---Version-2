local({
  source("scripts/diagnostics/glofas_native_prior_contract.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(x) ok(inherits(try(force(x), silent = TRUE), "try-error"))
  target <- paste(rep("7", 64L), collapse = "")
  prior <- paste(rep("8", 64L), collapse = "")
  cfg <- list(task_id = "gft-al-p050", posterior_target_sha256 = target,
    prior_sha256 = prior, vb_args = list(
      beta_rhs = list(tau0 = 5.2043087e-5, slab_s2 = 7, a_zeta = 2,
        b_zeta = 4, intercept_prec = 1e-9),
      alpha_rhs = list(tau0 = .0001159, slab_s2 = 9),
      beta_ridge = list(precision = 3), prior_sigma = list(a = 2, b = 1)))
  out <- gnpc_extract_config(cfg)
  ok(out$schema_version == "glofas_native_prior_export_v1")
  ok(out$effective_prior$beta$tau0 == 5.2043087e-5)
  ok(out$effective_prior$alpha$tau0 == .0001159)
  ok(out$effective_prior$alpha$slab$a_zeta == 2 &&
    out$effective_prior$alpha$slab$b_zeta == 4)
  ok(out$effective_prior$beta$slab$learned &&
    out$effective_prior$beta$slab$slab_s2_initial == 7)
  ok(out$effective_prior$beta$slab$slab_s2_role ==
    "variational_state_initializer_not_prior_hyperparameter")
  ok(identical(out$effective_prior$source_scale$Y, c(shape = 2, rate = 1)) &&
    identical(out$effective_prior$source_scale$G, c(shape = 2, rate = 1)))
  ok(out$effective_prior$ridge$precision == 3 &&
    !out$effective_prior$ridge$used_by_native_AL_target)
  ok(is.null(out$raw_protected_tuple$alpha_rhs$a_zeta))
  ok(!out$model_run_authorized && !out$native_application_qualified)
  fixed <- cfg
  fixed$vb_args$beta_rhs$zeta2_fixed <- 4
  fixed_out <- gnpc_extract_config(fixed)
  ok(!fixed_out$effective_prior$beta$slab$learned &&
    fixed_out$effective_prior$beta$slab$slab_s2_role == "ignored_by_fixed_slab_prior")
  alias <- cfg
  alias$vb_args$beta_rhs$slab_s2 <- NULL
  alias$vb_args$beta_rhs$s2 <- 4
  ok(gnpc_extract_config(alias)$effective_prior$beta$slab$slab_s2_initial == 4)
  defaults <- list(task_id = "gft-al-p050", vb_args = list())
  d <- gnpc_extract_config(defaults)
  ok(d$effective_prior$beta$tau0 == 1 && d$effective_prior$alpha$tau0 == 1)
  ok(d$effective_prior$beta$intercept_prec == 1e-9 &&
    d$effective_prior$source_scale$Y[["shape"]] == 2)
  bad <- cfg; bad$vb_args$prior_addition <- list(diagonal = 1)
  reject(gnpc_extract_config(bad))
  bad <- cfg; bad$vb_args$alpha_rhs$tau0 <- 0
  reject(gnpc_extract_config(bad))
  bad <- cfg; bad$vb_args$beta_rhs$zeta2_fixed <- -1
  reject(gnpc_extract_config(bad))
  raw <- out$raw_protected_tuple; raw$beta_rhs$slab_s2 <- 11
  ok(!identical(gnpc_hash_object(raw), out$raw_protected_tuple_sha256))
  cat(sprintf("GLOFAS_NATIVE_PRIOR_CONTRACT_PASS checks=%d original_reads=0 model_runs=0\n", n))
})
