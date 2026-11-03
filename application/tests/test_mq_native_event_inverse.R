#!/usr/bin/env Rscript
# One bounded generated build and numerical equivalence test, not qualification.
local({
 root<-if(exists("app_repo_root",mode="function"))app_repo_root()else {
  f<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
  normalizePath(file.path(dirname(f),"../.."),mustWork=TRUE)
 }
 # The unchanged reference uses vapply(exists), requiring the same global
 # dependency visibility as the existing standalone reference tests.
 setwd(root);source("application/R/integrated_quantile_forecast.R",local=FALSE)
 source("scripts/mq_forecast_array_methods.R",local=FALSE);source("scripts/mq_native_event_inverse.R",local=TRUE)
 checks<-0L;ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L}
 reject<-function(expr){e<-tryCatch({force(expr);NULL},error=function(e)e);ok(inherits(e,"error"))}
 bits<-function(a,b)identical(a,b,num.eq=FALSE)
 old_rng<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
 pinned<-c("application/R/integrated_quantile_forecast.R","scripts/mq_forecast_array_methods.R")
 before<-tools::sha256sum(pinned)
 build<-Sys.getenv("MQE_BUILD_ROOT",unset="")
 if(!nzchar(build))build<-tempfile("mq_event_generated_build_")
 stopifnot(!file.exists(build),dir.create(build))
 stopifnot(file.copy("scripts/native/mq_event_inverse.c",file.path(build,"mq_event_inverse.c")))
 makevars<-file.path(build,"controlled.Makevars")
 writeLines(c("CFLAGS = -O2 -fno-fast-math -ffp-contract=off","PKG_CFLAGS = -fno-fast-math -ffp-contract=off"),makevars)
 old_env<-Sys.getenv(c("R_MAKEVARS_USER","R_MAKEVARS_SITE","MAKEFLAGS"),unset=NA_character_)
 restore<-function(){for(n in names(old_env))if(is.na(old_env[[n]]))Sys.unsetenv(n)else do.call(Sys.setenv,setNames(list(old_env[[n]]),n))}
 on.exit(restore(),add=TRUE)
 Sys.setenv(R_MAKEVARS_USER=makevars,R_MAKEVARS_SITE="/dev/null",MAKEFLAGS="-j1")
 wd<-getwd();setwd(build)
 log<-system2(file.path(R.home("bin"),"R"),c("CMD","SHLIB","--preclean","mq_event_inverse.c"),stdout=TRUE,stderr=TRUE)
 setwd(wd);restore();cat(paste(log,collapse="\n"),"\n")
 ok(is.null(attr(log,"status")));ok(any(grepl("-ffp-contract=off",log,fixed=TRUE)))
 dll<-normalizePath(file.path(build,paste0("mq_event_inverse",.Platform$dynlib.ext)),mustWork=TRUE)
 backend<-mqe_load(dll,unname(tools::sha256sum(dll)),"generated_fixture_only")
 ok(identical(backend$dll[["dynamicLookup"]],FALSE))
 ok(identical(names(getDLLRegisteredRoutines(backend$dll)[[".Call"]]),c("mqe_first_indices","mqe_cdf_values")))
 native<-function(q,p,tau=c(.1,.5,.9),...)mqe_inverse(q,tau,p,backend,scope="generated_fixture_only",...)
 compare<-function(q,tau,p) {
  original<-serialize(q,NULL,version=3L)
  ref<-app_iqf_mq_matrix_inverse(q,tau,p)
  got<-native(q,p,tau);ok(bits(got,ref))
  ok(bits(native(q,p,tau,cdf_backend="unchanged_reference"),ref))
  ok(identical(original,serialize(q,NULL,version=3L)))
 }
 tau<-c(.1,.5,.9);eps<-.Machine$double.eps;small<-.Machine$double.xmin*eps
 cases<-list(matrix(c(-1,0,1),1L),rbind(c(0,0,1),c(1,2,2)),matrix(rep(2,6),2L),
  rbind(c(-0,0,-0),c(0,-0,0)),rbind(c(2,-1,1),c(0,1,2)),
  rbind(c(0,1,2),c(4,5,6)),rbind(1+eps*c(0,1,2),1+eps*c(0,2,2)),
  matrix(c(0,small,2*small),1L))
 for(q in cases)compare(q,tau,setNames(c(.9,.1,.5,.1,.75),letters[1:5]))
 # An atom/plateau uses the first >= event, not root finding or last match.
 q<-rbind(rep(0,3),rep(2,3));compare(q,tau,c(.5,.50001,.25,.75))
 got<-native(q,c(.5,.50001));ok(got[1]==0&&got[2]==2)
 tiny<-native(matrix(c(0,small,2*small),1L),c(.1,.5,.9),return_receipt=TRUE)
 ok(tiny$fallback&&tiny$reason=="nonfinite_events"&&!tiny$production_authorized)
 # A nondefault huge tolerance can overflow a probe; the unchanged R CDF
 # accepts infinite queries, so use it rather than invent a bisection failure.
 huge<-matrix(c(0,1e308,1.7e308),1L)
 ok(bits(native(huge,.5,tolerance=1e308),app_iqf_mq_matrix_inverse(huge,tau,.5,1e308)))
 # Pointwise CDF values retain exact native interpolation and R mean handling.
 for(K in c(2L,7L,16L)) {
  p<-seq(.03,.97,length.out=K)
  q<-matrix(sort(sin(seq_len(32L*K)*.33)),32L,K)
  q<-t(apply(q,1L,sort));q[2,]<-q[1,];q[3,]<-rep(0,K)
  y<-setNames(c(-2,-1,-0,0,.01,.5,1,2),letters[1:8])
  means<-mqe_cdf(y,q,p,backend,"generated_fixture_only")
  ok(bits(means,app_iqf_mq_matrix_cdf(y,q,p)))
  values<-.Call(backend$cdf,q,as.double(p),as.double(y))
  for(i in 1:4)for(j in seq_along(y))ok(bits(values[i,j],app_iqf_mq_grid_cdf(as.double(y[j]),q[i,],p)))
  compare(q,p,c(.01,.05,.5,.95,.99))
 }
 # Sequential filters retain separate draw-specific lag paths; only terminal
 # conditional-CDF inversion is replaced, never a mean-feature approximation.
 levels<-c(.05,.10,.25,.50,.75,.90,.95)
 for(draw in 1:2) {
  past<-sin(1:32)/10+draw/100
  for(h in 1:30) {
   raw<-outer(.7*past+sin(h+1:32)/10,rep(1,7))+matrix(rep(c(-1,-.8,-.3,0,.2,.8,1),each=32),32,7)
   ref<-app_iqf_mq_matrix_inverse(raw,levels,levels)
   ok(bits(native(raw,levels,levels),ref))
   u<-((1:32*17+h*3)%%97)/97
   past<-vapply(1:32,function(i)app_iqf_mq_grid_inverse(raw[i,],levels,u[i]),0)
  }
 }
 for(q in list(matrix(0,0,3),matrix(0,1,1),matrix(c(NA,0,1),1L),c(0,1),list(1,2)))reject(native(q,.5))
 reject(native(matrix(0,1,3),c(0,1)));reject(native(matrix(0,1,3),.5,tolerance=0))
 reject(mqe_inverse(matrix(c(-1,0,1),1L),tau,.5,backend))
 reject(mqe_load(dll,strrep("0",64),"generated_fixture_only"))
 reject(.Call(backend$scan,c(0L,1L),.5));reject(.Call(backend$scan,c(0,NA),.5))
 reject(.Call(backend$cdf,matrix(c(0,2,1),1L),tau,.5))
 reject(.Call(backend$cdf,matrix(0L,1,3),tau,.5))
 reject(mqe_cdf(.5,matrix(c(-1,0,1)+1i,1L),tau,backend,"generated_fixture_only"))
 reject(mqe_cdf(.5,matrix(c(-1,0,1),1L),tau+1i,backend,"generated_fixture_only"))
 reject(mqe_cdf(.5+1i,matrix(c(-1,0,1),1L),tau,backend,"generated_fixture_only"))
 # A single bounded generated timing, not a full-unit/campaign speed estimate.
 q<-outer(sin(seq_len(8192L)*.031),levels*2)+matrix(rep(seq(-2,2,length.out=7),each=8192L),8192L,7)
 timing_ref<-system.time(ref<-app_iqf_mq_matrix_inverse(q,levels,levels))
 timing_new<-system.time(new<-native(q,levels,levels));ok(bits(ref,new))
 cat(sprintf("GENERATED_EVENT_TIMING reference_cpu=%.6f candidate_cpu=%.6f authentic_speedup_claimed=FALSE\n",
  sum(timing_ref[1:2]),sum(timing_new[1:2])))
 ok(identical(tools::sha256sum(pinned),before))
 now_rng<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
 ok(identical(old_rng,now_rng))
 ok(identical(unname(tools::sha256sum(dll)),backend$sha256))
 cat(sprintf("MQ_NATIVE_EVENT_CANDIDATE_PASS checks=%d production_runs=0 default_switches=0\n",checks))
})
