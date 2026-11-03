#!/usr/bin/env Rscript
source("scripts/mq_qualified_pilot_typed.R")
mqp2_sources <- function() c("scripts/mq_qualified_pilot_typed.R","scripts/consume_mq_qualified_pilot.R",
  "application/tests/test_mq_qualified_pilot_typed.R","docs/implementation_notes/mq_qualified_pilot_typed_20261103.md",
  "scripts/integrated_quantile_receipts_v2.R","scripts/mq_streaming_cdf_certificate.R",
  "scripts/mq_independent_cdf_certificate.R","scripts/qualify_integrated_quantile_forecast.R")
mqp2_scope <- function(s) {
  q<-mqp2_require
  fields<-c("schema_version","purpose","mode","nonce","expires_utc","source_root","source_commit","source_tree",
    "source_files","evidence_pins","output_root","expected_provenance_sha256","limits","allow_own_pilot_read",
    "allow_compact_packet_read","allow_model_read","allow_future_truth","allow_refit","allow_scoring","allow_ledger_mutation",
    "allow_production","allow_article")
  q(is.list(s)&&identical(sort(names(s)),sort(fields))&&!anyDuplicated(names(s))&&
    identical(s$schema_version,"mq_qualified_pilot_consumer_purpose_v1")&&
    identical(s$purpose,"OWN_EVIDENCE_TYPED_QUALIFICATION_ONLY")&&s$mode%in%c("convert","readback")&&
    is.character(s$nonce)&&length(s$nonce)==1L&&grepl("^[a-f0-9]{32,64}$",s$nonce),"distinct own-evidence consumer purpose required")
  for(k in c("allow_model_read","allow_future_truth","allow_refit","allow_scoring","allow_ledger_mutation","allow_production","allow_article"))
    q(identical(s[[k]],FALSE),"consumer cannot grant scientific/production authority")
  q(identical(s$allow_own_pilot_read,identical(s$mode,"convert"))&&
    identical(s$allow_compact_packet_read,identical(s$mode,"readback")),"separate input/output reader roles required")
  q(mqp2_roles(s$evidence_pins)<=32*1024^2,"complete selected evidence exceeds32MiB")
  wanted<-list(cpu_seconds=120,wall_term_seconds=119,wall_kill_after_seconds=1,
    address_space_bytes=2*1024^3,output_bytes=16*1024^2,logical_cpu=30)
  q(is.list(s$limits)&&setequal(names(s$limits),names(wanted))&&all(vapply(names(wanted),function(k)
    is.numeric(s$limits[[k]])&&length(s$limits[[k]])==1L&&is.finite(s$limits[[k]])&&
      s$limits[[k]]==wanted[[k]],logical(1L))),"fixed finite one-core consumer budget required")
  q(if(s$mode=="convert")is.null(s$expected_provenance_sha256)else
    is.character(s$expected_provenance_sha256)&&length(s$expected_provenance_sha256)==1L&&
      grepl("^[a-f0-9]{64}$",s$expected_provenance_sha256),"separately pinned readback provenance required")
  invisible(TRUE)
}
mqp2_source_guard <- function(s) {
  q<-mqp2_require;root<-normalizePath(getwd(),mustWork=TRUE)
  git<-function(args) {x<-system2("/usr/bin/git",c("--no-replace-objects","-c","core.fsmonitor=false",args),stdout=TRUE)
    q(is.null(attr(x,"status")),"source Git check failed");unname(x)}
  q(identical(root,s$source_root)&&identical(git(c("rev-parse","HEAD")),s$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=all"))),"exact clean committed consumer source required")
  paths<-vapply(s$source_files,`[[`,"","path")
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,mqp2_sources())),"complete exact consumer source closure required")
  for(pin in s$source_files)mqp2_pin(pin,1024^2)
  for(rel in mqp2_sources())q(identical(git(c("hash-object","--no-filters","--",shQuote(rel))),
    git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel))))),"current source differs from its committed blob")
  invisible(root)
}
mqp2_runtime <- function(s) {
  q<-mqp2_require;b<-s$limits
  q(identical(as.character(getRversion()),"4.6.0")&&
    identical(normalizePath(R.home()),"/data/jaguir26/local/opt/R/4.6.0/lib64/R")&&
    identical(as.character(utils::packageVersion("digest")),"0.6.39")&&"--vanilla"%in%commandArgs(FALSE)&&
    Sys.info()[["nodename"]]%in%c("muscat","muscat.be.ucsc.edu")&&
    all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1")&&
    !nzchar(Sys.getenv("LD_PRELOAD"))&&!nzchar(Sys.getenv("LD_AUDIT")),"native vanilla single-thread consumer required")
  q2_limits(list(logical_cpu=30,max_cpu_seconds=120,max_wall_seconds=120,max_memory_bytes=2*1024^3,max_output_bytes=16*1024^2))
  # The child cannot escape the TERM/KILL process group of the exact timeout.
  parse<-function(pid) {x<-readLines(sprintf("/proc/%s/stat",pid),warn=FALSE)
    as.integer(strsplit(sub("^[0-9]+ \\(.*\\) ","",x),"[[:space:]]+")[[1L]][2:4])}
  self<-parse("self");pid<-Sys.getpid();matched<-FALSE
  for(i in 1:12) {
    z<-parse(pid);parent<-z[1L];if(parent<=1L)break
    raw<-readBin(sprintf("/proc/%d/cmdline",parent),"raw",n=16384L);raw[raw==as.raw(0)]<-as.raw(10)
    argv<-strsplit(rawToChar(raw),"\n",fixed=TRUE)[[1L]]
    if(length(argv)&&basename(argv[1L])=="timeout") {
      pp<-parse(parent)
      q(identical(argv[2:4],c("--signal=TERM","--kill-after=1s","119s"))&&
        pp[2L]==parent&&identical(self[2:3],pp[2:3]),"exact whole-group timeout required")
      matched<-TRUE;break
    };pid<-parent
  }
  q(matched,"native bounded consumer timeout missing")
}
mqp2_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {cat("--contract EXTERNAL_JSON --sha256 SHA --execute; never production\n");return(invisible(NULL))}
  q<-mqp2_require
  q(length(args)==5L&&identical(args[c(1,3,5)],c("--contract","--sha256","--execute")),"explicit external own-evidence purpose required")
  for(p in c("digest","jsonlite"))q(requireNamespace(p,quietly=TRUE),"required package missing")
  cp<-normalizePath(args[2L],mustWork=TRUE);q2_regular(cp)
  q(identical(cp,args[2L])&&!startsWith(cp,paste0(normalizePath(getwd()),"/"))&&file.info(cp)$size<=1024^2&&
    identical(mqp2_sha(cp),args[4L]),"exact external consumer purpose required")
  s<-jsonlite::read_json(cp,simplifyVector=FALSE);mqp2_scope(s)
  expiry<-q2_time(s$expires_utc);q(!is.na(expiry)&&expiry>Sys.time()+120,"complete future purpose lifetime required")
  root<-mqp2_source_guard(s);mqp2_runtime(s)
  output<-s$output_root;q2_regular(output)
  q(startsWith(output,paste0(root,"/local_trackers/")),"ignored consumer output must belong to this source worktree")
  if(s$mode=="readback") {
    proof<-mqp2_readback(output,s$expected_provenance_sha256)
    mqp2_source_guard(s);q(expiry>Sys.time(),"consumer purpose expired")
    cat(jsonlite::toJSON(proof,auto_unbox=TRUE),"\n");return(invisible(proof))
  }
  q(!file.exists(output)&&identical(dirname(output),normalizePath(dirname(output),mustWork=TRUE))&&
    system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(output)))==0L,"fresh ignored output required")
  q(dir.create(output),"owned fresh output creation failed")
  tryCatch({
  pins<-s$evidence_pins;invisible(lapply(pins,mqp2_pin))
  meta<-lapply(pins[c("pilot_purpose","qualification","freeze","stop_post","terminal")],function(p)jsonlite::read_json(p$path,simplifyVector=FALSE))
  meta$finalizer_time<-readLines(pins$finalizer_time$path,warn=FALSE)
  manifest<-read.csv(pins$manifest$path,stringsAsFactors=FALSE)
  mqp2_links(meta,pins,manifest) # No RDS has been opened yet.
  objects<-lapply(pins[c("candidates","split","stream")],function(p)readRDS(p$path))
  value<-mqp2_make(meta,pins,manifest,objects$candidates,objects$split,objects$stream,
    list(source_commit=s$source_commit,source_tree=s$source_tree,purpose_sha256=args[4L]))
  invisible(lapply(pins,mqp2_pin));mqp2_source_guard(s);q(expiry>Sys.time(),"consumer purpose expired")
  sha<-mqp2_write(value,output,prepared_empty=TRUE)
  q(sum(file.info(list.files(output,full.names=TRUE))$size)<16*1024^2,"consumer output cap exceeded")
  cat("QUALIFICATION_ONLY_TYPED_PACKET_CREATED provenance_sha256=",sha," production=FALSE\n",sep="")
  invisible(sha)
  },error=function(e){
    jsonlite::write_json(list(status="FAILED_OWN_EVIDENCE_TYPED_CONSUMER_NOT_PRODUCTION",error=conditionMessage(e),
      purpose_sha256=args[4L],source_commit=s$source_commit,production_authorized=FALSE),
      file.path(output,"FAILURE.json"),auto_unbox=TRUE,pretty=TRUE)
    stop(e)
  })
}
if(sys.nframe()==0L)mqp2_main()
