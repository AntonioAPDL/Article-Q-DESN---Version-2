# Generated-data-only parity checks; no authentic artifacts or launches.
source("scripts/ind_batched_al_auxiliary_filter.R")
ncheck<-0L
check<-function(x){stopifnot(isTRUE(x));ncheck<<-ncheck+1L}
reject<-function(expr) {
 e<-tryCatch({force(expr);NULL},error=identity)
 check(inherits(e,"error"))
}
close_num<-function(a,b,tol=1e-10) {
 check(is.numeric(a)&&is.numeric(b)&&identical(dim(a),dim(b))&&length(a)==length(b)&&
  all(is.finite(c(a,b)))&&all(abs(a-b)<=tol+tol*pmax(abs(a),abs(b))))
}
had_rng<-exists(".Random.seed",.GlobalEnv,inherits=FALSE)
if(had_rng)old_rng<-.Random.seed
old_kind<-RNGkind()
RNGkind("Mersenne-Twister","Inversion","Rejection");set.seed(381741L)
for(N in c(1L,2L,17L,64L))for(pp in c(.01,.05,.5,.95,.99))for(yy in c(-1000,0,1000)) {
 m<-seq(-20,20,length.out=N);S<-rep(c(0,1e-14,.01,1,100),length.out=N)
 u<-matrix(runif(N*4L),N,4L)
 if(N>1L) {
  u[1L,]<-c(1e-12,.5,1-1e-12,1e-12)
  u[N,]<-c(1-1e-12,1e-12,.5,1-1e-12)
 }
 frozen<-.Random.seed
 batch<-ind_baf_al_propose(yy,m,S,pp,.7,u)
 reference<-lapply(seq_len(N),function(j)ind_gap_propose(yy,m[j],S[j],pp,.7,u[j,]))
 for(key in c("v","ex_f","ex_q","log_predictive_density","temporary_L"))
  close_num(batch[[key]],vapply(reference,`[[`,numeric(1L),key),1e-12)
 check(identical(batch$proposal_component,vapply(reference,`[[`,character(1L),"proposal_component")))
 check(identical(.Random.seed,frozen)&&identical(batch$production_authorized,FALSE))
}
reject(ind_baf_al_propose(0,c(0,1),c(1,1),.05,.7,matrix(.5,2,3)))
reject(ind_baf_al_propose(0,c(0,1),c(1,-1),.05,.7,matrix(.5,2,4)))
reject(ind_baf_al_propose(0,c(0,1),c(1,1),.05,.7,matrix(0,2,4)))
reject(ind_baf_al_propose(c(0,1),c(0,1),c(1,1),.05,.7,matrix(.5,2,4)))

for(N in c(1L,7L,32L))for(pp in c(.05,.5,.95)) {
 p<-3L;n<-24L;tt<-seq_len(n);F<-c(1,.4,-.2)
 G<-matrix(c(1,0,0,.1,.95,.02,0,-.02,.95),p,p)
 y<-sin(tt/4);y[c(5L,13L,21L)]<-c(-14,18,-11)
 eta<-list(family="al",p=pp,sigma=.7,gamma=0)
 initial<-ind_aaf_initialize(rep(0,p),diag(.3,p),matrix(.04,p,p),eta,N,"generated_parity_only")
 u<-list(proposal=array(runif(N*n*4L),c(N,n,4L)),ancestor=runif(n),residual_resampling=runif(n))
 frozen<-.Random.seed;FF<-matrix(rep(F,n),p,n)
 reference<-ind_aaf_continue(initial,y,FF,G,u,tt,c(5L,11L,17L,24L))
 batch<-ind_baf_continue(initial,y,FF,G,u,tt,c(5L,11L,17L,24L))
 check(isTRUE(all.equal(batch,reference,tolerance=1e-10,check.attributes=TRUE)))
 for(at in names(reference$checkpoints)) {
  a<-batch$checkpoints[[at]];b<-reference$checkpoints[[at]]
  close_num(a$mean,b$mean);close_num(a$covariance,b$covariance);close_num(a$weights,b$weights)
 }
 check(identical(batch$state$lineage,reference$state$lineage))
 check(identical(lapply(batch$diagnostics,`[[`,"ancestor_indices"),
  lapply(reference$diagnostics,`[[`,"ancestor_indices")))
 check(identical(lapply(batch$diagnostics,`[[`,"post_indices"),
  lapply(reference$diagnostics,`[[`,"post_indices")))
 subu<-function(indices)list(proposal=u$proposal[,indices,,drop=FALSE],
  ancestor=u$ancestor[indices],residual_resampling=u$residual_resampling[indices])
 first<-ind_baf_continue(initial,y[1:11],FF[,1:11,drop=FALSE],G,subu(1:11),1:11,c(5L,11L))
 second<-ind_baf_continue(first$state,y[12:24],FF[,12:24,drop=FALSE],G,subu(12:24),12:24,c(17L,24L))
 check(isTRUE(all.equal(second$state,batch$state,tolerance=1e-12,check.attributes=TRUE)))
 check(isTRUE(all.equal(c(first$checkpoints,second$checkpoints),batch$checkpoints,
  tolerance=1e-12,check.attributes=TRUE)))
 check(identical(.Random.seed,frozen)&&!batch$production_authorized&&!batch$numerical_accuracy_qualified)
 bad<-initial;bad$covariance[1,1,1]<--1
 reject(ind_baf_step(bad,y[1],F,G,list(proposal=matrix(u$proposal[,1,],N,4),
  ancestor=u$ancestor[1],residual_resampling=u$residual_resampling[1]),1))
 reject(ind_baf_continue(initial,y,FF,G,u,tt+1,c(5L,11L)))
}
exal<-ind_aaf_initialize(0,matrix(1,1,1),matrix(.1,1,1),
 list(family="exal",p=.5,sigma=1,gamma=.1),1L,"generated_exal_rejection")
reject(ind_baf_step(exal,0,1,matrix(1,1,1),list(proposal=matrix(.5,1,4),
 ancestor=.5,residual_resampling=.5,half_normal=.5),1L))
do.call(RNGkind,as.list(old_kind))
if(had_rng)assign(".Random.seed",old_rng,.GlobalEnv)else rm(".Random.seed",envir=.GlobalEnv)
cat(sprintf("IND_BATCHED_AL_CHECKS=%d PASS; generated_only=TRUE authentic_reads=0 filters_qualified=0 production=FALSE\n",ncheck))
