source("scripts/ind_adapted_auxiliary_filter.R")
aaf_n <- 0L
aaf_check <- function(x){stopifnot(isTRUE(x));aaf_n <<- aaf_n+1L}
aaf_close <- function(x,y,tol=1e-10)isTRUE(all.equal(x,y,tolerance=tol,check.attributes=FALSE))
aaf_reject <- function(x)aaf_check(inherits(tryCatch({force(x);NULL},error=identity),"error"))
had_rng <- exists(".Random.seed",.GlobalEnv,inherits=FALSE)
if(had_rng)old_rng <- .Random.seed
N <- 6L;p <- 1L
eta <- list(family="al",p=.25,sigma=.7,gamma=0)
init <- function(e=eta)ind_aaf_initialize(0,matrix(1,1L),matrix(.2,1L),e,N,"synthetic-native-17",ess_fraction=.99)
s <- init();s$mean[] <- c(-.7,-.2,.3,.5,1.2,2)
s$covariance[] <- c(.1,.3,.5,.2,.4,.6);s$weights <- c(.05,.1,.2,.25,.4,0)
u <- list(proposal=matrix(seq(.03,.96,length.out=N*4L),N,4L),ancestor=.37,residual_resampling=.63)
y <- .4
# Independent one-dimensional integration of the original response likelihood.
al_pdf <- function(z,p,sigma)p*(1-p)/sigma*exp(-z*(p-(z<0))/sigma)
ell <- vapply(seq_len(N),function(j)integrate(function(L)
  dnorm(L,s$mean[j],sqrt(1.2*s$covariance[j]))*al_pdf(y-L,eta$p,eta$sigma),
  -Inf,Inf,rel.tol=1e-10,abs.tol=1e-12)$value,numeric(1L))
expected_r <- s$weights*ell/sum(s$weights*ell)
z <- ind_aaf_step(s,y,1,matrix(1,1L),u,1L)
d <- z$last_diagnostics;cp <- z$last_report
aaf_check(aaf_close(d$ancestor_probabilities,expected_r,1e-9))
aaf_check(aaf_close(d$log_predictive_increment,log(sum(s$weights*ell)),1e-9))
aaf_check(aaf_close(d$log_mean_residual_weight,0))
aaf_check(aaf_close(cp$weights,rep(1/N,N)))
aaf_check(d$lookahead_is_exact && d$proposal=="fully_adapted_AL_ancestor_and_v")
aaf_check(!cp$temporary_projected_location_assimilated && !z$parameter_weights_updated &&
  !z$numerical_accuracy_qualified && !z$production_authorized && z$random_draws_generated==0L)
pos <- ((seq_len(N)-1)+u$ancestor)/N
manual_A <- vapply(pos,function(x)which(cumsum(expected_r)>x)[1L],integer(1L))
aaf_check(identical(d$ancestor_indices,manual_A))
aaf_check(!any(d$ancestor_indices==6L))
aaf_check(d$selected_ancestor_count<N)
duplicate <- which(duplicated(d$ancestor_indices))[1L]
previous <- which(d$ancestor_indices==d$ancestor_indices[duplicate])[1L]
aaf_check(abs(cp$covariance[,,duplicate]-cp$covariance[,,previous])>1e-9)
for(i in seq_len(N)) {
  j <- d$ancestor_indices[i];R <- 1.2*s$covariance[j]
  pr <- ind_gap_propose(y,s$mean[j],R,eta$p,eta$sigma,as.numeric(u$proposal[i,]))
  aaf_check(aaf_close(cp$mean[i],s$mean[j]+R*(y-s$mean[j]-pr$ex_f)/(R+pr$ex_q)))
  aaf_check(aaf_close(cp$covariance[,,i],R-R^2/(R+pr$ex_q)))
}

