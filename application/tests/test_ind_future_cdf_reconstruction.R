source("scripts/ind_future_cdf_reconstruction.R")
fcm_n <- 0L
fcm_check <- function(x){stopifnot(isTRUE(x));fcm_n <<- fcm_n+1L}
fcm_close <- function(x,y,tol=1e-10)isTRUE(all.equal(x,y,tolerance=tol,check.attributes=FALSE))
fcm_reject <- function(x)fcm_check(inherits(tryCatch({force(x);NULL},error=identity),"error"))
had_rng <- exists(".Random.seed",.GlobalEnv,inherits=FALSE)
if(had_rng)old_rng <- .Random.seed
eta <- list(family="al",p=.25,sigma=.8,gamma=0)
cp <- list(eta=eta,mean=matrix(c(-1,1),1L),covariance=array(c(.3,.5),c(1L,1L,2L)),
  weights=c(.3,.7),representation="weighted_pre_resampling",parameter_id="synthetic-native-11",
  observed_prefix_length=500L)
H <- 3L;F <- matrix(1,1L,H);G <- matrix(1,1L);D <- matrix(.2,1L)
v <- matrix(seq(.2,2,length.out=4L*H),4L,H);map <- c(1L,1L,2L,2L)
build <- function(vp=v,dt=D,checkpoint=cp,FF=F,GG=G)
  ind_fcm_components(checkpoint,FF,GG,dt,checkpoint$eta,vp,map,
    "known_deterministic","native_prior_Exp_scale_sigma_supplied_paths")
z <- build()
fcm_check(fcm_close(z$weight,c(.15,.15,.35,.35)))
fcm_check(fcm_close(z$mean[,1L],c(-1,-1,1,1)))
fcm_check(fcm_close(z$variance[,1L],1.2*c(.3,.3,.5,.5)))
fcm_check(z$Gaussian_states_and_intermediate_responses_integrated && z$terminal_v_integrated &&
  !z$intermediate_half_Normal_shifts_required && !z$joint_future_path_law_returned &&
  !z$origin_filter_accuracy_qualified && !z$future_auxiliary_integration_qualified && !z$production_authorized)
args <- c(-2,0,3)
h1 <- ind_fcm_cdf(args,1L,z)
expected <- vapply(args,function(y).3*ind_gap_al_cdf(y,-1,.36,.25,.8)+
  .7*ind_gap_al_cdf(y,1,.6,.25,.8),numeric(1L))
fcm_check(fcm_close(h1$value,expected))
fcm_check(all(h1$terminal_quadrature_error_estimate==0) && !h1$particle_filter_accuracy_certified)
one <- ind_gaf_origin_components(cp,1,G,D,"known_deterministic")
fcm_check(fcm_close(h1$value,ind_gap_mixture_cdf(args,one$mean,one$variance,.25,.8,one$weight)))

# A terminal v does not enter that horizon's state law, but affects later W.
modified <- v;modified[,2L] <- modified[,2L]*4
changed <- build(modified)
fcm_check(identical(z$mean[,1:2],changed$mean[,1:2]))
fcm_check(identical(z$variance[,1:2],changed$variance[,1:2]))
fcm_check(max(abs(z$variance[,3L]-changed$variance[,3L]))>1e-4)
last <- v;last[,3L] <- last[,3L]*7
fcm_check(identical(z$variance,build(last)$variance))

# Unit discount is a fully analytical all-horizon benchmark. No sampled
# future auxiliary or response is allowed to add a second state uncertainty.
exact <- build(dt=matrix(0,1L))
for(h in 1:H) {
  fcm_check(fcm_close(exact$variance[,h],c(.3,.3,.5,.5)))
  fcm_check(fcm_close(ind_fcm_cdf(args,h,exact)$value,ind_fcm_cdf(args,1L,exact)$value))
}
q <- ind_fcm_quantile(c(.05,.25,.5,.95),1L,z)
fcm_check(all(q$result$cdf_lower<=q$result$probability & q$result$cdf_upper>=q$result$probability))
fcm_check(q$finite_mixture_bracket_is_analytic && !q$production_authorized &&
  !q$origin_filter_accuracy_qualified && !q$future_auxiliary_integration_qualified)
q_components <- .3*(-1)+.7*1
fcm_check(abs(q$result$quantile[2L]-q_components)>.01)

