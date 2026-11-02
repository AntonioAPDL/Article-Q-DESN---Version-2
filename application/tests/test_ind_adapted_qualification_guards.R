# Source/metadata/synthetic checks only: no authentic input or numerical purpose.
source("scripts/qualify_ind_adapted_filter.R")
source("scripts/ind_adapted_auxiliary_filter.R")
aq_n <- 0L
aq_check <- function(x){stopifnot(isTRUE(x));aq_n <<- aq_n+1L}
aq_reject <- function(x,text=NULL) {
  e <- tryCatch({force(x);NULL},error=identity)
  aq_check(inherits(e,"error")&&(is.null(text)||grepl(text,conditionMessage(e),fixed=TRUE)))
}
had_rng <- exists(".Random.seed",.GlobalEnv,inherits=FALSE)
if(had_rng)old_rng <- .Random.seed
pin <- function(sha,n=0)list(path="/not-an-authentic-input",size_bytes=n,sha256=sha)
s <- list(schema_version="ind_ancestor_first_filter_qualification_v1",allow_qualification=TRUE,
  allow_refit=FALSE,allow_production=FALSE,allow_scoring=FALSE,allow_article_promotion=FALSE,
  method="ancestor_first_AL_exact_v_v1",rng_namespace="ind_ancestor_first_AL_training_H1_v1",
  rng_layout="Mersenne_Twister_time_major_proposal4_then_ancestor_then_residual_v1",
  posterior_column=1L,observed_prefix_length=500L,particle_resolutions=c(64L,256L,1024L),
  seeds=c(71521L,71522L),checkpoint_indices=c(100L,250L,500L),probabilities=c(.05,.5,.95),
  ess_fraction=.5,inversion_absolute_tolerance=1e-8,
  agreement_absolute_tolerance=.005,agreement_relative_tolerance=.005,
  limits=list(cpu_seconds=1800L,wall_term_seconds=1799L,wall_kill_after_seconds=1L,
    address_space_bytes=16*1024^3,output_bytes=96*1024^2),
  training_input=pin("d38bd5f49744c67861908f8fd960781bf97efdf1c43473829b46894574252496",13728),
  native_forward_receipt=pin("440da6c4d71554952947b128c77758f86aea385c7cb3ceb203ddad5ff5737bff"),
  bootstrap_receipt=pin("b14b6ea359d6f48f37134d40e87ca2d37f8dd33d954c5c59f479352fa495e599"),
  historical_guided_receipt=pin("ce2b82b96b57de42cedd3f856f5f630e4f9387d70d9219edb47db28b64a1a2b2"),
  original_fit=pin("1e8ba3de4a6c9e9e0f6bd900be7801e8c80fe0fdff4b6ca24804bdc62e3ff17f",611287756),
  native_cpp=pin("f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065"),
  source_commit=paste(rep("0",40),collapse=""),source_tree=paste(rep("0",40),collapse=""))
