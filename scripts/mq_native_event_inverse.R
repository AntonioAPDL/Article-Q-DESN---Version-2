# Explicit generated-only candidate. All canonical defaults remain unchanged.
mqe_require<-function(ok,why)if(!isTRUE(ok))stop(paste0("MQ event candidate: ",why),call.=FALSE)
mqe_scope<-function(scope)mqe_require(identical(scope,"generated_fixture_only"),
 "source/runtime qualification and production admission are not provided")
mqe_load<-function(path,sha256,scope="NOT_ADMITTED") {
 mqe_scope(scope)
 mqe_require(is.character(path)&&length(path)==1L&&!is.na(path)&&startsWith(path,"/")&&
  file.exists(path)&&!dir.exists(path)&&!nzchar(Sys.readlink(path))&&
  identical(normalizePath(path,mustWork=TRUE),path)&&file.info(path)$size>0&&file.info(path)$size<8*1024^2&&
  is.character(sha256)&&length(sha256)==1L&&!is.na(sha256)&&grepl("^[a-f0-9]{64}$",sha256)&&
  identical(unname(tools::sha256sum(path)),sha256),"canonical bounded pinned generated DLL required")
 dll<-dyn.load(path,local=TRUE,now=TRUE);complete<-FALSE
 on.exit(if(!complete)dyn.unload(path),add=TRUE)
 mqe_require(identical(dll[["dynamicLookup"]],FALSE),"registered symbols required")
 scan<-getNativeSymbolInfo("mqe_first_indices",PACKAGE=dll)
 cdf<-getNativeSymbolInfo("mqe_cdf_values",PACKAGE=dll)
 mqe_require(identical(scan$numParameters,2L)&&identical(cdf$numParameters,3L)&&
  identical(unname(tools::sha256sum(path)),sha256),"native signature/bytes changed")
 complete<-TRUE
 structure(list(dll=dll,scan=scan,cdf=cdf,sha256=sha256,scope=scope,
  source_authentication_provided=FALSE,production_authorized=FALSE),class="mq_event_generated_candidate_v1")
}
mqe_handle<-function(candidate,scope) {
 mqe_scope(scope)
 mqe_require(inherits(candidate,"mq_event_generated_candidate_v1")&&
  identical(candidate$scope,"generated_fixture_only")&&identical(candidate$production_authorized,FALSE)&&
  inherits(candidate$scan,"NativeSymbolInfo")&&inherits(candidate$cdf,"NativeSymbolInfo"),
  "explicit generated candidate handle required")
}
mqe_cdf<-function(y,q,tau,candidate,scope="NOT_ADMITTED") {
 mqe_handle(candidate,scope)
 mqe_require(is.matrix(q)&&typeof(q)%in%c("double","integer")&&
  typeof(tau)%in%c("double","integer")&&typeof(y)%in%c("double","integer"),
  "real integer/double matrix/grid/queries required")
 if(typeof(q)!="double")storage.mode(q)<-"double"
 values<-.Call(candidate$cdf,q,as.double(tau),as.double(y))
 # Preserve R mean's extended-precision accumulation/correction; colMeans or
 # a new double C accumulator is NOT an interchangeable replacement.
 out<-vapply(seq_along(y),function(j)mean(values[,j]),numeric(1L));names(out)<-names(y);out
}
mqe_inverse<-function(q,tau,probabilities,candidate,tolerance=1e-8,
 scope="NOT_ADMITTED",cdf_backend="native_values_R_mean",return_receipt=FALSE) {
 mqe_handle(candidate,scope)
 mqe_require(cdf_backend%in%c("native_values_R_mean","unchanged_reference")&&
  is.logical(return_receipt)&&length(return_receipt)==1L&&!is.na(return_receipt),"explicit candidate options required")
 req<-mqe_require
 req(is.matrix(q)&&typeof(q)%in%c("double","integer")&&nrow(q)>=1L&&nrow(q)<=262144L&&ncol(q)>=2L&&ncol(q)<=64L&&
  all(is.finite(q))&&typeof(tau)%in%c("double","integer")&&length(tau)==ncol(q)&&
  typeof(probabilities)%in%c("double","integer")&&
  length(probabilities)>=1L&&length(probabilities)<=64L&&all(is.finite(probabilities))&&
  all(probabilities>0&probabilities<1)&&typeof(tolerance)%in%c("double","integer")&&length(tolerance)==1L&&
  is.finite(tolerance)&&tolerance>0,"bounded native geometry/probabilities/tolerance required")
 app_iqf_grid(rep(0,ncol(q)),tau)
 L<-nrow(q);K<-ncol(q);tau<-as.numeric(tau);original_q<-q
 crossed<-which(rowSums(q[,-1L,drop=FALSE]<q[,-K,drop=FALSE])>0L)
 for(i in crossed)q[i,]<-stats::isoreg(seq_len(K),q[i,])$yf
 finish<-function(answer,fallback,reason)if(return_receipt)list(quantile=answer,fallback=fallback,
  reason=reason,source_authentication_provided=FALSE,production_authorized=FALSE)else answer
 fallback<-function(reason) {
  kernels<-lapply(seq_len(L),function(i)list(family="mq_grid",q=as.numeric(original_q[i,]),tau=tau))
  finish(app_iqf_invert_cdf_bisection(kernels,probabilities,tolerance),TRUE,reason)
 }
 # These expressions, event order, sort/rowsum and BOTH R cumsums are retained
 # verbatim in arithmetic from app_iqf_mq_matrix_inverse. R cumsum uses LDOUBLE
 # on this build; a native sequential-double replacement would not be exact.
 width<-q[,-1L,drop=FALSE]-q[,-K,drop=FALSE]
 mass<-matrix(rep(diff(tau),each=L),nrow=L);positive<-width>0
 density<-matrix(0,nrow=L,ncol=K-1L);density[positive]<-mass[positive]/width[positive]
 events<-cbind(position=c(q[,1L],q[,K],q[,-K,drop=FALSE],q[,-1L,drop=FALSE]),
  slope_change=c(rep(0,2L*L),density,-density)/L,
  atom=c(rep(tau[1L],L),rep(1-tau[K],L),ifelse(positive,0,mass),rep(0,length(mass)))/L)
 if(any(!is.finite(events)))return(fallback("nonfinite_events"))
 knots<-sort(unique(events[,"position"]))
 grouped<-rowsum(events[,c("slope_change","atom"),drop=FALSE],match(events[,"position"],knots),reorder=TRUE)
 slope<-cumsum(grouped[,"slope_change"])
 interval_mass<-if(length(knots)>1L)head(slope,-1L)*diff(knots)else numeric()
 if(any(!is.finite(interval_mass))||any(interval_mass< -1e-12))return(fallback("interval_mass"))
 interval_mass<-pmax(0,interval_mass)
 right<-cumsum(grouped[,"atom"]+c(0,interval_mass));left<-right-grouped[,"atom"]
 if(any(!is.finite(c(left,right)))||any(left< -1e-10)||any(right>1+1e-10)||
  abs(tail(right,1L)-1)>1e-10||any(diff(right)< -1e-12))return(fallback("cdf_event_mass"))
 right<-pmin(1,pmax(0,right));right[length(right)]<-1
 if(length(right)>4000000L)return(fallback("candidate_scan_bound"))
 index<-.Call(candidate$scan,as.double(right),as.double(probabilities))
 # Interpolation and scalar max/min remain R operations, including signed
 # zero and exceptional-value semantics. Only which(...)[1] scans move to C.
 answer<-vapply(seq_along(probabilities),function(i) {
  p<-probabilities[i];j<-index[i]
  if(is.na(j))return(NA_real_)
  if(j==1L||p>left[j])return(knots[j])
  if(!is.finite(slope[j-1L])||slope[j-1L]<=0)return(NA_real_)
  value<-knots[j-1L]+(p-right[j-1L])/slope[j-1L]
  max(knots[j-1L],min(knots[j],value))
 },numeric(1L));names(answer)<-names(probabilities)
 if(any(!is.finite(answer)))return(fallback("unresolved_inverse"))
 probe_y<-c(answer-tolerance,answer+tolerance)
 probe<-if(cdf_backend=="unchanged_reference"||any(!is.finite(probe_y))||as.double(L)*length(probe_y)>8388608)
  app_iqf_mq_matrix_cdf(probe_y,q,tau)else
  mqe_cdf(probe_y,q,tau,candidate,scope)
 n<-length(answer)
 if(any(!is.finite(probe))||any(probe[seq_len(n)]>=probabilities)||
  any(probe[n+seq_len(n)]<probabilities))return(fallback("checked_inverse_probe"))
 finish(answer,FALSE,"native_first_index_and_checked_pointwise_CDF")
}
