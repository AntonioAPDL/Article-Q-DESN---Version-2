# Generated qualification only; no retained object or authentic callback reads.
local({
  source("scripts/diagnostics/glofas_al_path_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_fixed_target_scalar_diagnostics.R", local = TRUE)
  source("scripts/diagnostics/glofas_fixed_target_smoothing_reference.R", local = TRUE)
  fixture <- function(p = .5, H = 1L, M = 51L, nonlinear = FALSE) {
    contract <- list(mode = "generated", likelihood_family = "al", p = p, sigma_y = .07, sigma_g = .05,
      issued = matrix(-.1,H,M), member_weights = matrix(1,H,M),
      forecast_dates = as.Date("2000-01-01") + seq_len(H), origin_date = as.Date("2000-01-01"),
      known_baseline = rep(0,H), parameter_id = paste("fixed",p,H,M,nonlinear),
      feature_id = paste("generated",H,nonlinear), coefficient_covariance = matrix(0,2,2),
      truth_access = "forbidden", max_callback_calls = 1000000L,
      max_jacobian_calls = 5000L,
      ensemble_location_convention = "total_reference_plus_discrepancy_plus_known_baseline")
    value <- function(y) {
      r <- g <- numeric(H)
      if(H==2L) {
        r[2] <- if(nonlinear) .1*tanh(y[1]) else 0
        g[2] <- if(nonlinear) .15*tanh(y[1]) else .05*y[1]
      }
      list(reference_location=r,ensemble_location=g)
    }
    jacobian <- function(y) {
      out <- value(y);JR <- JG <- matrix(0,H,H)
      if(H==2L) {
        JR[2,1] <- if(nonlinear) .1*(1-tanh(y[1])^2) else 0
        JG[2,1] <- if(nonlinear) .15*(1-tanh(y[1])^2) else .05
      }
      c(out,list(reference_jacobian=JR,ensemble_jacobian=JG))
    }
    list(target=gapr_new_target(value,contract),jacobian=jacobian,contract=contract,value=value)
  }
  engine <- app_gftd_scalar_production_namespace(".")
  # Independent scalar CDF and normalized AL density, including every member
  # normalization constant. Current members do not inform the current Y.
  for(p in c(.05,.5)) {
    x <- fixture(p)
    ref <- gapr_one_dimensional_reference(function(y)gapr_log_target(x$target,y))
    exact <- vapply(ref$quantiles,function(q)app_gftd_scalar_al_cdf(q,p,0,.07),numeric(1L))
    stopifnot(max(abs(exact-ref$probabilities))<1e-8,
      ref$estimated_normalization_error<1e-8,ref$normalization_tightening<1e-8,
      ref$quantile_tightening<1e-8)
    y <- .13;parts <- gapr_log_target(x$target,y,TRUE)
    expected_y <- log(p*(1-p)/.07)-(y*(p-(y<0)))/.07
    expected_g <- sum(vapply(rep(-.1,51),function(g)
      log(p*(1-p)/.05)-g*(p-(g<0))/.05,numeric(1L)))
    stopifnot(abs(parts$value-expected_y-expected_g)<1e-10,
              length(parts$future_y)==1L,identical(dim(parts$members),c(1L,51L)))
  }
  # Existing independently integrated and closed-form two-step reference.
  for(M in c(1L,51L)) {
    x <- fixture(H=2L,M=M)
    ref <- gapr_one_dimensional_reference(function(y)gapr_log_target(x$target,c(y,0)),
                                           split_points=c(-2,0))
    previous <- gftsr_contract(M)
    stopifnot(max(abs(gftsr_piecewise_cdf(ref$quantiles,previous)-ref$probabilities))<1e-8,
              ref$quantile_tightening<1e-8)
    vb <- gapr_matched_fixed_vb(x$target,x$jacobian,engine,c(0,0),diag(.02,2),
                                max_iterations=1000L,tolerance=1e-10)
    original <- gftsr_actual_mean_field(previous,engine)
    stopifnot(vb$status=="FIXED_PARAMETER_VB_STABILIZED",
              max(abs(vb$mean-original$mean))<1e-7,
              max(abs(vb$covariance-original$covariance))<1e-7,
              identical(vb$comparison_type,"matched_fixed_parameter_VB_not_original_full_qF"))
  }
  # A genuinely nonlinear map; Y2's normalized conditional density integrates
  # to one. Evaluating it at its own location only removes a constant density
  # value, not a Jacobian or a transformation of the joint posterior.
  x <- fixture(H=2L,nonlinear=TRUE)
  profile <- function(y)gapr_log_target(x$target,c(y,.1*tanh(y)))
  ref <- gapr_one_dimensional_reference(profile,split_points=c(atanh(-2/3),0))
  independent_kernel <- function(y) {
    -abs(y)/(.14)-51*abs(-.1-.15*tanh(y))/.1
  }
  independent <- gapr_one_dimensional_reference(independent_kernel,
    split_points=c(atanh(-2/3),0))
  stopifnot(max(abs(ref$quantiles-independent$quantiles))<1e-8,
            ref$quantile_tightening<1e-8)

  # Explicit guards prevent accidental weights, support, dates, likelihood or
  # original-full-qF uncertainty changes in this fixed-parameter diagnostic.
  good <- fixture()
  # The callback already supplies TOTAL G location. A known baseline is not
  # added again by the kernel, and cannot disappear through a d-versus-r+d mixup.
  baseline_contract <- good$contract;baseline_contract$known_baseline<- .3
  baseline_callback <- function(y)list(reference_location=0,ensemble_location=.3)
  baseline_target <- gapr_new_target(baseline_callback,baseline_contract)
  expected <- log(.25/.07)+51*(log(.25/.05)-.4*.5/.05)
  stopifnot(abs(gapr_log_target(baseline_target,0)-expected)<1e-10)
  bad <- good$contract;bad$member_weights[1,1]<-1/51
  stopifnot(inherits(try(gapr_new_target(good$value,bad),silent=TRUE),"try-error"))
  bad <- good$contract;bad$coefficient_covariance[1,1]<-.01
  stopifnot(inherits(try(gapr_new_target(good$value,bad),silent=TRUE),"try-error"))
  bad <- good$contract;bad$forecast_dates<-bad$forecast_dates+1
  stopifnot(inherits(try(gapr_new_target(good$value,bad),silent=TRUE),"try-error"))
  bad <- good$contract;bad$truth_access<-"scoring"
  stopifnot(inherits(try(gapr_new_target(good$value,bad),silent=TRUE),"try-error"))
  bad <- good$contract;bad$mode<-"authentic"
  stopifnot(inherits(try(gapr_new_target(good$value,bad),silent=TRUE),"try-error"))
  bad <- good$contract;bad$likelihood_family<-"exal"
  stopifnot(inherits(try(gapr_new_target(good$value,bad),silent=TRUE),"try-error"))
  stopifnot(inherits(try(gapr_log_target(good$target,c(0,1)),silent=TRUE),"try-error"))
  bad_jacobian <- function(y)c(good$value(y),list(reference_jacobian=matrix(1,1,1),
                                                  ensemble_jacobian=matrix(0,1,1)))
  stopifnot(inherits(try(gapr_locations(good$target,0,bad_jacobian),silent=TRUE),"try-error"))

  dependency <- gapr_posterior_dependency()
  if(dependency$available) {
    x <- fixture(.5)
    control <- list(warmup=400L,samples=2000L,max_evaluations=20000L,max_wall_seconds=60,
      adapt_warmup=TRUE,rhat_max=1.01,min_ess=400,max_quantile_mcse=.02,
      proposal_kind="blocked_preconditioned")
    starts <- matrix(c(-.3,-.1,.1,.3),1L,4L)
    sampled <- gapr_sample_reference(x$target,starts,control=control,
                                      proposal_covariance=matrix(.04,1,1))
    stopifnot(sampled$scientific_runs==0L,sampled$authentic_reads==0L,
              sampled$full_parameter_refits==0L,
              sampled$conditional_reference_chains_requested==4L,
              sampled$conditional_reference_chains_attempted==4L,
              sampled$conditional_reference_chains_completed==4L,
              sampled$callback_evaluations==4L*(1L+control$warmup+control$samples),
              all(is.finite(sampled$draws)),!grepl("FAIL_",sampled$status),
              identical(names(sampled$seeds),paste0("chain",1:4)),
              sampled$adaptation=="warmup_only_then_frozen_symmetric_MH_proposal")
    vb <- gapr_matched_fixed_vb(x$target,x$jacobian,engine,0,matrix(.02,1,1))
    stopifnot(vb$conditional_future_path_vb_optimizations==1L,vb$full_parameter_refits==0L)
    compare <- gapr_compare_matched_vb(sampled,vb)
    if(sampled$qualified) {
      stopifnot(compare$status=="MATCHED_CONDITIONAL_COMPARISON",
        all(abs(compare$comparison$reference_quantile)<
              6*compare$comparison$mcse_quantile+.005))
      unfinished <- vb;unfinished$status<-"INCONCLUSIVE_ITERATION_LIMIT"
      stopifnot(gapr_compare_matched_vb(sampled,unfinished)$status=="INCONCLUSIVE_VB_UNQUALIFIED")
      repaired <- vb;repaired$repaired<-TRUE
      stopifnot(gapr_compare_matched_vb(sampled,repaired)$status=="INCONCLUSIVE_VB_UNQUALIFIED")
    } else stopifnot(compare$status=="INCONCLUSIVE_REFERENCE_UNQUALIFIED")
    wrong <- vb;wrong$condition$parameter_id<-"different_parameter_point"
    stopifnot(inherits(try(gapr_compare_matched_vb(sampled,wrong),silent=TRUE),"try-error"))
    wrong <- vb;wrong$comparison_type<-"original_full_qF"
    stopifnot(inherits(try(gapr_compare_matched_vb(sampled,wrong),silent=TRUE),"try-error"))
    # A tiny hard budget must remain visibly inconclusive, never autoextend.
    tiny <- control;tiny$max_evaluations<-2L
    stopped <- gapr_sample_reference(fixture()$target,starts,control=tiny,
                                      proposal_covariance=matrix(.04,1,1))
    stopifnot(stopped$status=="INCONCLUSIVE_BUDGET_LIMITED",!stopped$qualified,
              stopped$callback_evaluations==2L)
    # Named chains may be run separately under a separate native admission;
    # combining requires all four exactly once and the identical target.
    split_control <- control;split_control$warmup<-100L;split_control$samples<-200L
    parts <- lapply(1:4,function(chain) {
      local_control<-split_control;local_control$chain_ids<-chain
      gapr_sample_reference(fixture()$target,starts,control=local_control,
                             proposal_covariance=matrix(.04,1,1))
    })
    joined <- gapr_combine_chains(parts,fixture()$target,split_control)
    stopifnot(all(is.finite(joined$draws)),!grepl("FAIL_",joined$status),
      inherits(try(gapr_combine_chains(parts[c(1,1,3,4)],fixture()$target,split_control),
                   silent=TRUE),"try-error"))
    changed <- parts;changed[[2L]]$control$warmup<-101L
    stopifnot(inherits(try(gapr_combine_chains(changed,fixture()$target,split_control),
                            silent=TRUE),"try-error"))
    changed <- parts;changed[[2L]]$seeds[[1L]]<-1L
    stopifnot(inherits(try(gapr_combine_chains(changed,fixture()$target,split_control),
                            silent=TRUE),"try-error"))
    message("Conditional MCMC generated benchmark status: ",sampled$status,
            "; finite-chain reference, not exact draws/full-posterior inference.")
  } else {
    message("Conditional MCMC NOT RUN: ",dependency$status,
            "; deterministic exact-density/quadrature and contract guards ran.")
  }
  message("GloFAS AL path reference: generated scalar/two-step/nonlinear references and matched-condition guards passed.")
})
