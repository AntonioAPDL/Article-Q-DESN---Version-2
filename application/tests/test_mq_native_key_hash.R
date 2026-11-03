#!/usr/bin/env Rscript
# Generated software checks only. Explicit caller-built DLL; never compile,
# discover scientific data, enroll a source or authorize a production route.
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==3L)
dll_path <- args[1L]; dll_sha <- args[2L]; output <- normalizePath(args[3L],mustWork=TRUE)
for (file in c("joint_qvp_qdesn.R","joint_exqdesn_exact_structured_inference.R",
  "latent_path_design.R","joint_qdesn_pure_recursive_campaign.R",
  "joint_qdesn_recursive_mean_design.R","integrated_quantile_forecast.R"))
  source(file.path("application/R",file),keep.source=TRUE)
source("scripts/integrated_quantile_mq_batch.R",keep.source=TRUE)
source("scripts/mq_forecast_array_methods.R",keep.source=TRUE)
source("scripts/mq_native_key_hash.R",keep.source=TRUE)
`%||%` <- function(a,b)if(is.null(a))b else a
mqb_tau <- c(.05,.1,.25,.5,.75,.9,.95);mqb_hash <- strrep("a",64L)
ast <- parse(file="application/tests/test_integrated_quantile_mq_batch.R")
ix <- which(vapply(ast,function(e)is.call(e)&&identical(e[[1L]],as.name("<-"))&&
  identical(e[[2L]],as.name("mqb_fixture")),logical(1L)))
stopifnot(length(ix)==1L);eval(ast[[ix]])
backend <- mqk_load_candidate(dll_path,dll_sha)
proof <- app_iqf_mqb_rng_reference()
set.seed(20261102)
initial_seed <- .Random.seed;initial_kind <- RNGkind()
baseline_body <- deparse(body(app_iqf_mqb_fast_uniforms),width.cutoff=500L)
baseline_formals <- formals(app_iqf_mqb_fast_uniforms)
baseline_environment <- environment(app_iqf_mqb_fast_uniforms)
n <- 0L
check <- function(ok){stopifnot(isTRUE(ok));n<<-n+1L}
reject <- function(expr)check(inherits(tryCatch({force(expr);NULL},error=identity),"error"))
same_rng <- function()check(identical(.Random.seed,initial_seed)&&identical(RNGkind(),initial_kind))
latin <- rawToChar(as.raw(c(99,97,102,233)));Encoding(latin)<-"latin1"
bytes <- rawToChar(as.raw(c(120,255)));Encoding(bytes)<-"bytes"
utf8 <- enc2utf8(latin)
triples <- list(c("namespace","chain1/draw2","origin33"),rep("same",3L),
  c("\u03b1/\u03b2","\u4f8b\u5b50","\u00e9"),c(latin,utf8,bytes),
  c("quote\"/slash\\/newline\n"," draw ","origin"),
  c(strrep("long_",1000L),strrep("d",2048L),strrep("o",512L)))
for (triple in triples) {
  ids <- c(1L,2L,10L,1024L,65536L,.Machine$integer.max)
  audit <- mqk_candidate_uniforms(backend,triple[1L],triple[2L],triple[3L],ids,7L,proof,TRUE)
  reference <- app_iqf_mqb_fast_uniforms(triple[1L],triple[2L],triple[3L],ids,7L,proof)
  check(identical(audit$uniforms,reference))
  for(h in 1:7)for(i in seq_along(ids)) {
    key <- list(version=1L,scientific_identity=as.character(triple[1L]),
      draw=as.character(triple[2L]),origin=as.character(triple[3L]),
      inner=as.character(ids[i]),horizon=as.character(h),purpose="response")
    at <- (h-1L)*length(ids)+i
    raw <- serialize(key,NULL,version=2L)
    check(identical(audit$serialized[[at]],raw))
    hash <- digest::digest(key,algo="sha256",serialize=TRUE,serializeVersion=2L)
    check(identical(audit$digests[i,h],hash))
    check(identical(hash,digest::digest(raw[-seq_len(14L)],algo="sha256",serialize=FALSE)))
    words <- app_iqf_seed(triple[1L],triple[2L],triple[3L],ids[i],h,"response")
    check(identical(as.integer(audit$seed_words[at,]),words))
    native <- app_iqf_rng(words,function()stats::runif(1L))
    check(identical(audit$uniforms[i,h],native))
  }
  same_rng()
}
# Reordered, nonconsecutive and partitioned IDs preserve every original tuple.
ids <- c(501L,1L,21L,4L,19L)
full <- mqk_candidate_uniforms(backend,"generated_partition","draw","origin",ids,30L,proof)
parts <- rbind(mqk_candidate_uniforms(backend,"generated_partition","draw","origin",ids[1:2],30L,proof),
  mqk_candidate_uniforms(backend,"generated_partition","draw","origin",ids[3:5],30L,proof))
check(identical(full,parts))
check(identical(full[,1:3,drop=FALSE],mqk_candidate_uniforms(backend,"generated_partition","draw","origin",ids,3L,proof)))
same_rng()
for (bad in list("",NA_character_,structure("x",class="custom_identity"),c("x","y")))
  reject(mqk_candidate_uniforms(backend,bad,"draw","origin",1L,1L,proof))
for (bad in list(0L,-1L,1.5,NA_real_,Inf,c(1L,1L),as.double(.Machine$integer.max)+1))
  reject(mqk_candidate_uniforms(backend,"ns","draw","origin",bad,1L,proof))
