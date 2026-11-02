#!/usr/bin/env Rscript
# Synthetic pure-DESN fixtures only; no scientific fit or cache is opened.
for (file in c("joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
  "latent_path_design.R", "joint_qdesn_pure_recursive_campaign.R",
  "joint_qdesn_recursive_mean_design.R", "integrated_quantile_forecast.R")) source(file.path("application/R", file))
source("scripts/integrated_quantile_mq_batch.R")
`%||%` <- function(a, b) if (is.null(a)) b else a
mqb_n <- 0L
mqb_check <- function(x) { stopifnot(isTRUE(x)); mqb_n <<- mqb_n + 1L }
mqb_close <- function(a, b, tol = 1e-11)
  isTRUE(all.equal(a, b, tolerance = tol, check.attributes = FALSE))
mqb_reject <- function(expr) mqb_check(inherits(tryCatch({force(expr); NULL}, error = identity), "error"))
mqb_hash <- paste(rep("a",64L),collapse="")
mqb_tau <- c(.05,.1,.25,.5,.75,.9,.95)
set.seed(20481); mqb_seed <- .Random.seed; mqb_kind <- RNGkind()

# Fused extraction is bit-identical to the unchanged native wrapper for every
# original tuple, including nonconsecutive/reordered inner IDs and prefixes.
for (ids in list(1L,c(13L,2L,51L,7L),1:67,c(1L,.Machine$integer.max))) {
  u <- app_iqf_mqb_uniforms("seed_parity","draw17","origin29",ids,5L)
  reference <- matrix(NA_real_,length(ids),5L)
  for(h in 1:5)for(i in seq_along(ids))reference[i,h] <- app_iqf_rng(
    app_iqf_seed("seed_parity","draw17","origin29",ids[i],h,"response"),function()stats::runif(1L))
  mqb_check(identical(u,reference))
  mqb_check(identical(.Random.seed,mqb_seed) && identical(RNGkind(),mqb_kind))
}
uq <- app_iqf_mqb_uniforms("seed_parity","draw17","origin29",1:19,3L)
mqb_check(identical(uq,app_iqf_mqb_uniforms("seed_parity","draw17","origin29",1:19,5L)[,1:3,drop=FALSE]))
# An isolated error injector shadows only this test copy's seed lookup, not
# the frozen native helper or any global binding. An error midway through
# extraction must restore both the caller's RNG kind and exact state.
error_probe <- app_iqf_mqb_uniforms
error_scope <- new.env(parent=environment(error_probe)); error_scope$calls <- 0L
error_scope$app_iqf_seed <- function(...) {
  error_scope$calls <- error_scope$calls + 1L
  if(error_scope$calls==3L)stop("injected post-entry seed error")
  app_iqf_seed(...)
}
environment(error_probe) <- error_scope
mqb_reject(error_probe("seed_parity","draw17","origin29",1:3,2L))
mqb_check(identical(.Random.seed,mqb_seed) && identical(RNGkind(),mqb_kind))
# Absence of a caller seed is also preserved on successful and failed calls.
rm(".Random.seed",envir=.GlobalEnv)
invisible(app_iqf_mqb_uniforms("seed_parity","draw17","origin29",1:3,2L))
mqb_check(!exists(".Random.seed",.GlobalEnv,inherits=FALSE) && identical(RNGkind(),mqb_kind))
error_scope$calls <- 0L
mqb_reject(error_probe("seed_parity","draw17","origin29",1:3,2L))
mqb_check(!exists(".Random.seed",.GlobalEnv,inherits=FALSE) && identical(RNGkind(),mqb_kind))
assign(".Random.seed",mqb_seed,.GlobalEnv)

