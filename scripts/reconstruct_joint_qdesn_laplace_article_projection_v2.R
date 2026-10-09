#!/usr/bin/env Rscript
# Deterministic post-processing of frozen draws. No estimator is called here.
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1")
options(stringsAsFactors = FALSE, digits = 17)
args <- commandArgs(trailingOnly = TRUE)
option <- function(flag, default) {
  i <- match(flag, args); if (is.na(i)) return(default)
  if (i == length(args)) stop(paste("Missing value for", flag))
  args[[i + 1L]]
}
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
repo <- normalizePath(option("--repo-root", file.path(dirname(script), "..")))
setwd(repo)
source("application/R/00_packages.R")
app_set_repo_root(repo)
for (module in c(
  "input_contract", "synthesize_quantiles", "score_forecasts", "latent_path_vb_al",
  "joint_qvp_qdesn", "joint_qdesn_posterior_contract", "joint_qdesn_simulation_readiness",
  "joint_qdesn_simulation_fixtures", "joint_qdesn_simulation_validation", "joint_qdesn_mcmc_readiness",
  "latent_path_design", "joint_exqdesn_phase151_feature_design_screening",
  "glofas_normal_desn_part1_screening", "joint_exqdesn_trace_tools",
  "joint_exqdesn_phase156_collapsed_gamma_sigma", "joint_exqdesn_exact_structured_inference",
  "joint_exqdesn_inference_dispatch", "joint_qdesn_dgp_integrated_acrps",
  "joint_qdesn_shared_backbone_screening", "joint_qdesn_shared_backbone_quantile_fit",
  "joint_qdesn_shared_backbone_family_campaign", "joint_qdesn_shared_backbone_article_confirmation",
  "joint_qdesn_shared_backbone_article_score_packet", "joint_qdesn_pure_recursive_campaign",
  "joint_qdesn_recursive_mean_design", "joint_qdesn_recursive_dgp_oracle",
  "joint_qdesn_recursive_mean_score_packet")) source(app_path("application/R",paste0(module,".R")))
source("application/R/joint_qdesn_fixed_backbone_prior_screen.R")
source("application/R/joint_qdesn_laplace_quantile_architecture.R")
source("application/R/joint_qdesn_laplace_architecture_article_confirmation.R")
runtime <- normalizePath(option("--runtime-root", file.path(repo, "application/cache/joint_qdesn_laplace_architecture_article_confirmation_jerez_15core_20261008")))
cache <- option("--cache-root", file.path(repo, "local_trackers/joint_laplace_v2_postprocess"))
dir.create(cache, recursive = TRUE, showWarnings = FALSE)
cache <- normalizePath(cache)
workers <- as.integer(option("--workers", "4"))
stopifnot(workers >= 1L, workers <= 4L)
prefix <- "joint_qdesn_pure_desn_v2_"
oldprefix <- "joint_qdesn_pure_desn_v1_"
read <- function(path) read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
sha <- function(path) unname(tools::sha256sum(path)[[1L]])
expect <- function(x, why) if (!isTRUE(x)) stop(why, call. = FALSE)
old <- function(name) read(file.path(repo, "tables", paste0(oldprefix, name, ".csv")))
oldfile <- function(name) file.path(repo, "tables", paste0(oldprefix, name, ".csv"))
pins <- c(
  "closeout/article_scores.csv" = "b670b1deadd7fc056605780893b910c2480fec9f7eec9e48ee768ae112f3882b",
  "closeout/artifact_manifest.csv" = "13ea15c3b45e1cd373134b7e90bf643ccbf463bd703cff079f126ddb3f22efd3",
  "closeout/decision.csv" = "fdea5c463c14030511cae540cfc55aad119d3b9eacd0013697dd7be5e814e6ef")
for (name in names(pins)) expect(identical(sha(file.path(runtime, name)), pins[[name]]), paste("Frozen pin mismatch", name))
expect(identical(sha(oldfile("forecast_score_summary")), "a0be319e4486d5be122ad6dfe5ee9e2a470cd09ce5dfafc5d0af3925aecf2d1c"), "v1 score changed")
expect(identical(sha(oldfile("crossing_summary")), "80c929b6f94fefde8ed0a18126c538467759eca093aafae9fbef9eb33afb2e67"), "v1 crossing changed")
expect(trimws(readLines(file.path(runtime, "COMPLETE"))[1L]) == "COMPLETE_READY_FOR_INTEGRATION_REVIEW", "Frozen runtime incomplete")
manifests <- list.files(runtime, "^(artifact_manifest|component_manifest|plan_manifest|freeze_manifest)[.]csv$", recursive = TRUE, full.names = TRUE)
manifests <- manifests[!startsWith(manifests, file.path(runtime,"source_evidence/"))]
manifest_receipts <- lapply(manifests, function(path) {
  checked <- app_joint_shared_verify_manifest(dirname(path), path)
  expect(nrow(checked) > 0L && all(checked$verified), paste("Manifest mismatch", path))
  data.frame(relative_path = substring(path, nchar(runtime) + 2L), verified_payloads = nrow(checked), status = "pass")
})
manifest_receipts <- do.call(rbind, manifest_receipts)
expect(nrow(manifest_receipts) == 57L && sum(manifest_receipts$verified_payloads) == 230L, "Frozen nested manifest cardinality changed")
app_joint_laplace_article_verify_freeze(runtime)
ct <- readRDS(file.path(runtime, "contract.rds"))
context <- readRDS(file.path(runtime, "article/datasets/dataset_02/context.rds"))
oracle <- readRDS(file.path(runtime, "article/datasets/dataset_02/oracle.rds"))
d <- context$design
tau <- ct$tau; weights <- ct$weights
expect(nrow(d$forecast_map) == 990L && length(d$fit_local) == 500L && ncol(d$Z) == 24L &&
  d$response_lags == 1L && identical(tau, c(.05,.10,.25,.50,.75,.90,.95)), "Candidate geometry differs")