aq_check(isTRUE(ind_aq_scope(s)))
for(k in c("allow_refit","allow_production","allow_scoring","allow_article_promotion")) {
  x <- s;x[[k]] <- TRUE;aq_reject(ind_aq_scope(x),"qualification-only")
}
for(k in c("posterior_column","observed_prefix_length","ess_fraction","inversion_absolute_tolerance",
  "agreement_absolute_tolerance","agreement_relative_tolerance")) {
  x <- s;x[[k]] <- x[[k]]+.0001;aq_reject(ind_aq_scope(x),"fixed new-purpose")
}
for(k in c("seeds","particle_resolutions","checkpoint_indices","probabilities")) {
  x <- s;x[[k]][1L] <- x[[k]][1L]+1;aq_reject(ind_aq_scope(x),"fixed new-purpose")
}
for(k in c("method","rng_namespace","rng_layout")) {
  x <- s;x[[k]] <- "old-purpose-relabel";aq_reject(ind_aq_scope(x),"fixed new-purpose")
}
for(k in names(s$limits)) {
  x <- s;x$limits[[k]] <- x$limits[[k]]+1;aq_reject(ind_aq_scope(x),"fixed finite")
}
for(k in c("training_input","native_forward_receipt","bootstrap_receipt","historical_guided_receipt","original_fit","native_cpp")) {
  x <- s;x[[k]]$sha256 <- paste(rep("0",64),collapse="");aq_reject(ind_aq_scope(x),"frozen original")
}
argv <- c("/usr/bin/timeout","--signal=TERM","--kill-after=1s","1799s","Rscript","--vanilla")
aq_check(isTRUE(ind_aq_timeout_argv(argv)))
for(bad in list(c("timeout","1799s","Rscript"),
  c("timeout","--signal=TERM","--kill-after=2s","1799s","Rscript"),
  c("timeout","--signal=TERM","--kill-after=1s","1800s","Rscript"),
  c("timeout","--signal=KILL","--kill-after=1s","1799s","Rscript"),
  c("timeout","--signal=TERM","--kill-after=1s","1799s","--foreground")))
  aq_reject(ind_aq_timeout_argv(bad),"exact native timeout")

# Default GNU timeout creates its own process group, not necessarily a new
# session. A setsid/setpgid payload must not evade its TERM/KILL group.
proc_stat <- function(pid,ppid,pgid,sid,comm="R")
  sprintf("%d (%s) S %d %d %d 0 0 0 0",pid,comm,ppid,pgid,sid)
timeout_stat <- proc_stat(200L,100L,200L,90L,"timeout")
self_stat <- proc_stat(201L,200L,200L,90L,"R ) with embedded ) name")
proof <- ind_aq_process_group_proof(self_stat,timeout_stat)
aq_check(identical(proof$payload_pid,201L)&&identical(proof$timeout_pid,200L)&&
  isTRUE(proof$timeout_process_group_leader)&&isTRUE(proof$payload_same_timeout_group_and_session))
aq_check(identical(ind_aq_proc_stat(self_stat),list(pid=201L,ppid=200L,pgid=200L,sid=90L)))
aq_reject(ind_aq_process_group_proof(proc_stat(201L,200L,201L,90L),timeout_stat),"process group and session")
aq_reject(ind_aq_process_group_proof(proc_stat(201L,200L,200L,201L),timeout_stat),"process group and session")
aq_reject(ind_aq_process_group_proof(proc_stat(201L,200L,201L,201L),timeout_stat),"process group and session")
aq_reject(ind_aq_process_group_proof(self_stat,proc_stat(200L,100L,100L,90L)),"lead its controlled process group")
aq_reject(ind_aq_process_group_proof(timeout_stat,timeout_stat),"process group and session")
for(bad in c("not a stat record","201 (R) S 200 200","201 (R) S 200 0 90",
  "0 (R) S 200 200 90","201 (R) S 200 200 0","2147483648 (R) S 200 200 90"))
  aq_reject(ind_aq_proc_stat(bad))

runtime <- data.frame(path=c("/runtime/a","/runtime/b"),size_bytes=c(1,2),
  sha256=c(paste(rep("a",64),collapse=""),paste(rep("b",64),collapse="")))
aq_check(isTRUE(ind_aq_runtime_match(runtime,runtime)))
aq_check(isTRUE(ind_aq_strict_mappings_present(runtime$path,c(TRUE,TRUE),c(FALSE,FALSE))))
aq_reject(ind_aq_strict_mappings_present(runtime$path,c(TRUE,FALSE),c(FALSE,NA)),"strict mapped file")
aq_reject(ind_aq_strict_mappings_present(runtime$path,c(TRUE,TRUE),c(FALSE,TRUE)),"strict mapped file")
aq_reject(ind_aq_strict_mappings_present(runtime$path,c(TRUE,TRUE),c(FALSE,NA)),"strict mapped file")
aq_reject(ind_aq_strict_mappings_present(runtime$path,TRUE,FALSE),"strict mapped file")
for(mut in list(function(x){x<-x[2:1,];x},function(x){x$sha256[1]<-"bad";x},
  function(x){x$size_bytes[1]<-99;x},function(x){x$path[1]<-x$path[2];x},
  function(x){x<-x[-1L,];x}))aq_reject(ind_aq_runtime_match(runtime,mut(runtime)),"runtime/package")

