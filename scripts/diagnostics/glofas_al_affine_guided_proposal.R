# Exact normalized affine-AL guide on the whole real line. It is a proposal,
# never a replacement for the normalized future AL law or member factors.
# Generated-only algebra: no original payload access or native qualification.
gaag_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS affine AL guide: ",why),call.=FALSE)
  invisible(TRUE)
}
gaag_hash <- function(x) digest::digest(x,algo="sha256",serialize=TRUE)
gaag_lse <- function(x) { a<-max(x);if(a==-Inf)return(-Inf);a+log(sum(exp(x-a))) }
gaag_logdiff <- function(a,b) {
  gaag_require(!is.na(a)&&!is.na(b)&&a>=b,"invalid ordered log probability difference")
  if(b==-Inf)return(a)
  if(a==b)return(-Inf)
  a+log(-expm1(b-a))
}
gaag_log_kernel <- function(y,data) vapply(y,function(x) {
  e<-data$a*x+data$b
  sum(log(data$probability)+log1p(-data$probability)-log(data$scales)-
    e*(data$probability-(e<0))/data$scales)
},numeric(1L))
gaag_code <- function() lapply(list(gaag_log_kernel,gaag_lse,gaag_logdiff,gaag_interval_quantile,
  gaag_quantile_impl,gaag_cdf_impl),function(fn)list(formals=deparse(formals(fn)),body=deparse(body(fn))))
gaag_payload <- function(proposal) proposal[setdiff(names(proposal),"value_sha256")]