cells <- read(file.path(runtime, "article/cells.csv"))
chains <- read(file.path(runtime, "article/chains.csv"))
candidate <- cells[cells$dataset_id == 2L, ]
model_map <- c(independent_qdesn_rhs = "qdesn_rhs_independent_mcmc", joint_qdesn_rhs = "joint_qdesn_rhs_mcmc",
  independent_exqdesn_rhs = "exqdesn_rhs_independent_mcmc", joint_exqdesn_rhs = "joint_exqdesn_rhs_mcmc")
cell_map <- sub("_mcmc$", "", model_map)

# A vectorized evaluation of the same existing recursion, restricted to the
# authenticated candidate contract. Native three-draw checks below establish
# numerical agreement before any resulting summary can enter the projection.
path_evaluate <- function(beta, alpha, uniforms, chain_id, source_draw_index, mean_only = FALSE) {
  beta <- as.matrix(beta); alpha <- as.matrix(alpha); uniforms <- as.matrix(uniforms)
  n <- nrow(beta); K <- length(tau); p <- ncol(d$Z); r <- d$reservoir
  expect(r$D == 3L && identical(as.integer(r$n), c(8L,8L,8L)) && all(r$Q_is_identity) &&
    r$act_f == "tanh" && r$act_k == "identity" && d$response_lags == 1L,
    "Vectorized path evaluator is restricted to the frozen three-layer candidate")
  snapshots <- app_joint_recursive_origin_snapshots(d, context$fixture, context$selected)
  expected <- realized <- numeric(n); raw_cross <- contract_cross <- numeric(n)
  adjustments <- max_adjustments <- numeric(n)
  mean_design <- matrix(0, nrow(d$forecast_map), p)
  variance <- mean_design
  half_design <- list(mean_design, mean_design)
  half <- rep(c(1L,2L), length.out = n)
  for (o in seq_along(snapshots$origin_index)) {
    ids <- which(d$forecast_map$origin_index == snapshots$origin_index[[o]])
    states <- lapply(snapshots$states[[o]], function(x) matrix(rep(x, each = n), nrow = n))
    lag <- rep(context$fixture$y[[snapshots$origin_full_time_index[[o]]]], n)
    for (j in ids) {
      tt <- d$forecast_map$full_time_index[[j]]
      angle <- 2*pi*(tt-1L)/d$dgp_row$period[[1L]]
      trend <- -1+2*(tt-1L)/(d$dgp_row$simulated_length[[1L]]-1L)
      raw <- cbind(lag, trend, sin(angle), cos(angle))
      scaled <- sweep(sweep(raw, 2L, d$scale_params$center, "-"), 2L, d$scale_params$scale, "/")
      u <- cbind(rep(snapshots$reservoir_meta$win_scale_bias,n), scaled * snapshots$reservoir_meta$win_scale_global)
      next_states <- states
      next_states[[1L]] <- (1-r$alpha[[1L]])*states[[1L]] + r$alpha[[1L]]*tanh(states[[1L]] %*% t(r$W[[1L]]) + u %*% t(r$Win[[1L]]))
      for (layer in 2:3) next_states[[layer]] <- (1-r$alpha[[layer]])*states[[layer]] +
        r$alpha[[layer]]*tanh(states[[layer]] %*% t(r$W[[layer]]) + next_states[[layer-1L]] %*% t(r$Win[[layer]]))
      states <- next_states
      z <- sweep(sweep(cbind(states[[3L]],states[[1L]],states[[2L]]), 2L, d$state_center, "-"), 2L, d$state_scale, "/")
      if(mean_only) {
        mean_design[j,] <- colMeans(z)
        variance[j,] <- pmax((colSums(z*z)-n*mean_design[j,]^2)/(n-1L),0)
        for (h in 1:2) half_design[[h]][j,] <- colMeans(z[half == h,,drop=FALSE])
      }
      q <- matrix(0,n,K)
      for (k in seq_len(K)) {cols<-((k-1L)*p+1L):(k*p); q[,k]<-alpha[,k]+rowSums(z*beta[,cols,drop=FALSE])}
      contracted <- app_joint_qdesn_postscore_contract_rows(q,tau)
      fixed <- contracted$q_contract
      position <- pmax(1L,pmin(K-1L,findInterval(uniforms[,j],tau)))
      left <- fixed[cbind(seq_len(n),position)]; right <- fixed[cbind(seq_len(n),position+1L)]
      fraction <- (uniforms[,j]-tau[position])/(tau[position+1L]-tau[position])
      lag <- left+fraction*(right-left)
      lag[uniforms[,j]<=tau[[1L]]] <- fixed[uniforms[,j]<=tau[[1L]],1L]
      lag[uniforms[,j]>=tau[[K]]] <- fixed[uniforms[,j]>=tau[[K]],K]
      if (!mean_only) {
        for (k in seq_len(K)) {
          expected <- expected + 2*weights[[k]]*app_joint_recursive_empirical_expected_check(fixed[,k],tau[[k]],oracle$sorted_response[,j],oracle$prefix_response[,j])
          realized <- realized + 2*weights[[k]]*app_joint_qdesn_postscore_check_loss(oracle$observed_y[[j]],fixed[,k],tau[[k]])
        }
        raw_cross <- raw_cross + rowSums(contracted$raw_crossing > 1e-12)
        contract_cross <- contract_cross + rowSums(contracted$contract_crossing > 1e-12)
        adjustments <- adjustments + rowMeans(abs(fixed-q))
        max_adjustments <- pmax(max_adjustments,apply(abs(fixed-q),1L,max))
      }
    }
  }
  expect(all(is.finite(mean_design)), "Nonfinite vectorized future design")
  stable_scale<-sqrt(variance)
  stable_scale[!is.finite(stable_scale)|stable_scale<1e-8]<-1
  diagnostics<-data.frame(inference_draws=n,
    standardized_rms_half_difference=sqrt(mean(((half_design[[1L]]-half_design[[2L]])/stable_scale)^2)),
    finite=all(is.finite(c(mean_design,variance))))
  list(mean_design = mean_design, half_mean = half_design, diagnostics=diagnostics,
    scores = data.frame(draw_index=seq_len(n),chain_id=chain_id,source_draw_index=source_draw_index,
      origin_marginal_dgp_integrated_acrps=expected/990,realized_acrps=realized/990,
      raw_crossing_pairs=raw_cross,contract_crossing_pairs=contract_cross,
      mean_abs_monotone_adjustment=adjustments/990,max_abs_monotone_adjustment=max_adjustments))
}
get_fit <- function(model) switch(model,
  independent_qdesn_rhs=context$independent_al, independent_exqdesn_rhs=context$independent_exal,
  joint_qdesn_rhs=context$joint$AL,joint_exqdesn_rhs=context$joint$exAL)