changed_observation <- runtime
attr(changed_observation,"observational_os_state") <- list(path=runtime_ic_paths(),observed_sha256="different_live_OS_bytes")
aq_check(isTRUE(ind_aq_runtime_match(runtime,changed_observation)))
changed_software <- changed_observation;changed_software$sha256[1] <- strrep("c",64L)
aq_reject(ind_aq_runtime_match(runtime,changed_software),"runtime/package")

eta <- list(family="al",p=.05,sigma=.7,gamma=0)
A <- (1-2*.05)/(.05*.95);B <- 2/(.05*.95)
input <- list(y=rep(0,500),FF=matrix(rep(c(1,0,1,0,1,0),500),6L),GG=diag(6L),
  m0=rep(0,6),C0=diag(6L),df_mat=diag(rep(.2,6)),ex_f=rep(A,500),
  ex_q=rep(B*.7,500),observed_prefix_length=500L)
aq_check(isTRUE(ind_aq_truth_free_input(input,eta)))
array_input <- input;array_input$GG <- array(rep(diag(6),500),c(6L,6L,500L))
aq_check(isTRUE(ind_aq_truth_free_input(array_input,eta)))
for(mut in list(function(x){x$future_truth<-rep(1,30);x},function(x){x$y<-c(x$y,1);x},
  function(x){x<-c(x,list(y=rep(99,30)));x},
  function(x){x$observed_prefix_length<-501;x},function(x){x$FF[1,2]<-2;x},
  function(x){x$GG<-array(1,c(6,6,499));x},function(x){x$ex_f[1]<-x$ex_f[1]+1;x},
  function(x){x$ex_q[1]<-0;x},function(x){x$C0[1,1]<--1;x}))aq_reject(ind_aq_truth_free_input(mut(input),eta))
bad <- array_input;bad$GG[1,1,499] <- 3
aq_reject(ind_aq_truth_free_input(bad,eta),"constant training G")

# Wrong SHA/source fail before any scientific RDS can be reached.
tmp <- tempfile("ind-aq-synthetic-");dir.create(tmp)
f <- file.path(tmp,"purpose.json")
jsonlite::write_json(s,f,auto_unbox=TRUE,digits=17)
sha <- unname(tools::sha256sum(f))
aq_reject(ind_aq_main(c("--contract",f,"--sha256",paste(rep("0",64),collapse=""),"--execute")),"purpose contract SHA")
aq_reject(ind_aq_main(c("--contract",f,"--sha256",sha,"--execute")),"clean frozen source/tree")
aq_reject(ind_aq_main(character()),"exact contract/hash")
text <- file.path(tmp,"text-only.txt");writeLines("synthetic metadata",text)
p <- list(path=text,size_bytes=file.info(text)$size,sha256=unname(tools::sha256sum(text)))
aq_check(identical(ind_aq_pin(p),text))
bad <- p;bad$size_bytes <- p$size_bytes+1;aq_reject(ind_aq_pin(bad),"file bytes changed")
link <- file.path(tmp,"linked.txt");invisible(file.symlink(text,link))
bad <- p;bad$path <- link;aq_reject(ind_aq_pin(bad),"nonsymlink")
unlink(tmp,recursive=TRUE)
help <- capture.output(ind_aq_main("--help"));aq_check(length(help)==1L&&grepl("--vanilla",help,fixed=TRUE))
aq_check(identical(exists(".Random.seed",.GlobalEnv,inherits=FALSE),had_rng))
if(had_rng)aq_check(identical(.Random.seed,old_rng))
cat(sprintf("IND_ADAPTED_QUALIFICATION_GUARDS=%d PASS; authentic_reads=0 scientific_runs=0\n",aq_n))