# exAL prior-s guidance needs nonconstant residual weights, and its
# likelihood normalizer needs BOTH lookahead and mean-residual terms.
ex <- eta;ex$family <- "exal";ex$gamma <- .3
sx <- init(ex);sx$mean <- s$mean;sx$covariance <- s$covariance;sx$weights <- s$weights
ux <- u;ux$half_normal <- seq(.01,.99,length.out=N)
zx <- ind_aaf_step(sx,y,1,matrix(1,1L),ux,1L);dx <- zx$last_diagnostics
aaf_check(!dx$lookahead_is_exact && dx$post_resampled)
residual <- numeric(N)
for(i in seq_len(N)) {
  j <- dx$ancestor_indices[i]
  pr <- ind_gap_exal_propose(y,sx$mean[j],1.2*sx$covariance[j],ex$p,ex$sigma,ex$gamma,
    qnorm((1-ux$half_normal[i])/2,lower.tail=FALSE),as.numeric(ux$proposal[i,]))
  # Recover each selected ancestor's actual positive lookahead from r_j Z/w_j.
  tilt <- dx$ancestor_probabilities[j]*exp(dx$log_lookahead_normalizer)/sx$weights[j]
  residual[i] <- exp(pr$log_predictive_density)/tilt
}
aaf_check(aaf_close(zx$last_report$weights,residual/sum(residual)))
aaf_check(aaf_close(dx$log_predictive_increment,dx$log_lookahead_normalizer+log(mean(residual))))
aaf_check(aaf_close(zx$weights,rep(1/N,N)))
aaf_check(!aaf_close(zx$last_report$weights,zx$weights))
ex$gamma <- 0;sg <- init(ex);sg$mean <- s$mean;sg$covariance <- s$covariance;sg$weights <- s$weights
zg <- ind_aaf_step(sg,y,1,matrix(1,1L),ux,1L)
for(k in c("mean","covariance","weights"))aaf_check(aaf_close(zg$last_report[[k]],z$last_report[[k]]))
aaf_check(aaf_close(zg$last_diagnostics$log_predictive_increment,d$log_predictive_increment))

# Exact run/chunk/carry parity, even when post-resampling and reporting differ.
n <- 5L
streams <- list(proposal=array(seq(.013,.987,length.out=N*n*4L),c(N,n,4L)),
  ancestor=seq(.11,.89,length.out=n),residual_resampling=seq(.19,.79,length.out=n),
  half_normal=matrix(seq(.02,.98,length.out=N*n),N,n))
ex$gamma <- -.2
start <- init(ex);yy <- c(.2,-.3,.8,.1,-.6);FF <- matrix(1,1L,n);GG <- matrix(1,1L)
full <- ind_aaf_continue(start,yy,FF,GG,streams,1:5,1:5)
slice <- function(a,b)list(proposal=streams$proposal[,a:b,,drop=FALSE],
  ancestor=streams$ancestor[a:b],residual_resampling=streams$residual_resampling[a:b],
  half_normal=streams$half_normal[,a:b,drop=FALSE])
first <- ind_aaf_continue(start,yy[1:2],FF[,1:2,drop=FALSE],GG,slice(1,2),1:2,1:2)
rest <- ind_aaf_continue(first$state,yy[3:5],FF[,3:5,drop=FALSE],GG,slice(3,5),3:5,3:5)
aaf_check(identical(full$state,rest$state))
aaf_check(identical(full$checkpoints,c(first$checkpoints,rest$checkpoints)))
aaf_check(identical(full$diagnostics,c(first$diagnostics,rest$diagnostics)))
late_y <- yy;late_y[4:5] <- c(30,-99)
late <- ind_aaf_continue(start,late_y,FF,GG,streams,1:5,1:5)
aaf_check(identical(full$checkpoints[1:3],late$checkpoints[1:3]))
aaf_reject(ind_aaf_step(full$checkpoints[["1"]],0,1,GG,u,2L))
bad <- start;bad$identity$eta$sigma <- 2
aaf_reject(ind_aaf_continue(bad,yy,FF,GG,streams,1:5,1:5))
bad <- start;bad$identity$C0[] <- 2
aaf_reject(ind_aaf_continue(bad,yy,FF,GG,streams,1:5,1:5))
aaf_reject(ind_aaf_continue(start,yy,FF,matrix(1,2,2),streams,1:5,1:5))
aaf_reject(ind_aaf_continue(start,yy,FF,GG,streams,c(1,2,4,5,6),1:5))
aaf_reject(ind_aaf_continue(start,yy,FF,GG,streams,1:5,c(2,1)))
for(mut in list(function(x){x$proposal[1]<-0;x},function(x){x$ancestor<-1;x},
  function(x){x$residual_resampling<-NA_real_;x},function(x){x$half_normal<-rep(.5,N);x}))
  aaf_reject(ind_aaf_step(s,y,1,GG,mut(u),1L))
bad <- s;bad$covariance[] <- -1
aaf_reject(ind_aaf_step(bad,y,1,GG,u,1L))
aaf_check(identical(exists(".Random.seed",.GlobalEnv,inherits=FALSE),had_rng))
if(had_rng)aaf_check(identical(.Random.seed,old_rng))
cat(sprintf("IND_ANCESTOR_FIRST_FILTER_CHECKS=%d PASS; protected_reads=0 fits=0 production=FALSE\n",aaf_n))