vb_draws <- function(fit, n, seed, independent) {
  p <- ncol(d$Z); K <- length(tau)
  beta <- if (independent) do.call(cbind,lapply(seq_len(K),function(k)
    app_joint_recursive_mvn_draws(fit$fits[[k]]$beta_mean,fit$fits[[k]]$beta_cov,n,seed+7919L*k))) else
    app_joint_recursive_mvn_draws(fit$beta_mean,fit$beta_cov,n,seed)
  list(beta=beta,alpha=matrix(rep(fit$alpha_mean,each=n),n,K),chain_id=rep(NA_integer_,n),source_draw_index=seq_len(n))
}
state_proof<-function(recursive,beta,alpha) {
  canonical<-app_joint_recursive_canonical_metrics(recursive$mean_design,colMeans(beta),colMeans(alpha),oracle,tau,weights)$origin_marginal_dgp_integrated_acrps
  halves<-vapply(recursive$half_mean,function(Z)
    app_joint_recursive_canonical_metrics(Z,colMeans(beta),colMeans(alpha),oracle,tau,weights)$origin_marginal_dgp_integrated_acrps,numeric(1))
  # This is the existing strict half-score gate, with precisely its original
  # denominator. The pooled score is retained only as a finite-value check.
  relative<-abs(diff(halves))/max(abs(mean(halves)),1e-12)
  data.frame(inference_draws=recursive$diagnostics$inference_draws,
    standardized_rms_half_difference=recursive$diagnostics$standardized_rms_half_difference,
    half_canonical_score_relative_difference=relative,rms_gate=.10,score_gate=.005,
    finite=all(is.finite(c(canonical,halves))),
    pass=all(is.finite(c(canonical,halves)))&&recursive$diagnostics$standardized_rms_half_difference<=.10&&relative<=.005)
}
old_score <- old("forecast_score_summary")
old_plan <- old("cell_plan")
tasks <- expand.grid(model=as.character(candidate$model_id),inference=c("mcmc","vb"),stringsAsFactors=FALSE)
task <- function(i) {
  row <- tasks[i,]; model<-row$model; method<-row$inference
  path <- file.path(cache,paste0(model,"_",method,".rds"))
  signature <- sha(file.path(runtime,"article/datasets/dataset_02/context.rds"))
  if (file.exists(path)) {
    out <- readRDS(path)
    expect(identical(out$context_sha256,signature) && identical(out$script_sha256,sha(script)), "Postprocessing cache provenance mismatch")
    cat("REUSED",model,method,"\n");return(out)
  }
  cat("RECONSTRUCTING",model,method,"\n")
  frozen_cell <- candidate[candidate$model_id==model,,drop=FALSE]
  template <- old_score[old_score$scenario_id=="laplace_bridge" & old_score$model_id==model_map[[model]] & old_score$inference_method==method,,drop=FALSE]
  plan <- old_plan[old_plan$worker_id==template$worker_id,,drop=FALSE]
  metadata <- NULL
  if (method=="mcmc") {
    jobs <- chains[chains$cell_id==frozen_cell$cell_id,,drop=FALSE]
    dirs <- file.path(runtime,"article/chains",sprintf("worker_%04d",jobs$worker_id))
    frames <- lapply(dirs,function(x)read(file.path(x,"posterior_draws.csv.gz")))
    metadata <- do.call(rbind,lapply(dirs,function(x)read(file.path(x,"metadata.csv"))))
    expect(nrow(metadata)==5L && length(unique(metadata$target_hash))==1L &&
      all(metadata$retained_draws==if(model %in% c("independent_qdesn_rhs","joint_qdesn_rhs"))750L else 1500L), "Chain identity/cardinality mismatch")
    if(frozen_cell$likelihood=="exAL")expect(all(metadata$method=="M0_v_collapsed_support_logit"),"Nonexact exAL source")
    beta <- do.call(rbind,lapply(frames,app_joint_recursive_select_block,block="beta"))
    alpha <- do.call(rbind,lapply(frames,app_joint_recursive_select_block,block="alpha"))
    chain_id <- rep(jobs$chain_id,vapply(frames,nrow,integer(1)))
    source_index <- unlist(lapply(frames,function(x)x$draw_index),use.names=FALSE)
    seed <- as.integer(ct$score_seed_base+2000L+1000000L)
    if(frozen_cell$structure=="independent")for(j in seq_along(frames)) {
      ii<-which(chain_id==jobs$chain_id[[j]])
      coupled<-app_joint_recursive_couple_independent(beta[ii,,drop=FALSE],alpha[ii,,drop=FALSE],ncol(d$Z),seed+j)
      beta[ii,]<-coupled$beta;alpha[ii,]<-coupled$alpha
    }
    recursive <- readRDS(file.path(runtime,"article/scores",sprintf("cell_%04d",frozen_cell$cell_id),"mean_design.rds"))
    draws <- read(file.path(runtime,"article/scores",sprintf("cell_%04d",frozen_cell$cell_id),"score_draws.csv.gz"))
    checkdraws <- app_joint_recursive_score_draws(recursive$mean_design,beta,alpha,oracle,tau,weights,100L,chain_id,source_index)
    expect(max(abs(as.matrix(checkdraws[,c("origin_marginal_dgp_integrated_acrps","realized_acrps","raw_crossing_pairs","contract_crossing_pairs")])-as.matrix(draws[,c("origin_marginal_dgp_integrated_acrps","realized_acrps","raw_crossing_pairs","contract_crossing_pairs")])))<1e-11,"Frozen score reconstruction disagrees")
    frozen_summary <- read(file.path(runtime,"article/scores",sprintf("cell_%04d",frozen_cell$cell_id),"summary.csv"))
    set.seed(seed+313L)
    uniforms<-matrix(runif(nrow(beta)*990L),nrow(beta),990L)
  } else {
    posterior<-vb_draws(get_fit(model),4000L,plan$score_seed[[1L]],frozen_cell$structure=="independent")
    beta<-posterior$beta;alpha<-posterior$alpha;chain_id<-posterior$chain_id;source_index<-posterior$source_draw_index
    for(n_state in c(1000L,2000L,4000L)) {
      state<-vb_draws(get_fit(model),n_state,plan$state_seed[[1L]],frozen_cell$structure=="independent")
      set.seed(plan$uniform_seed[[1L]])
      state_uniforms<-matrix(runif(n_state*990L),n_state,990L)
      recursive<-path_evaluate(state$beta,state$alpha,state_uniforms,state$chain_id,state$source_draw_index,mean_only=TRUE)
      if(state_proof(recursive,beta,alpha)$pass)break
    }
    draws<-app_joint_recursive_score_draws(recursive$mean_design,beta,alpha,oracle,tau,weights,100L,chain_id,source_index)
    frozen_summary<-NULL
    set.seed(plan$uniform_seed[[1L]]+313L)
    uniforms<-matrix(runif(nrow(beta)*990L),nrow(beta),990L)
  }
  path_result<-path_evaluate(beta,alpha,uniforms,chain_id,source_index)
  probes<-unique(round(seq(1,nrow(beta),length.out=3)))
  native<-app_joint_pure_recursive_path_score_draws(d,context$fixture,beta[probes,,drop=FALSE],alpha[probes,,drop=FALSE],uniforms[probes,,drop=FALSE],oracle,tau,weights,chain_id[probes],source_index[probes])
  columns<-c("origin_marginal_dgp_integrated_acrps","realized_acrps","raw_crossing_pairs","contract_crossing_pairs","mean_abs_monotone_adjustment","max_abs_monotone_adjustment")
  difference<-max(abs(as.matrix(native[,columns])-as.matrix(path_result$scores[probes,columns])))
  expect(is.finite(difference)&&difference<1e-9,"Vectorized path evaluator failed native reference")
  summary<-app_joint_recursive_draw_summary(draws,method)
  state_check<-state_proof(recursive,beta,alpha)
  expect(state_check$pass,paste("Mean-design strict stability gate failed",model,method))
  canonical<-app_joint_recursive_canonical_metrics(recursive$mean_design,colMeans(beta),colMeans(alpha),oracle,tau,weights)
  names(canonical)<-paste0("canonical_",names(canonical))
  path_summary<-app_joint_recursive_draw_summary(path_result$scores,method)
  names(path_summary)<-paste0("path_",names(path_summary))
  for(name in names(summary))if(name%in%names(template))template[[name]]<-summary[[name]]
  for(name in names(canonical))template[[name]]<-canonical[[name]]
  for(name in names(path_summary))template[[name]]<-path_summary[[name]]
  template$score_stability_status<-if(method=="mcmc")frozen_summary$functional_status else "pass"
  if(method=="mcmc")template$score_rank_rhat<-frozen_summary$score_rank_rhat
  template$vb_alpha_uncertainty_included<-if(method=="vb")FALSE else NA
  qfit<-matrix(0,length(d$fit_local),length(tau))
  bbar<-colMeans(beta);abar<-colMeans(alpha)
  for(k in seq_along(tau)){cols<-((k-1L)*ncol(d$Z)+1L):(k*ncol(d$Z));qfit[,k]<-as.vector(d$Z[d$fit_local,,drop=FALSE]%*%bbar[cols])+abar[[k]]}
  contracted<-app_joint_qdesn_apply_monotone_contract(qfit,tau)
  error<-contracted$qhat_contract-d$true_q[d$fit_local,,drop=FALSE]
  fitting<-data.frame(scenario_id="laplace_bridge",model_cell_id=template$model_cell_id,inference_method=method,
    fit_oracle_mae=mean(abs(error)),fit_oracle_rmse=sqrt(mean(error^2)),
    fit_raw_crossing_pairs=sum(contracted$raw_crossing$n_crossing_pairs),fit_contract_crossing_pairs=sum(contracted$contract_crossing$n_crossing_pairs),
    scope="canonical_posterior_mean_action_oracle_diagnostic")
  if(method=="mcmc")expect(abs(fitting$fit_oracle_mae-frozen_summary$fit_oracle_mae)<1e-11,"Frozen fit MAE disagrees")
  crossing<-data.frame(worker_id=template$worker_id,scenario_id="laplace_bridge",model_cell_id=template$model_cell_id,inference_method=method,
    posterior_raw_crossing_pairs_mean=mean(draws$raw_crossing_pairs),posterior_raw_crossing_pairs_median=median(draws$raw_crossing_pairs),
    posterior_contract_crossing_pairs_max=max(draws$contract_crossing_pairs),canonical_raw_crossing_pairs=canonical$canonical_raw_crossing_pairs,
    canonical_contract_crossing_pairs=canonical$canonical_contract_crossing_pairs,
    path_posterior_raw_crossing_pairs_mean=mean(path_result$scores$raw_crossing_pairs),path_posterior_raw_crossing_pairs_median=median(path_result$scores$raw_crossing_pairs),
    path_posterior_contract_crossing_pairs_max=max(path_result$scores$contract_crossing_pairs))
  policy<-data.frame(scenario_id="laplace_bridge",model_cell_id=template$model_cell_id,inference_method=method,
    posterior_score_mean=template$posterior_score_mean,posterior_score_interval_width=template$posterior_score_interval_width,
    path_posterior_score_mean=template$path_posterior_score_mean,path_posterior_score_interval_width=template$path_posterior_score_interval_width,
    mean_state_minus_path_mean=template$posterior_score_mean-template$path_posterior_score_mean,
    mean_state_to_path_width_ratio=template$posterior_score_interval_width/template$path_posterior_score_interval_width)
  out<-list(score=template,crossing=crossing,fit=fitting,policy=policy,draws=draws,path_draws=path_result$scores,
    metadata=metadata,state_proof=state_check,context_sha256=signature,script_sha256=sha(script),native_path_max_difference=difference,
    path_uniform_seed=if(method=="mcmc")seed+313L else plan$uniform_seed[[1L]]+313L)
  saveRDS(out,path);cat("POSTPROCESSED",model,method,"native_difference",format(difference),"\n");out
}
results<-parallel::mclapply(seq_len(nrow(tasks)),task,mc.cores=workers,mc.preschedule=FALSE)
expect(!any(vapply(results,inherits,logical(1),"try-error")),"At least one deterministic reconstruction failed")
key<-function(x)paste(x$scenario_id,x$model_cell_id,x$inference_method,sep="|")

