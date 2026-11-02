source("scripts/ind_guided_auxiliary_filter.R")
gaf_n <- 0L
gaf_check <- function(ok) { stopifnot(isTRUE(ok)); gaf_n <<- gaf_n + 1L }
gaf_close <- function(a,b,tol=1e-11) isTRUE(all.equal(a,b,tolerance=tol,check.attributes=FALSE))
gaf_reject <- function(expr) gaf_check(inherits(tryCatch({force(expr);NULL},error=identity),"error"))
set.seed(71501)
N <- 12L; n <- 3L
u <- list(proposal=array(runif(N*n*4L),c(N,n,4L)),resampling=runif(n))
eta <- list(family="al",p=.25,sigma=.7,gamma=0)
args <- list(y=c(.7,-.2,.9),FF=matrix(1,1L,n),GG=matrix(1,1L),m0=0,
  C0=matrix(1,1L),df_mat=matrix(.25,1L),eta=eta,uniforms=u,
  observed_prefix_length=n,parameter_id="synthetic-native-column-19",
  checkpoint_indices=1:3,ess_fraction=.8)
gaf_rng <- .Random.seed
z <- do.call(ind_gaf_filter,args)
cp <- z$checkpoints[["1"]]
gaf_check(gaf_close(cp$weights,rep(1/N,N)))
gaf_check(gaf_close(z$ESS[1L],N))
gaf_check(gaf_close(z$log_predictive_normalizers[1L],
  ind_gap_al_terms(.7,0,1.25,.25,.7)$log_density))
gaf_check(!z$parameter_weights_updated && !z$numerical_accuracy_qualified &&
  !z$production_authorized && z$proposal=="exact_locally_optimal_v" && z$random_draws_generated==0L)
gaf_check(!cp$temporary_projected_location_assimilated && !cp$production_authorized)

# Proposal-only L must not be assimilated as another observation. At one
# dimension, that incorrect operation would fix theta=L exactly.
proposal <- ind_gap_propose(.7,0,1.25,.25,.7,as.numeric(u$proposal[1L,1L,]))
expected_C <- 1.25-1.25^2/(1.25+proposal$ex_q)
expected_m <- 1.25*(.7-proposal$ex_f)/(1.25+proposal$ex_q)
gaf_check(gaf_close(cp$mean[1L,1L],expected_m))
gaf_check(gaf_close(cp$covariance[1L,1L,1L],expected_C))
gaf_check(abs(cp$mean[1L,1L]-proposal$temporary_L)>1e-4)
gaf_check(cp$covariance[1L,1L,1L]>0)

# The exAL gamma-zero limit, including arbitrary supplied s innovations.
ex <- args;ex$eta$family <- "exal";ex$uniforms$half_normal <- matrix(seq(.01,.99,length.out=N*n),N,n)
ez <- do.call(ind_gaf_filter,ex)
for(key in c("ESS","resampled","ancestry","log_predictive_normalizers"))
  gaf_check(gaf_close(ez[[key]],z[[key]]))
for(tt in 1:3) for(key in c("mean","covariance","weights"))
  gaf_check(gaf_close(ez$checkpoints[[as.character(tt)]][[key]],z$checkpoints[[as.character(tt)]][[key]]))
gaf_check(ez$proposal=="prior_s_conditionally_optimal_v" && !ez$production_authorized)
for(gamma in c(-.15,.15)) {
  ex$eta$gamma <- gamma
  one <- do.call(ind_gaf_filter,ex)
  gaf_check(all(is.finite(one$ESS)) && all(one$ESS>=1-1e-12))
  gaf_check(all(is.finite(one$checkpoints[["3"]]$mean)))
}