# Optional R4.6 first-step specialization: source declaration is NOT external
# source authentication or execution permission. More than 1,000 original
# purpose-key identities and handcrafted valid positive28-bit boundary states
# must match the actual native RNG bit for bit.
proof <- app_iqf_mqb_rng_reference()
ids <- 1:257; H <- 5L
native_u <- matrix(NA_real_,length(ids),H)
seeds <- matrix(0L,length(ids)*H,6L)
row <- 0L
for(h in seq_len(H))for(i in seq_along(ids)) {
  old <- app_iqf_seed("mq_first_step_parity","chain2/draw47","origin33",ids[i],h,"response")
  fast <- app_iqf_mqb_fast_seed("mq_first_step_parity","chain2/draw47","origin33",ids[i],h)
  mqb_check(identical(old,fast))
  row <- row+1L; seeds[row,] <- old
  native_u[i,h] <- app_iqf_rng(old,function()stats::runif(1L))
}
mqb_check(identical(app_iqf_mqb_first_uniform(seeds,proof),as.numeric(native_u)))
mqb_check(identical(app_iqf_mqb_fast_uniforms("mq_first_step_parity","chain2/draw47","origin33",ids,H,proof),native_u))
corners <- as.matrix(expand.grid(a=c(1,2^28),b=c(1,2^28),c=c(1,2^28),d=c(1,2^28)))
boundary <- matrix(1,nrow(corners),6L); boundary[,c(1,2,4,6)] <- corners
for(k in c(1,10,100)) boundary <- rbind(boundary,c(1403580*k,810728*k,1,527612*k,1,1370589*k))
boundary_native <- apply(boundary,1L,function(seed)app_iqf_rng(as.integer(seed),function()stats::runif(1L)))
mqb_check(identical(app_iqf_mqb_first_uniform(boundary,proof),boundary_native))
mqb_check(all(app_iqf_mqb_first_uniform(boundary,proof)>0 & app_iqf_mqb_first_uniform(boundary,proof)<1))
for(value in c(0,2^28+1,1.5,NA_real_,Inf)) {
  bad <- rep(1,6);bad[1L] <- value
  mqb_reject(app_iqf_mqb_first_uniform(bad,proof))
}
wrong <- proof; wrong$RNG_c_sha256 <- paste(rep("b",64),collapse="")
mqb_reject(app_iqf_mqb_first_uniform(rep(1,6),wrong))
wrong <- proof; wrong$R_version <- "4.5.0"
mqb_reject(app_iqf_mqb_first_uniform(rep(1,6),wrong))
mqb_reject(app_iqf_mqb_first_uniform(rep(1,6),NULL))
mqb_check(identical(.Random.seed,mqb_seed) && identical(RNGkind(),mqb_kind))
rm(".Random.seed",envir=.GlobalEnv)
invisible(app_iqf_mqb_uniforms("first_step_absence","draw1","origin1",1:3,2L,
  "r46_first_step_qualified",proof))
mqb_check(!exists(".Random.seed",.GlobalEnv,inherits=FALSE) && identical(RNGkind(),mqb_kind))
assign(".Random.seed",mqb_seed,.GlobalEnv)