gaag_build <- function(mu,sigma_y,members=numeric(),offset=0,lag=0,sigma_g=1,probability=.2) {
  q<-gaag_require
  scalar<-function(x)is.numeric(x)&&length(x)==1L&&is.finite(x)
  q(requireNamespace("digest",quietly=TRUE),"digest required for immutable value/code seals")
  q(all(vapply(list(mu,sigma_y,probability),scalar,logical(1L)))&&sigma_y>0&&
    probability>0&&probability<1&&is.numeric(members)&&length(members)%in%c(0L,1L,51L)&&
    all(is.finite(members)),"proper AL law and zero, one or all 51 finite members required")
  M<-length(members)
  expand<-function(x,positive=FALSE){q(is.numeric(x)&&length(x)%in%c(1L,M)&&all(is.finite(x))&&
    (!positive||all(x>0)),"finite aligned offsets/lags/positive scales required");rep_len(x,M)}
  offset<-expand(offset);lag<-expand(lag);sigma_g<-expand(sigma_g,TRUE)
  data<-list(a=c(1,-lag),b=c(-mu,members-offset),scales=c(sigma_y,sigma_g),probability=probability)
  roots<- -data$b[data$a!=0]/data$a[data$a!=0]
  q(all(is.finite(roots)),"affine knots are not representable; no truncation permitted")
  knots<-sort(unique(roots));boundary<-c(-Inf,knots,Inf)
  logk<-function(y)gaag_log_kernel(y,data)
  intervals<-lapply(seq_len(length(boundary)-1L),function(i){
    lo<-boundary[i];hi<-boundary[i+1L]
    negative<-data$b<0;nonzero<-data$a!=0
    zero<- -data$b[nonzero]/data$a[nonzero]
    negative[nonzero]<-ifelse(data$a[nonzero]>0,hi<=zero,lo>=zero)
    rate<- -sum(data$a*(probability-negative)/data$scales)
    q(is.finite(rate),"nonrepresentable affine log-density slope")
    if(!is.finite(lo)){
      q(rate>0,"left tail is improper");mass<-logk(hi)-log(rate);mean<-hi-1/rate
    }else if(!is.finite(hi)){
      q(rate<0,"right tail is improper");mass<-logk(lo)-log(-rate);mean<-lo-1/rate
    }else{
      width<-hi-lo;q(is.finite(width)&&width>0,"interval width is not representable")
      z<-abs(rate)*width
      if(rate==0||z==0){mass<-logk(lo)+log(width);mean<-lo+width/2
      }else{
        anchor<-if(rate>0)hi else lo
        mass<-logk(anchor)+log(-expm1(-z))-log(abs(rate))
        distance<-if(z<1e-4)width*(.5-z/12+z^3/720-z^5/30240) else
          1/abs(rate)-if(z>700)0 else width/expm1(z)
        mean<-if(rate>0)hi-distance else lo+distance
      }
    }
    q(is.finite(mass)&&is.finite(mean),"nonrepresentable exact interval mass or mean")
    data.frame(lower=lo,upper=hi,rate=rate,log_mass=mass,conditional_mean=mean)
  })
  intervals<-do.call(rbind,intervals);logZ<-gaag_lse(intervals$log_mass)
  intervals$log_probability<-intervals$log_mass-logZ
  intervals$log_cumulative<-vapply(seq_len(nrow(intervals)),function(i)
    gaag_lse(intervals$log_mass[seq_len(i)])-logZ,numeric(1L))
  intervals$log_cumulative[nrow(intervals)]<-0 # exact normalized sum identity
  proposal<-list(schema_version="glofas_generated_affine_AL_guide_v1",data=data,
    inputs=list(mu=mu,sigma_y=sigma_y,members=members,offset=offset,lag=lag,sigma_g=sigma_g),
    knots=knots,intervals=intervals,log_normalizer=unname(logZ),
    mean=sum(exp(intervals$log_probability)*intervals$conditional_mean),
    member_factors=M,member_weights=rep(1,M),code_sha256=gaag_hash(gaag_code()),
    support="entire_real_line_no_truncation",proposal_only=TRUE,
    reference_qualified=FALSE,production_qualified=FALSE,native_launch_authorized=FALSE,
    original_reads=0L,application_fits=0L)
  proposal$value_sha256<-gaag_hash(gaag_payload(proposal))
  gaag_assert(proposal)
  proposal
}
gaag_assert <- function(proposal) {
  q<-gaag_require
  q(is.list(proposal)&&identical(proposal$schema_version,"glofas_generated_affine_AL_guide_v1")&&
    identical(proposal$proposal_only,TRUE)&&identical(proposal$production_qualified,FALSE)&&
    identical(proposal$native_launch_authorized,FALSE)&&identical(proposal$member_weights,rep(1,proposal$member_factors)),
    "sealed proposal-only object required")
  q(identical(proposal$code_sha256,gaag_hash(gaag_code())),"guide evaluator/source fingerprint changed")
  q(identical(proposal$value_sha256,gaag_hash(gaag_payload(proposal))),"guide values or normalizer changed")
  invisible(TRUE)
}
gaag_log_density <- function(proposal,y) {
  gaag_assert(proposal)
  gaag_require(is.numeric(y)&&!anyNA(y),"numeric nonmissing density arguments required")
  result<-rep(-Inf,length(y));finite<-is.finite(y)
  result[finite]<-gaag_log_kernel(y[finite],proposal$data)-proposal$log_normalizer
  result
}
gaag_interval_quantile <- function(lo,hi,rate,logu,log1mu) {
  if(logu==-Inf)return(lo)
  if(log1mu==-Inf)return(hi)
  if(!is.finite(lo))return(hi+logu/rate)
  if(!is.finite(hi))return(lo+log1mu/rate)
  width<-hi-lo;z<-abs(rate)*width
  if(rate==0||z==0)return(lo+width*exp(logu))
  if(rate>0){
    if(z<.5)return(lo+log1p(exp(logu)*expm1(z))/rate)
    hi+gaag_lse(c(logu,log1mu-z))/rate
  }else{
    if(z<.5)return(lo+log1p(-exp(logu)*(-expm1(-z)))/rate)
    lo+gaag_lse(c(log1mu,logu-z))/rate
  }
}
gaag_quantile_impl <- function(proposal,u) {
  gaag_require(is.numeric(u)&&!anyNA(u)&&all(is.finite(u))&&all(u>=0&u<=1),"probabilities must lie in [0,1]")
  tab<-proposal$intervals
  vapply(u,function(value){
    if(value==0)return(-Inf)
    if(value==1)return(Inf)
    lu<-log(value);i<-which(lu<=tab$log_cumulative)[1L]
    gaag_require(!is.na(i),"normalized guide interval could not be located")
    before<-if(i==1L)-Inf else tab$log_cumulative[i-1L]
    logv<-gaag_logdiff(lu,before)-tab$log_probability[i]
    log1mv<-gaag_logdiff(tab$log_cumulative[i],lu)-tab$log_probability[i]
    gaag_interval_quantile(tab$lower[i],tab$upper[i],tab$rate[i],logv,log1mv)
  },numeric(1L))
}
gaag_quantile <- function(proposal,u){gaag_assert(proposal);gaag_quantile_impl(proposal,u)}
gaag_cdf_impl <- function(proposal,y) {
  gaag_require(is.numeric(y)&&!anyNA(y),"numeric nonmissing CDF arguments required")
  tab<-proposal$intervals
  vapply(y,function(value){
    if(value==-Inf)return(0)
    if(value==Inf)return(1)
    terms<-vapply(seq_len(nrow(tab)),function(i){
      lo<-tab$lower[i];hi<-tab$upper[i];r<-tab$rate[i]
      if(value<=lo)return(-Inf)
      if(value>=hi)return(tab$log_probability[i])
      fraction<-if(!is.finite(lo))exp(r*(value-hi)) else if(!is.finite(hi)) -expm1(r*(value-lo)) else {
        width<-hi-lo;z<-abs(r)*width
        if(r==0||z==0)(value-lo)/width else if(z<.5)expm1(r*(value-lo))/expm1(r*width) else
          if(r>0)exp(r*(value-hi))*(-expm1(-r*(value-lo)))/(-expm1(-z)) else
            (-expm1(r*(value-lo)))/(-expm1(-z))
      }
      tab$log_probability[i]+log(fraction)
    },numeric(1L))
    exp(gaag_lse(terms))
  },numeric(1L))
}
gaag_cdf <- function(proposal,y){gaag_assert(proposal);gaag_cdf_impl(proposal,y)}
gaag_sample <- function(proposal,n,seed) {
  gaag_assert(proposal)
  gaag_require(is.numeric(n)&&length(n)==1L&&is.finite(n)&&n==floor(n)&&n>=1&&n<=100000L&&
    is.numeric(seed)&&length(seed)==1L&&is.finite(seed)&&seed==floor(seed)&&seed>0&&seed<=.Machine$integer.max,
    "bounded sample count and explicit positive seed required")
  oldkind<-RNGkind();oldseed<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  on.exit({do.call(RNGkind,as.list(oldkind));if(is.null(oldseed)){
    if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)
  }else assign(".Random.seed",oldseed,.GlobalEnv)},add=TRUE)
  RNGkind("Mersenne-Twister","Inversion","Rejection");set.seed(as.integer(seed))
  samples<-gaag_quantile_impl(proposal,stats::runif(as.integer(n)))
  gaag_require(all(is.finite(samples)),"sample is not representable; no clamp or truncation permitted")
  list(samples=samples,log_q=gaag_log_density(proposal,samples),log_normalizer=proposal$log_normalizer,
    proposal_only=TRUE,production_qualified=FALSE,native_launch_authorized=FALSE)
}
gaag_as_guide <- function(proposal) {
  gaag_assert(proposal)
  # Copy the validated functions and immutable value data into a locked private
  # environment, so draw/logq do not inherit mutable caller implementations.
  private<-new.env(parent=baseenv());private$proposal<-proposal
  helpers<-list(gaag_require=gaag_require,gaag_lse=gaag_lse,gaag_logdiff=gaag_logdiff,
    gaag_log_kernel=gaag_log_kernel,gaag_interval_quantile=gaag_interval_quantile,
    gaag_quantile_impl=gaag_quantile_impl,gaag_cdf_impl=gaag_cdf_impl)
  for(name in names(helpers)){fn<-helpers[[name]];environment(fn)<-private;assign(name,fn,private)}
  draw<-eval(quote(function(u)gaag_quantile_impl(proposal,u)),private)
  log_density<-eval(quote(function(y){
    gaag_require(is.numeric(y)&&!anyNA(y),"numeric nonmissing density arguments required")
    result<-rep(-Inf,length(y));finite<-is.finite(y)
    result[finite]<-gaag_log_kernel(y[finite],proposal$data)-proposal$log_normalizer
    result
  }),private)
  lockEnvironment(private,bindings=TRUE)
  list(draw=draw,log_density=log_density,log_normalizer=proposal$log_normalizer,
    proposal_only=TRUE,production_qualified=FALSE,native_launch_authorized=FALSE)
}