# Keep every unaffected CSV row lexically unchanged. Seventeen significant
# digits for new numerics preserve IEEE-double round trips exactly.
csv_row<-function(frame,i)paste(vapply(frame,function(column){
  x<-column[[i]];if(is.na(x))return("")
  if(is.logical(x))return(if(x)"TRUE" else "FALSE")
  if(is.numeric(x))return(sprintf("%.17g",x))
  paste0('"',gsub('"','""',as.character(x),fixed=TRUE),'"')
},character(1)),collapse=",")
write_exact<-function(name,updates,keyfun=key){
  prior<-old(name);before<-prior
  ids<-match(keyfun(updates),keyfun(prior));expect(!anyNA(ids)&&!anyDuplicated(ids),paste("Replacement identity mismatch",name))
  expect(identical(names(updates),names(prior)),paste("Replacement schema mismatch",name))
  for(j in seq_along(ids))prior[ids[[j]],]<-updates[j,]
  raw<-readLines(oldfile(name),warn=FALSE);expect(length(raw)==nrow(prior)+1L,"Historical multiline CSV not supported")
  for(j in ids)raw[[j+1L]]<-csv_row(prior,j)
  path<-file.path(repo,"tables",paste0(prefix,name,".csv"));writeLines(raw,path,useBytes=TRUE)
  check<-read(path);unaffected<-setdiff(seq_len(nrow(prior)),ids)
  expect(isTRUE(all.equal(before[unaffected,,drop=FALSE],check[unaffected,,drop=FALSE],tolerance=0,check.attributes=FALSE)),paste("Unaffected rows changed",name))
  invisible(check)
}
write_new<-function(frame,name){path<-file.path(repo,"tables",paste0(prefix,name,".csv"));writeLines(c(paste0('"',names(frame),'"',collapse=","),vapply(seq_len(nrow(frame)),function(i)csv_row(frame,i),character(1))),path,useBytes=TRUE);invisible(path)}
score_updates<-do.call(rbind,lapply(results,`[[`,"score"));score<-write_exact("forecast_score_summary",score_updates)
cross<-write_exact("crossing_summary",do.call(rbind,lapply(results,`[[`,"crossing")))
fit<-write_exact("fit_oracle_diagnostics",do.call(rbind,lapply(results,`[[`,"fit")))
policy<-write_exact("recursive_policy_comparison",do.call(rbind,lapply(results,`[[`,"policy")))
plan_updates<-old_plan[old_plan$scenario_id=="laplace_bridge",,drop=FALSE]
for(name in intersect(names(context$selected),names(plan_updates)))plan_updates[[name]]<-context$selected[[name]][[1L]]
for(name in c("calibration_exact_gaussian_crps_mean","runtime_seconds_total","condition_gate_status","saturation_gate_status"))plan_updates[[name]]<-NA
plan_updates$selection_window<-"separate_source_realizations"
plan_updates$selection_metric<-"quantile_score_validation_shared_across_four_models"
plan_updates$next_stage<-"protected_evaluation_complete"
plan_updates$state_seed[plan_updates$inference_method=="mcmc"]<-NA
plan_updates$score_seed[plan_updates$inference_method=="mcmc"]<-as.integer(ct$score_seed_base+2000L+1000000L)
plan_updates$uniform_seed[plan_updates$inference_method=="mcmc"]<-as.integer(ct$score_seed_base+2000L+1000000L)
plan_updates$p<-ncol(d$Z);plan_updates$design_fingerprint<-d$design_fingerprint
plan_updates$design_path<-"frozen_laplace_candidate_context_design"
plan_updates$design_relative_path<-"article/datasets/dataset_02/context.rds"
plan_updates$fixture_relative_path<-"frozen_inputs/laplace_article_fixture.rds"
plan_updates$initializer_relative_path<-"article/datasets/dataset_02/context.rds"
plan_updates$initializer_status<-"frozen_nested_vb"
plan<-write_exact("cell_plan",plan_updates)
backbone<-old("selected_backbones");bb<-backbone[backbone$scenario_id=="laplace_bridge",,drop=FALSE]
for(name in intersect(names(context$selected),names(bb)))bb[[name]]<-context$selected[[name]][[1L]]
for(name in c("calibration_exact_gaussian_crps_mean","runtime_seconds_total","condition_gate_status","saturation_gate_status"))bb[[name]]<-NA
bb$selection_window<-"separate_source_realizations"
bb$selection_metric<-"quantile_score_validation_shared_across_four_models"
bb$next_stage<-"protected_evaluation_complete"
write_exact("selected_backbones",bb,function(x)x$scenario_id)
target_updates<-do.call(rbind,lapply(results[vapply(results,function(x)x$score$inference_method=="mcmc",logical(1))],function(x)
  data.frame(model_cell_id=x$score$model_cell_id,likelihood_family=x$score$likelihood_family,n_chains=5L,
    posterior_target_sha256=unique(x$metadata$target_hash),verified=TRUE)))