mqb_fixture <- function(D = 2L, activation = "tanh", projection = FALSE,
    standardize = TRUE, regime = FALSE) {
  widths <- c(3L,2L,2L)[seq_len(D)]
  sc <- data.frame(simulated_length = 50L, period = 12L,
    regime_start_fraction = .15,
    dynamics_class = if(regime) "regime_shift_location_scale" else "ar_fixture")
  y <- c(.3,-.7,.1,.9,-.4,.2,.6,-.1)
  full <- 3:8
  raw <- app_joint_pure_raw_matrix(full,y,data.frame(response_lags=2L),sc)
  m <- ncol(raw)
  scale <- list(standardize = standardize,
    center = stats::setNames(seq(-.2,.2,length.out=m),colnames(raw)),
    scale = stats::setNames(seq(.7,1.4,length.out=m),colnames(raw)))
  r <- list(D=D,n=widths,alpha=c(.35,.7,.5)[seq_len(D)],
    W=lapply(widths,function(n) matrix(seq(-.12,.14,length.out=n*n),n,n)),
    Win=lapply(seq_len(D),function(d) {
      n <- widths[d]; k <- if(d==1L)m+1L else widths[d-1L]
      matrix(seq(-.25,.3,length.out=n*k),n,k)
    }),act_f=activation,act_k=if(D==3L)"tanh" else "identity",
    Q=if(D>1L)lapply(widths[seq_len(D-1L)],function(n)diag(n)) else list(),
    Q_is_identity=rep(TRUE,max(0L,D-1L)))
  if(projection && D>1L) {
    r$Q[[1L]] <- diag(widths[1L])[rev(seq_len(widths[1L])),,drop=FALSE]
    r$Q_is_identity[1L] <- FALSE
  }
  meta <- list(standardize_inputs=FALSE,lag_center=rep(0,m),lag_scale=rep(1,m),
    input_bound="none",win_scale_global=.8,win_scale_bias=.8)
  scaled <- app_qdesn_reservoir_scale_inputs(raw,scale_params=scale)$X
  rolled <- app_qdesn_roll_article_reservoir(scaled,r,meta)
  p <- ncol(rolled$X_all)
  state_center <- seq(-.1,.1,length.out=p); state_scale <- seq(.8,1.3,length.out=p)
  Z <- sweep(sweep(rolled$X_all,2L,state_center,"-"),2L,state_scale,"/")
  colnames(Z) <- paste0("reservoir_",sprintf("%04d",seq_len(p)))
  design <- list(scenario_id="synthetic_pure",feature_contract="pure_recursive_v1",
    design_class="reservoir",response_lags=2L,dgp_row=sc,scale_params=scale,
    reservoir=r,reservoir_meta=meta,state_center=state_center,state_scale=state_scale,
    Z=Z,row_meta=data.frame(full_time_index=full),
    full_states_all_layers=TRUE,raw_inputs_in_readout=FALSE)
  K <- length(mqb_tau)
  posterior <- list(beta=rbind(seq(-.2,.3,length.out=p*K),seq(.25,-.15,length.out=p*K)),
    alpha=rbind(c(-1,-.2,.1,.7,.3,1.3,.9),c(-.9,-.5,.1,.3,.8,1,1.4)),
    draw_ids=c("chain1/draw11","chain2/draw23"),chain_id=c(1L,2L),
    source_draw_index=c(11L,23L),draw_mapping_sha256=mqb_hash)
  origins <- list(o8=list(origin_time=8L,H=5L,history=y),
    o7=list(origin_time=7L,H=3L,history=y[1:7]))
  coupling <- list(method="native_joint_posterior",recipe_sha256=mqb_hash,
    draw_mapping_sha256=mqb_hash)
  list(design=design,posterior=posterior,origins=origins,tau=mqb_tau,coupling=coupling,
    rng_namespace="synthetic_pure_MQ_batch_v1")
}

# All supported activations, full-state depths, nontrivial projection and
# standardization are compared with the unchanged scalar path implementation.
for (case in list(c(1L,"identity",FALSE,TRUE,FALSE),c(2L,"tanh",FALSE,TRUE,FALSE),
  c(2L,"relu",TRUE,FALSE,TRUE),c(3L,"tanh",TRUE,TRUE,TRUE))) {
  f <- mqb_fixture(as.integer(case[1]),case[2],as.logical(case[3]),as.logical(case[4]),as.logical(case[5]))
  scalar <- do.call(app_iqf_desn_adapter,c(f,list(family="mq_grid")))
  batched <- do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=7L,batch_size=3L)))
  mqb_check(inherits(batched,"app_iqf_adapter") && !batched$production_authorized &&
    !batched$numerical_accuracy_qualified)
  for (draw in f$posterior$draw_ids) for (origin in names(f$origins)) {
    many <- app_iqf_mq_batch_paths(batched,draw,origin,c(1L,3L,7L),include_trace=TRUE)
    for (i in seq_along(many$inner_ids)) {
      reference <- scalar$path(draw,origin,many$inner_ids[i])
      mqb_check(mqb_close(reference$response,many$paths[[i]]$response))
      for(h in seq_along(reference$kernels))
        mqb_check(mqb_close(reference$kernels[[h]]$q,many$paths[[i]]$kernels[[h]]$q))
    }
    # Explicit trace replay uses the original raw/scale/reservoir/readout
    # helpers, so agreement is not only an output-quantile self comparison.
    context <- batched$batch_context; snap <- context$snapshots[[origin]]
    for(i in seq_along(many$inner_ids)) {
      state <- snap$states[[1L]]; history <- f$origins[[origin]]$history
      j <- match(draw,f$posterior$draw_ids)
      for(h in seq_len(f$origins[[origin]]$H)) {
        raw <- app_joint_recursive_feature_from_history(f$origins[[origin]]$origin_time+h,history,f$design)
        step <- app_joint_recursive_readout_row(raw,state,f$design,snap$reservoir_meta)
        mqb_check(mqb_close(raw,many$trace[[h]]$raw[,i]))
        mqb_check(mqb_close(step$z,many$trace[[h]]$readout[,i]))
        for(d in seq_along(step$states))
          mqb_check(mqb_close(step$states[[d]],many$trace[[h]]$states[[d]][,i]))
        mqb_check(mqb_close(app_joint_recursive_predict_vector(step$z,
          f$posterior$beta[j,],f$posterior$alpha[j,],f$tau),many$trace[[h]]$raw_quantiles[i,]))
        state <- step$states; history <- c(history,many$response[i,h])
      }
    }
    # Cached scalar interface remains compatible with the original runner,
    # including an uneven last batch and switching draw/origin cache keys.
    for(inner in c(1L,2L,3L,7L,4L,1L)) {
      ref <- scalar$path(draw,origin,inner); b <- batched$path(draw,origin,inner)
      mqb_check(mqb_close(ref$response,b$response))
      mqb_check(mqb_close(ref$kernels,b$kernels))
    }
  }
  mqb_check(identical(.Random.seed,mqb_seed) && identical(RNGkind(),mqb_kind))
}