# Horizon extension, origin replication and irregular path replication retain
# the same mixture law and original component mass.
long <- build(vp=cbind(v,matrix(1,4L,27L)),FF=matrix(1,1L,30L))
fcm_check(identical(z$mean,long$mean[,1:3]))
fcm_check(identical(z$variance,long$variance[,1:3]))
vr <- rbind(v[1:2,,drop=FALSE],v[3,,drop=FALSE],v[3,,drop=FALSE],v[4,,drop=FALSE],v[4,,drop=FALSE])
zr <- ind_fcm_components(cp,F,G,D,eta,vr,c(1,1,2,2,2,2),
  "known_deterministic","native_prior_Exp_scale_sigma_supplied_paths")
for(h in 1:H)fcm_check(fcm_close(ind_fcm_cdf(args,h,z)$value,ind_fcm_cdf(args,h,zr)$value))

# exAL gamma=0 agrees exactly with AL; signed nonzero shapes retain the
# quantile-fixed native point-location property, with quadrature labelled.
g0 <- cp;g0$eta$family <- "exal"
zg <- build(checkpoint=g0)
fcm_check(identical(z$variance,zg$variance))
fcm_check(identical(h1$value,ind_fcm_cdf(args,1L,zg)$value))
for(gamma in c(-.2,.2)) {
  point <- list(eta=list(family="exal",p=.25,sigma=.8,gamma=gamma),mean=matrix(0,1,1),
    covariance=array(0,c(1L,1L,1L)),weights=1,representation="weighted_pre_resampling",
    parameter_id="synthetic-native-point",observed_prefix_length=500L)
  ep <- ind_fcm_components(point,matrix(1,1L,2L),G,matrix(0,1L),point$eta,
    matrix(c(.3,1.1),1L),1L,"known_deterministic","native_prior_Exp_scale_sigma_supplied_paths")
  ec <- ind_fcm_cdf(0,1L,ep,1e-11,1e-11)
  fcm_check(abs(ec$value-.25)<1e-9)
  fcm_check(ec$error_kind=="weighted_QUADPACK_error_estimate_not_rigorous_bound" &&
    !ec$rigorous_quadrature_error_bound && !ec$origin_filter_accuracy_qualified)
  eq <- ind_fcm_quantile(.6,1L,ep,absolute_tolerance=1e-6,
    quadrature_absolute_tolerance=1e-12,quadrature_relative_tolerance=1e-12)
  fcm_check(eq$result$cdf_lower<=.6 && eq$result$cdf_upper>=.6 &&
    !eq$finite_mixture_bracket_is_analytic && !eq$rigorous_quadrature_error_bound)
}

fcm_reject(ind_fcm_components(cp,F,G,D,eta,v,map,"response_dependent",
  "native_prior_Exp_scale_sigma_supplied_paths"))
fcm_reject(ind_fcm_components(cp,F,G,D,eta,v,map,"known_deterministic","posterior_v_from_training"))
fcm_reject(ind_fcm_components(cp,F,G,D,eta,v,rep(1,4),"known_deterministic",
  "native_prior_Exp_scale_sigma_supplied_paths"))
bad <- v;bad[1L] <- 0
fcm_reject(build(bad));fcm_reject(build(GG=matrix(1,2,2)))
badcp <- cp;badcp$eta$sigma <- 2
fcm_reject(ind_fcm_components(badcp,F,G,D,eta,v,map,"known_deterministic",
  "native_prior_Exp_scale_sigma_supplied_paths"))
badcp <- cp;badcp$weights <- badcp$weights*2
fcm_reject(build(checkpoint=badcp))
badcp <- cp;badcp$observed_prefix_length <- 0
fcm_reject(build(checkpoint=badcp))
badcp <- cp;badcp$parameter_id <- ""
fcm_reject(build(checkpoint=badcp))
fcm_reject(ind_fcm_cdf(0,0,z));fcm_reject(ind_fcm_cdf(NA_real_,1,z))
fcm_reject(ind_fcm_quantile(1,1,z));fcm_reject(ind_fcm_quantile(.5,1,z,absolute_tolerance=0))
fcm_check(identical(exists(".Random.seed",.GlobalEnv,inherits=FALSE),had_rng))
if(had_rng)fcm_check(identical(.Random.seed,old_rng))
cat(sprintf("IND_FUTURE_TERMINAL_CDF_CHECKS=%d PASS; protected_reads=0 fits=0 production=FALSE\n",fcm_n))