write_exact("mcmc_posterior_target_hash_audit",target_updates,function(x)x$model_cell_id)
contrast<-old("posterior_contrast_summary");contrast_updates<-contrast[contrast$scenario_id=="laplace_bridge",,drop=FALSE]
for(i in seq_len(nrow(contrast_updates))){row<-contrast_updates[i,];select<-function(id)results[[which(vapply(results,function(x)x$score$model_cell_id==id&&x$score$inference_method==row$inference_method,logical(1)))]]$draws$origin_marginal_dgp_integrated_acrps
  left<-select(row$left_model_cell_id);right<-select(row$right_model_cell_id);n<-max(length(left),length(right))
  # Repeating the shorter sequence uses all frozen exAL draws, with no thinning.
  delta<-rep(left,length.out=n)-rep(right,length.out=n)
  contrast_updates$mean_difference[[i]]<-mean(delta);contrast_updates$median_difference[[i]]<-median(delta)
  # The frozen Laplace handoff uses default-R (type 7) contrast percentiles.
  # Score percentiles remain type 8 through app_joint_recursive_draw_summary;
  # every non-Laplace contrast row retains its historical values verbatim.
  contrast_updates$q025_difference[[i]]<-quantile(delta,.025,type=7,names=FALSE);contrast_updates$q975_difference[[i]]<-quantile(delta,.975,type=7,names=FALSE)
  contrast_updates$probability_left_better[[i]]<-mean(delta<0)
  contrast_updates$coupling[[i]]<-if(length(left)==length(right))"deterministic_index_coupling_for_descriptive_contrast" else "deterministic_index_coupling_repeating_shorter_sequence_no_thinning"
}
write_exact("posterior_contrast_summary",contrast_updates,function(x)paste(x$scenario_id,x$inference_method,x$contrast_type,x$contrast_label,sep="|"))
winners<-old("scenario_winner_summary");winner_updates<-do.call(rbind,lapply(c("vb","mcmc"),function(method){
  x<-score[score$scenario_id=="laplace_bridge"&score$inference_method==method,,drop=FALSE];x<-x[which.min(x$posterior_score_mean),names(winners),drop=FALSE];x}))