f <- mqb_fixture(); scalar <- do.call(app_iqf_desn_adapter,c(f,list(family="mq_grid")))
batch <- do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=7L,batch_size=3L)))
sc <- app_iqf_run_task(scalar,f$posterior$draw_ids[1],"o8",7L,f$tau,"model",include_paths=TRUE)
bc <- app_iqf_run_task(batch,f$posterior$draw_ids[1],"o8",7L,f$tau,"model",include_paths=TRUE)
mqb_check(mqb_close(sc$paths,bc$paths))
mqb_check(mqb_close(sc$quantiles$quantile,bc$quantiles$quantile))
mqb_check(identical(sc$original_draw,bc$original_draw) && identical(sc$rng_namespace,bc$rng_namespace))
mqb_check(identical(batch$coupling,f$coupling))
mqb_check(batch$rng_mode == "native_scoped")
fast_batch <- do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=7L,batch_size=3L,
  rng_mode="r46_first_step_qualified",rng_proof=proof)))
fc <- app_iqf_run_task(fast_batch,f$posterior$draw_ids[1],"o8",7L,f$tau,"model",include_paths=TRUE)
mqb_check(identical(sc$paths,fc$paths))
mqb_check(identical(sc$quantiles$quantile,fc$quantiles$quantile))
mqb_check(!fast_batch$rng_source_binding_authenticated && !fast_batch$production_authorized)

# Path count / partition / horizon extensions preserve original stream keys.
one <- do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=3L,batch_size=1L)))
many <- app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"o8",1:7)
for(i in 1:3) mqb_check(mqb_close(one$path(f$posterior$draw_ids[1],"o8",i),many$paths[[i]]))
pieces <- lapply(list(1:2,3:6,7L),function(ids)
  app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"o8",ids))
mqb_check(mqb_close(do.call(rbind,lapply(pieces,`[[`,"response")),many$response))
reversed <- app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"o8",7:1)
mqb_check(mqb_close(reversed$response,many$response[7:1,,drop=FALSE]))
prefix_f <- f; prefix_f$origins$o8$H <- 2L
prefix <- do.call(app_iqf_mq_batch_adapter,c(prefix_f,list(inner_paths=7L,batch_size=4L)))
pp <- app_iqf_mq_batch_paths(prefix,f$posterior$draw_ids[1],"o8",1:7)
mqb_check(mqb_close(pp$response,many$response[,1:2,drop=FALSE]))
mqb_check(mqb_close(pp$ordered_quantiles,many$ordered_quantiles[,,1:2,drop=FALSE]))
# Stored design values beyond an observed cutoff never reach reconstruction.
past <- f; past$origins <- past$origins["o7"]
future_changed <- past; future_changed$design$Z[6L,] <- 999
past_adapter <- do.call(app_iqf_mq_batch_adapter,c(past,list(inner_paths=2L,batch_size=2L)))
future_adapter <- do.call(app_iqf_mq_batch_adapter,c(future_changed,list(inner_paths=2L,batch_size=2L)))
mqb_check(mqb_close(past_adapter$path(f$posterior$draw_ids[1],"o7",1L),
  future_adapter$path(f$posterior$draw_ids[1],"o7",1L)))