for (bad in list(0L,-1L,1.5,NA_real_,Inf))
  reject(mqk_candidate_uniforms(backend,"ns","draw","origin",1L,bad,proof))
reject(mqk_candidate_uniforms(backend,"ns","draw","origin",1:1024,2L,proof,TRUE))
wrong <- proof;wrong$RNG_c_sha256<-strrep("b",64L)
reject(mqk_candidate_uniforms(backend,"ns","draw","origin",1L,1L,wrong))
reject(mqk_load_candidate(dll_path,strrep("b",64L)))
for (bad in c("version","inner","purpose","extra_attribute")) {
  key<-list(version=1L,scientific_identity="ns",draw="d",origin="o",inner="",horizon="",purpose="response")
  if(bad=="version")key$version<-1
  if(bad=="inner")key$inner<-structure("",class="custom")
  if(bad=="purpose")key$purpose<-"changed"
  if(bad=="extra_attribute")attr(key,"changed")<-TRUE
  reject(.Call(backend$symbol,key,"1","1",FALSE))
}
# Tiny forced-GC audit exercises protection across allocating R_Serialize.
gctorture(TRUE)
gc_probe <- mqk_candidate_uniforms(backend,"GC","draw","origin",c(1L,2L),1L,proof,TRUE)
gctorture(FALSE)
check(identical(gc_probe$uniforms,app_iqf_mqb_fast_uniforms("GC","draw","origin",c(1L,2L),1L,proof)))
same_rng()
# Absence of the caller RNG is preserved too; native code never uses R RNG APIs.
rm(".Random.seed",envir=.GlobalEnv)
invisible(mqk_candidate_uniforms(backend,"absent","draw","origin",1:3,2L,proof))
check(!exists(".Random.seed",.GlobalEnv,inherits=FALSE)&&identical(RNGkind(),initial_kind))
assign(".Random.seed",initial_seed,.GlobalEnv)

for(config in list(list(D=1L,activation="identity",projection=FALSE,standardize=TRUE),
    list(D=2L,activation="tanh",projection=TRUE,standardize=TRUE),
    list(D=3L,activation="relu",projection=TRUE,standardize=FALSE))) {
  f<-do.call(mqb_fixture,config);f$origins<-f$origins["o8"];f$origins$o8$H<-30L
  adapter<-do.call(app_iqf_mq_batch_adapter,c(f,list(inner_paths=17L,batch_size=4L,
    rng_mode="r46_first_step_qualified",rng_proof=proof)))
  reference<-app_iqf_mq_batch_arrays(adapter,f$posterior$draw_ids[1L],"o8",c(1L,3L,7L,17L),include_trace=TRUE)
  actual<-mqk_candidate_arrays(backend,adapter,f$posterior$draw_ids[1L],"o8",c(1L,3L,7L,17L),include_trace=TRUE)
  for(field in c("response","ordered_quantiles","trace","raw_coherence","inner_ids","coupling"))
    check(identical(reference[[field]],actual[[field]]))
  check(!actual$production_authorized&&!actual$numerical_accuracy_qualified)
  same_rng()
}
check(identical(baseline_body,deparse(body(app_iqf_mqb_fast_uniforms),width.cutoff=500L)))
check(identical(baseline_formals,formals(app_iqf_mqb_fast_uniforms)))
check(identical(baseline_environment,environment(app_iqf_mqb_fast_uniforms)))
timings<-list()
for(repetition in 1:3)for(method in if(repetition%%2L)c("reference","candidate")else c("candidate","reference")) {
  gc(FALSE);before<-proc.time()
  value<-if(method=="reference")app_iqf_mqb_fast_uniforms("generated_timing","draw","origin",1:1024,30L,proof)else
    mqk_candidate_uniforms(backend,"generated_timing","draw","origin",1:1024,30L,proof)
  elapsed<-proc.time()-before
  timings[[length(timings)+1L]]<-data.frame(repetition=repetition,method=method,
    user_cpu_s=unname(elapsed["user.self"]),system_cpu_s=unname(elapsed["sys.self"]),
    wall_s=unname(elapsed["elapsed"]),value_sha256=app_iqf_hash(value))
  same_rng()
}
t<-do.call(rbind,timings);check(length(unique(t$value_sha256))==1L)
write.csv(t,file.path(output,"generated_timings.csv"),row.names=FALSE)
jsonlite::write_json(list(schema_version="mq_native_key_hash_generated_test_v1",checks=n,
  status="PASS_GENERATED_BYTE_SHA_WORD_UNIFORM_AND_ARRAY_PARITY_ONLY",R=as.character(getRversion()),
  digest=as.character(utils::packageVersion("digest")),candidate_dll=dll_path,candidate_sha256=dll_sha,
  serializer="public_R_Serialize_version2_XDR",digest_header_skip=14L,
  identity_cases=length(triples),raw_byte_tuples=length(triples)*6L*7L,
  real_native_CMRG_uniforms_compared=length(triples)*6L*7L,
  caller_RNG_unchanged=TRUE,canonical_defaults_unchanged=TRUE,forced_GC_probe=TRUE,
  authentic_reads=0L,fits=0L,truth_reads=0L,production_authorized=FALSE,
  source_runtime_authenticated=FALSE,numerical_accuracy_qualified=FALSE,campaign_speedup_claimed=FALSE),
  file.path(output,"generated_test_receipt.json"),auto_unbox=TRUE,pretty=TRUE,digits=17)
cat(sprintf("MQ_NATIVE_KEY_HASH_GENERATED_CHECKS=%d PASS; authentic_reads=0 production=FALSE\n",n))