# Weighted checkpoint causality, including forced resampling. Future data
# and the fact that a prefix is the current call's endpoint cannot alter it.
force <- args;force$ess_fraction <- 1
fz <- do.call(ind_gaf_filter,force)
prefix <- force;prefix$y <- prefix$y[1:2];prefix$FF <- prefix$FF[,1:2,drop=FALSE]
prefix$uniforms$proposal <- prefix$uniforms$proposal[,1:2,,drop=FALSE]
prefix$uniforms$resampling <- prefix$uniforms$resampling[1:2]
prefix$observed_prefix_length <- 2L;prefix$checkpoint_indices <- 1:2
fp <- do.call(ind_gaf_filter,prefix)
late <- force;late$y[3L] <- 300
fl <- do.call(ind_gaf_filter,late)
for(tt in 1:2) {
  gaf_check(identical(fp$checkpoints[[as.character(tt)]],fz$checkpoints[[as.character(tt)]]))
  gaf_check(identical(fl$checkpoints[[as.character(tt)]],fz$checkpoints[[as.character(tt)]]))
}
gaf_check(identical(fp$ancestry,fz$ancestry[,1:2,drop=FALSE]))

# Native noncommuting state propagation; guidance cannot change P/W/R.
rot <- matrix(c(0,1,-1,0),2L)
ra <- args;ra$y <- .7;ra$FF <- matrix(c(1,0),2L,1L);ra$GG <- rot
ra$m0 <- c(0,0);ra$C0 <- diag(c(1,4));ra$df_mat <- matrix(.25,2L,2L)
ra$uniforms$proposal <- u$proposal[,1L,,drop=FALSE];ra$uniforms$resampling <- u$resampling[1L]
ra$observed_prefix_length <- 1L;ra$checkpoint_indices <- 1L
rz <- do.call(ind_gaf_filter,ra)
gaf_check(gaf_close(rz$log_predictive_normalizers[1L],ind_gap_al_terms(.7,0,5,.25,.7)$log_density))

# Exact terminal AL integration conditional on the supplied origin mixture.
components <- ind_gaf_origin_components(cp,1,matrix(1,1L),matrix(.25,1L),"known_deterministic")
gaf_check(gaf_close(components$mean,as.numeric(cp$mean)))
gaf_check(gaf_close(components$variance,1.25*as.numeric(cp$covariance)))
gaf_check(gaf_close(components$weight,cp$weights))
gaf_check(!components$origin_filter_accuracy_qualified && !components$future_feature_provenance_authenticated &&
  !components$production_authorized)
q <- ind_gap_mixture_quantile(c(.1,.5,.9),components$mean,components$variance,.25,.7,components$weight,1e-8)
gaf_check(all(diff(q$result$quantile)>0) && !q$origin_filter_accuracy_qualified)
gaf_check(all(q$result$cdf_lower<=q$result$probability & q$result$cdf_upper>=q$result$probability))
gaf_reject(ind_gaf_origin_components(cp,1,matrix(1,1L),matrix(.25,1L),"response_dependent"))

for(mutate in list(
  function(x){x$observed_prefix_length<-2L;x},
  function(x){x$y<-c(x$y,9);x},
  function(x){x$eta$extra<-1;x},
  function(x){x$eta$sigma<-0;x},
  function(x){x$eta$gamma<-.1;x},
  function(x){x$eta$family<-"normal";x},
  function(x){x$uniforms$proposal[1L]<-0;x},
  function(x){x$uniforms$proposal<-x$uniforms$proposal[,,1:3,drop=FALSE];x},
  function(x){x$uniforms$resampling[1L]<-1;x},
  function(x){x$uniforms$half_normal<-matrix(.5,N,n);x},
  function(x){x$checkpoint_indices<-c(2L,1L);x},
  function(x){x$C0[]<--1;x},
  function(x){x$df_mat[]<--1;x},
  function(x){x$FF<-function(y)y;x},
  function(x){x$parameter_id<-"";x}
)) gaf_reject(do.call(ind_gaf_filter,mutate(args)))
gaf_check(identical(.Random.seed,gaf_rng))
cat(sprintf("IND_GUIDED_AUXILIARY_FILTER_CHECKS=%d PASS; protected_reads=0 fits=0 production_runs=0\n",gaf_n))