f_ind <- f; f_ind$coupling$method <- "frozen_product_posterior_assembly"
ind <- do.call(app_iqf_mq_batch_adapter,c(f_ind,list(inner_paths=7L,batch_size=2L)))
mqb_check(ind$coupling$method == "frozen_product_posterior_assembly")
mqb_check(mqb_close(ind$path(f$posterior$draw_ids[1],"o8",2L),batch$path(f$posterior$draw_ids[1],"o8",2L)))

# Endpoint/flat/grid interpolation uses the unchanged inverse-CDF response law.
q <- rbind(c(-2,-1,0,.2,.3,.7,1),rep(2,7),c(-1,-1,0,0,2,3,3))
for(u in list(c(0,.5,1),c(.05,.1,.95),c(.2,.7,.8))) {
  ref <- vapply(seq_len(nrow(q)),function(i)app_iqf_mq_grid_inverse(q[i,],f$tau,u[i]),numeric(1L))
  mqb_check(mqb_close(app_iqf_mqb_inverse_rows(q,f$tau,u),ref))
}

for(change in list(
  function(x){x$design$feature_contract <- "legacy_fixture";x},
  function(x){x$design$design_class <- "hybrid";x},
  function(x){x$design$response_lags <- 2.5;x},
  function(x){x$design$scale_params$scale[1] <- 0;x},
  function(x){x$design$reservoir$act_f <- function(z)z;x},
  function(x){x$design$reservoir$act_k <- "unknown";x},
  function(x){x$design$state_scale[1] <- 0;x},
  function(x){x$design$reservoir$W[[1]][1] <- Inf;x},
  function(x){x$coupling <- NULL;x},
  function(x){x$coupling$draw_mapping_sha256 <- paste(rep("b",64),collapse="");x},
  function(x){x$origins$o8$future_y <- 0;x}
)) mqb_reject(do.call(app_iqf_mq_batch_adapter,c(change(f),list(inner_paths=7L,batch_size=3L))))
mqb_reject(do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=0L,batch_size=3L))))
mqb_reject(do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=7L,batch_size=1.5))))
mqb_reject(do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=7L,rng_mode="unknown"))))
mqb_reject(do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=7L,rng_mode="r46_first_step_qualified"))))
mqb_reject(batch$path(f$posterior$draw_ids[1],"o8",8L))
mqb_reject(app_iqf_mq_batch_paths(batch,"missing","o8",1L))
mqb_reject(app_iqf_mq_batch_paths(batch,f$posterior$draw_ids,"o8",1L))
mqb_reject(app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"missing",1L))
mqb_reject(app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"o8",c(1L,1L)))
mqb_reject(app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"o8",0))
mqb_reject(app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"o8",8L))
mqb_reject(app_iqf_mq_batch_paths(batch,f$posterior$draw_ids[1],"o8",2^32))
# Named probability labels are preserved exactly in native kernel metadata.
named <- f; names(named$tau) <- paste0("q",seq_along(named$tau))
named_batch <- do.call(app_iqf_mq_batch_adapter,c(named,list(inner_paths=2L,batch_size=2L)))
named_scalar <- do.call(app_iqf_desn_adapter,c(named,list(family="mq_grid")))
mqb_check(identical(named_batch$path(named$posterior$draw_ids[1],"o8",1L)$kernels[[1L]]$tau,
  named_scalar$path(named$posterior$draw_ids[1],"o8",1L)$kernels[[1L]]$tau))
mqb_check(identical(.Random.seed,mqb_seed) && identical(RNGkind(),mqb_kind))
cat(sprintf("MQ_BATCH_ADAPTER_CHECKS=%d PASS; protected_reads=0 fits=0 production_launches=0\n",mqb_n))