write_exact("scenario_winner_summary",winner_updates,function(x)paste(x$scenario_id,x$inference_method,sep="|"))
cardinality<-score[,c("scenario_id","model_cell_id","inference_method")]
cardinality$score_draws<-ifelse(score$inference_method=="vb",4000L,ifelse(score$scenario_id=="laplace_bridge"&score$likelihood_family=="exAL",7500L,3750L))
cardinality$n_score_draws<-cardinality$score_draws
cardinality$chains<-ifelse(score$inference_method=="mcmc",5L,0L)
cardinality$draws_per_chain<-ifelse(cardinality$chains==5L,cardinality$score_draws/5,NA)
cardinality$forecast_opportunities<-5940L
cardinality$posterior_forecast_opportunities<-cardinality$score_draws*5940L
write_new(cardinality,"draw_cardinality")
ledger<-score_updates[,c("scenario_id","model_cell_id","inference_method")]
oldidx<-match(key(ledger),key(old_score));newidx<-match(key(ledger),key(score_updates))
ledger$old_score_mean<-old_score$posterior_score_mean[oldidx]
ledger$new_score_mean<-score_updates$posterior_score_mean[newidx]
ledger$old_canonical_crossings<-old_score$canonical_raw_crossing_pairs[oldidx]
ledger$new_canonical_crossings<-score_updates$canonical_raw_crossing_pairs[newidx]
ledger$source_relative_path<-"article/datasets/dataset_02/context.rds"
ledger$context_sha256<-sha(file.path(runtime,ledger$source_relative_path[[1L]]))
ledger$preserved_other_scenarios<-TRUE
write_new(ledger,"replacement_ledger")
sampler<-old("sampler_audit");sampler$scope<-"historical_v1_complete_packet_not_current_aggregate"
candidate_jobs<-chains[chains$dataset_id==2L,,drop=FALSE]
repair_tables<-lapply(candidate_jobs$worker_id,function(id){
  x<-readRDS(file.path(runtime,"article/chains",sprintf("worker_%04d",id),"precision_diagnostics.rds"))
  # Joint workers store a diagnostics frame; independent workers store seven
  # component frames directly. Some older objects nest each component frame.
  tables<-c(list(x$diagnostics),lapply(x$components,function(one)
    if(is.data.frame(one))one else one$diagnostics))
  tables<-Filter(function(z)is.data.frame(z)&&nrow(z)>0,tables)
  tables<-lapply(tables,function(z){
    expect(all(c("status","jitter_relative")%in%names(z)),"Malformed precision diagnostics")
    z[z$status=="repaired",,drop=FALSE]})
  tables<-Filter(function(z)nrow(z)>0L,tables)
  if(length(tables))do.call(rbind,tables)else NULL})
