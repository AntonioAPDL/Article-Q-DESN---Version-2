# Generated affine products only. No retained application object is accessed.
local({
  source("scripts/diagnostics/glofas_al_affine_guided_proposal.R",local=TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R",local=TRUE)
  checks<-0L
  ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L}
  reject<-function(expr)ok(inherits(try(force(expr),silent=TRUE),"try-error"))
  literal<-function(y,mu,sy,members,offset,lag,sg,p)vapply(y,function(x)
    gcpr_log_al(x,mu,p,sy)+sum(gcpr_log_al(members,offset+lag*x,p,sg)),numeric(1L))
  split_integral<-function(fun,knots){cuts<-c(-Inf,sort(unique(knots)),Inf)
    sum(vapply(seq_len(length(cuts)-1L),function(i)stats::integrate(fun,cuts[i],cuts[i+1L],
      rel.tol=1e-9,abs.tol=1e-11,subdivisions=500L)$value,numeric(1L)))}
  members<-seq(.1,.3,length.out=51L)
  u<-c(1e-14,.0001,.01,.05,.2,.5,.8,.95,.9999,1-1e-14)
  fixtures<-list()
  for(p in c(.05,.2,.5,.8,.95))for(lag in c(-.35,0,.35)){
    mu<-.1;sy<-.5;offset<-.2;sg<-1
    proposal<-gaag_build(mu,sy,members,offset,lag,sg,p)
    independent<-gcpr_piecewise(c(1,rep(-lag,51)),c(-mu,members-offset),c(sy,rep(sg,51)),p)
    ok(abs(proposal$log_normalizer-independent$log_integral)<1e-10&&
      abs(proposal$mean-independent$mean)<1e-9)
    q<-gaag_quantile(proposal,u)
    ok(all(is.finite(q))&&all(diff(q)>0)&&max(abs(gaag_cdf(proposal,q)-u))<1e-10)
    points<-c(proposal$knots[1L]-2,proposal$knots,tail(proposal$knots,1)+2)
    ok(max(abs(gaag_log_density(proposal,points)-
      (literal(points,mu,sy,members,offset,lag,sg,p)-proposal$log_normalizer)))<1e-10)
    if(p==.2){
      f<-function(x)exp(literal(x,mu,sy,members,offset,lag,sg,p)-proposal$log_normalizer)
      norm<-split_integral(f,proposal$knots)
      mean<-split_integral(function(x)x*f(x),proposal$knots)
      ok(abs(norm-1)<1e-9&&abs(mean-proposal$mean)<1e-8)
      fixtures[[as.character(lag)]]<-proposal
    }
  }
  # Member-specific offsets/scales and mixed slope signs retain every factor.
  offset<-seq(-.1,.2,length.out=51L);lag<-rep(c(-.2,0,.3),17L);sg<-seq(.7,1.3,length.out=51L)
  varied<-gaag_build(.1,.5,members,offset,lag,sg,.2)
  independent<-gcpr_piecewise(c(1,-lag),c(-.1,members-offset),c(.5,sg),.2)
  ok(abs(varied$log_normalizer-independent$log_integral)<1e-10&&varied$member_factors==51L&&
    all(varied$member_weights==1))
  ok(max(abs(gaag_cdf(varied,gaag_quantile(varied,u))-u))<1e-10)
  empty<-gaag_build(.1,.5,probability=.2)
  constant<-gaag_build(.1,.5,members,.2,0,1,.2)
  points<-c(-5,-.1,.1,.5,5)
  ok(abs(empty$log_normalizer)<1e-12&&
    max(abs(gaag_log_density(empty,points)-gcpr_log_al(points,.1,.2,.5)))<1e-12)
  ok(abs(constant$log_normalizer-sum(gcpr_log_al(members,.2,.2,1)))<1e-10&&
    max(abs(gaag_log_density(constant,points)-gcpr_log_al(points,.1,.2,.5)))<1e-10)
  # An exactly flat interior interval is sampled as uniform, with both tails.
  flat<-gaag_build(0,1,1,offset=0,lag=1,sigma_g=1,probability=.5)
  ok(any(flat$intervals$rate==0)&&abs(flat$mean-.5)<1e-12&&
    max(abs(gaag_cdf(flat,gaag_quantile(flat,u))-u))<1e-10)
  ok(identical(gaag_quantile(flat,c(0,1)),c(-Inf,Inf))&&
    identical(gaag_cdf(flat,c(-Inf,Inf)),c(0,1))&&
    all(gaag_log_density(flat,c(-Inf,Inf))==-Inf))
  ok(gaag_quantile(flat,1e-300)<min(flat$knots)-100&&
    gaag_quantile(flat,1-1e-14)>max(flat$knots)+10)

  proposal<-fixtures[["0.35"]];guide<-gaag_as_guide(proposal)
  guide_before_mutation<-guide$draw(u)
  ok(identical(guide$draw(u),gaag_quantile(proposal,u))&&
    identical(guide$log_density(points),gaag_log_density(proposal,points))&&
    identical(guide$log_normalizer,proposal$log_normalizer))
  oldkind<-RNGkind();oldseed<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  on.exit({do.call(RNGkind,as.list(oldkind));if(is.null(oldseed)){
    if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)
  }else assign(".Random.seed",oldseed,.GlobalEnv)},add=TRUE)
  set.seed(2026110513L);before<-get(".Random.seed",.GlobalEnv);kind<-RNGkind()
  draw<-gaag_sample(proposal,4096L,2026110517L)
  ok(identical(before,get(".Random.seed",.GlobalEnv))&&identical(kind,RNGkind()))
  ok(identical(draw,gaag_sample(proposal,4096L,2026110517L))&&all(is.finite(draw$samples))&&
    max(abs(draw$log_q-gaag_log_density(proposal,draw$samples)))<1e-12)
  variance<-split_integral(function(x)(x-proposal$mean)^2*
    exp(literal(x,.1,.5,members,.2,.35,1,.2)-proposal$log_normalizer),proposal$knots)
  ok(abs(mean(draw$samples)-proposal$mean)<5*sqrt(variance/4096))
  ok(!draw$production_qualified&&!draw$native_launch_authorized&&draw$proposal_only)
  guide$draw(u);guide$log_density(points)
  ok(identical(before,get(".Random.seed",.GlobalEnv)))
  rm(".Random.seed",envir=.GlobalEnv)
  gaag_sample(proposal,4L,2026110519L)
  ok(!exists(".Random.seed",.GlobalEnv,inherits=FALSE)&&identical(kind,RNGkind()))
  assign(".Random.seed",before,.GlobalEnv)
  reject(gaag_sample(proposal,1.5,1));reject(gaag_sample(proposal,2,0))
  ok(identical(before,get(".Random.seed",.GlobalEnv)))
  bad<-proposal;bad$log_normalizer<-bad$log_normalizer+1
  reject(gaag_assert(bad));reject(gaag_as_guide(bad));reject(gaag_sample(bad,4,1))
  bad<-proposal;bad$inputs$members[1L]<-2;reject(gaag_as_guide(bad))
  bad<-proposal;bad$intervals$rate[1L]<- -1;reject(gaag_quantile(bad,.5))
  bad<-proposal;bad$member_weights[1L]<-1/51;reject(gaag_log_density(bad,0))
  oldfunction<-gaag_interval_quantile
  gaag_interval_quantile<-function(...)0
  reject(gaag_as_guide(proposal));reject(gaag_log_density(proposal,0))
  ok(identical(guide$draw(u),guide_before_mutation)) # Existing private guide stays frozen.
  gaag_interval_quantile<-oldfunction
  reject(gaag_quantile(proposal,NA_real_));reject(gaag_quantile(proposal,-.1))
  reject(gaag_build(.1,0,members,.2,.3,1,.2))
  reject(gaag_build(.1,.5,members,c(0,1),.3,1,.2))
  reject(gaag_build(.1,.5,members,.2,.3,-1,.2))
  reject(gaag_build(.1,.5,members,.2,.3,1,1))
  reject(gaag_build(.1,.5,c(members[-1L],Inf),.2,.3,1,.2))
  cat(sprintf("GLOFAS_AL_AFFINE_GUIDED_PROPOSAL_PASS checks=%d original_reads=0 application_fits=0\n",checks))
})