repair_rows<-Filter(Negate(is.null),repair_tables)
new_sampler<-data.frame(workers_with_repairs=sum(!vapply(repair_tables,is.null,logical(1))),total_repairs=sum(vapply(repair_rows,nrow,integer(1))),
  max_relative_jitter=if(length(repair_rows))max(vapply(repair_rows,function(x)max(x$jitter_relative),numeric(1)))else 0,
  exal_M0_workers=sum(candidate_jobs$likelihood=="exAL"),scope="candidate_laplace_only")
write_new(rbind(sampler,new_sampler),"sampler_audit")
write_new(manifest_receipts,"runtime_manifest_audit")
pin_paths<-c(names(pins),"article/datasets/dataset_02/context.rds","article/datasets/dataset_02/oracle.rds","article/cells.csv","article/chains.csv","architectures.csv","frozen_inputs/laplace_article_fixture.rds","frozen_inputs/laplace_baseline_design.rds","frozen_inputs/laplace_dgp_oracle.rds")
sources<-data.frame(role=ifelse(pin_paths%in%names(pins),"frozen_closeout_pin","frozen_candidate_input"),relative_path=pin_paths,
  size_bytes=file.info(file.path(runtime,pin_paths))$size,sha256=vapply(file.path(runtime,pin_paths),sha,character(1)))
old_sources<-list.files(file.path(repo,"tables"),paste0("^",oldprefix,".*[.]csv$"),full.names=TRUE)
sources<-rbind(sources,data.frame(role="historical_v1_source",relative_path=substring(old_sources,nchar(repo)+2L),size_bytes=file.info(old_sources)$size,sha256=vapply(old_sources,sha,character(1))))
write_new(sources,"source_hashes")
proof<-data.frame(name=c("source_lane_head","score_draw_policy","vb_score_draws","vb_state_draws","vb_alpha_uncertainty_included","posterior_index_coupling","contrast_pairing","recursive_path_draws","native_path_reference_max_difference","runtime_verified_manifests","runtime_verified_payloads","sampler_aggregate_scope","protected_realization_scope","projection_arithmetic"),
  value=c("6ff88298d7f10814071a9fec4a9a6d32804cdfb1","all_retained_candidate_MCMC_draws_AL3750_exAL7500",4000,"1000_then_2000_then_4000_until_existing_strict_stability_gates_pass",FALSE,"within_chain_independent_quantile_block_permutation_as_frozen_runtime","deterministic_index_equal_length_or_repeat_shorter_no_thinning","all_final_score_draws",max(vapply(results,`[[`,numeric(1),"native_path_max_difference")),nrow(manifest_receipts),sum(manifest_receipts$verified_payloads),"historical_v1_and_candidate_only_separate_not_summed","previously_evaluated_excluded_from_candidate_selection","10_2608_0_288"))
proof<-rbind(proof,data.frame(name=c("reconstruction_script_sha256","R_version","candidate_context_sha256","strict_stability_half_score_denominator","reconstructed_cells","preserved_cells"),
  value=c(sha(script),R.version.string,sha(file.path(runtime,"article/datasets/dataset_02/context.rds")),"absolute_mean_of_half_canonical_scores",8L,56L)))
proof<-rbind(proof,data.frame(name=c("contrast_percentile_type","score_percentile_type","historical_non_laplace_contrast_convention","contrast_percentile_scope"),
  value=c(7L,8L,"preserved_unchanged_type8","reconstructed_Laplace_rows_only_matching_frozen_handoff")))
write_new(proof,"postprocessing_provenance")
projection_proof<-proof;names(projection_proof)<-c("field","value")
write_new(projection_proof,"projection_provenance")
state_receipts<-do.call(rbind,lapply(results,function(x)cbind(x$score[,c("scenario_id","model_cell_id","inference_method")],x$state_proof)))
write_new(state_receipts,"state_stability_audit")
seeds<-do.call(rbind,lapply(results,function(x)data.frame(scenario_id=x$score$scenario_id,model_cell_id=x$score$model_cell_id,inference_method=x$score$inference_method,
  path_uniform_seed=x$path_uniform_seed,native_path_max_difference=x$native_path_max_difference)))
write_new(seeds,"postprocessing_seeds")
mcmc<-score[score$inference_method=="mcmc",];totals<-tapply(mcmc$canonical_raw_crossing_pairs,mcmc$model_id,sum)
expect(all(totals[c("joint_qdesn_rhs_mcmc","qdesn_rhs_independent_mcmc","joint_exqdesn_rhs_mcmc","exqdesn_rhs_independent_mcmc")]==c(10,2608,0,288)),"Corrected addendum crossings disagree")
expect(nrow(score)==64L&&all(is.finite(score$posterior_score_mean))&&all(score$contract_crossing_pairs==0)&&all(score$path_contract_crossing_pairs==0),"Incomplete v2 scores")
cat("LAPLACE_V2_RECONSTRUCTION=PASS rows=64 replacements=8 untouched=56 MCMC=32 canonical_crossings=10/2608/0/288\n")
