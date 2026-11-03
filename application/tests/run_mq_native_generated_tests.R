#!/usr/bin/env Rscript
# Isolated generated-only test adapter. No authentic evidence or model input.
local({
  require_ok <- function(ok, why) if (!isTRUE(ok)) stop(paste0("MQ generated runner: ",why),call.=FALSE)
  require_ok(length(commandArgs(trailingOnly=TRUE))==0L,"zero trailing arguments required")
  file_arg <- grep("^--file=",commandArgs(FALSE),value=TRUE)
  require_ok(length(file_arg)==1L,"standalone --file invocation required")
  root <- normalizePath(file.path(dirname(sub("^--file=","",file_arg)),"../.."),mustWork=TRUE)
  setwd(root)
  require_ok(identical(as.character(getRversion()),"4.6.0"),"R4.6.0 required")
  require_ok(requireNamespace("jsonlite",quietly=TRUE),"jsonlite required")
  compiler <- "/usr/bin/gcc"
  require_ok(identical(unname(system2(compiler,"-dumpfullversion",stdout=TRUE)),"8.5.0"),"declared GCC8.5.0 required")
  rscript <- normalizePath(file.path(R.home("bin"),"Rscript"),mustWork=TRUE)
  native_lib <- normalizePath(R.home("lib"),mustWork=TRUE)
  tests <- c(key="test_mq_native_key_hash.R",isotonic="test_mq_isoreg_batch.R",
    inverse="test_mq_native_event_inverse.R",composed="test_mq_native_composed_arrays.R")
  cli <- c(key=3L,isotonic=0L,inverse=0L,composed=0L)
  markers <- c(key="MQ_NATIVE_KEY_HASH_GENERATED_CHECKS=1335 PASS",
    isotonic="MQ_ISOREG_BATCH_GENERATED_PASS checks=49 ",
    inverse="MQ_NATIVE_EVENT_CANDIDATE_PASS checks=222 ",
    composed="MQ_COMPOSED_GENERATED_PASS checks=465 ")
  source_files <- c(file.path("application/tests",c("run_mq_native_generated_tests.R",unname(tests))),
    "scripts/mq_native_key_hash.R","scripts/mq_isoreg_batch.R","scripts/mq_native_event_inverse.R",
    "scripts/mq_native_composed_arrays.R","scripts/native/mq_key_hash.c",
    "scripts/native/mq_isoreg_batch.c","scripts/native/mq_event_inverse.c",
    "scripts/integrated_quantile_mq_batch.R","scripts/mq_forecast_array_methods.R",
    "application/R/integrated_quantile_forecast.R")
  pins <- tools::sha256sum(source_files)
  destination <- Sys.getenv("MQ_NATIVE_GENERATED_RECEIPT_ROOT",unset="")
  if (!nzchar(destination)) destination <- tempfile("mq_native_generated_runner_")
  parent <- normalizePath(dirname(destination),mustWork=TRUE)
  require_ok(identical(dirname(destination),parent)&&
    !basename(destination)%in%c(".",".."),"canonical receipt parent required")
  in_temporary <- startsWith(destination,paste0(normalizePath(tempdir(),mustWork=TRUE),"/"))
  in_ignored <- startsWith(destination,paste0(root,"/"))&&
    identical(as.integer(system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(destination)))),0L)
  require_ok(in_temporary||in_ignored,"receipt must be in the process temporary tree or an ignored repository path")
  require_ok(!file.exists(destination)&&dir.create(destination,recursive=FALSE),"fresh receipt directory required")
  destination <- normalizePath(destination,mustWork=TRUE)
  build <- file.path(destination,"key_build");temporary <- file.path(destination,"temporary")
  require_ok(dir.create(build)&&dir.create(temporary),"fresh generated build/temp directories required")
  environment_keys <- c("R_MAKEVARS_USER","R_MAKEVARS_SITE","MAKEFLAGS","MAKEOVERRIDES",
    "CC","PATH","PKG_LIBS","TMPDIR","OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS","NUMEXPR_NUM_THREADS","LC_ALL","TZ","MQE_BUILD_ROOT","MQC_RECEIPT_ROOT")
  old <- Sys.getenv(environment_keys,unset=NA_character_)
  restore <- function() for (key in names(old)) {
    if (is.na(old[[key]])) Sys.unsetenv(key) else do.call(Sys.setenv,setNames(list(old[[key]]),key))
  }
  on.exit(restore(),add=TRUE)
  makevars <- file.path(build,"controlled.Makevars")
  libs <- paste0("-Wl,-rpath,",native_lib," -lcrypto")
  writeLines(c("CC = /usr/bin/gcc","CFLAGS = -O2 -fno-fast-math -ffp-contract=off",
    "PKG_CFLAGS = -fno-fast-math -ffp-contract=off",paste0("PKG_LIBS = ",libs)),makevars)
  Sys.setenv(R_MAKEVARS_USER=makevars,R_MAKEVARS_SITE="/dev/null",MAKEFLAGS="-j1",MAKEOVERRIDES="",
    CC=compiler,PATH="/usr/bin:/bin",PKG_LIBS=libs,TMPDIR=temporary,
    OMP_NUM_THREADS="1",OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1",
    VECLIB_MAXIMUM_THREADS="1",NUMEXPR_NUM_THREADS="1",LC_ALL="C",TZ="UTC")
  # The unchanged isotonic/event tests replace their user Makevars. The
  # explicit compiler PATH and PKG_LIBS environment still bind their compiler
  # and rpath; inspect their actual command logs rather than assuming this.
  output_check <- function() {
    files <- list.files(destination,recursive=TRUE,full.names=TRUE,all.files=TRUE,no..=TRUE)
    sizes <- file.info(files)$size
    require_ok(all(is.finite(sizes))&&all(sizes>=0)&&all(!nzchar(Sys.readlink(files))),
      "generated output file missing, unstatable or symlinked")
    require_ok(sum(sizes)<128*1024^2,"aggregate generated output exceeds128MiB")
  }
  compilation_check <- function(lines,label) {
    require_ok(any(grepl("-fno-fast-math",lines,fixed=TRUE))&&
      any(grepl("-ffp-contract=off",lines,fixed=TRUE))&&
      any(grepl(paste0("-Wl,-rpath,",native_lib),lines,fixed=TRUE))&&
      any(grepl("^(/usr/bin/)?gcc[[:space:]]",lines)),paste(label,"compiler/flags/rpath not observed"))
  }
  results <- list()
  tryCatch({
    require_ok(file.copy("scripts/native/mq_key_hash.c",file.path(build,"mq_key_hash.c")),"key source copy failed")
    setwd(build)
    build_log <- system2(file.path(R.home("bin"),"R"),c("CMD","SHLIB","--preclean","mq_key_hash.c"),stdout=TRUE,stderr=TRUE)
    setwd(root)
    writeLines(build_log,file.path(destination,"key_build.log"))
    require_ok(is.null(attr(build_log,"status")),"key DLL build failed")
    compilation_check(build_log,"key")
    dll <- normalizePath(file.path(build,paste0("mq_key_hash",.Platform$dynlib.ext)),mustWork=TRUE)
    dll_sha <- unname(tools::sha256sum(dll))
    key_output <- file.path(destination,"key_output");require_ok(dir.create(key_output),"key output directory failed")
    for (name in names(tests)) {
      Sys.unsetenv(c("MQE_BUILD_ROOT","MQC_RECEIPT_ROOT"))
      if (name=="inverse") Sys.setenv(MQE_BUILD_ROOT=file.path(temporary,"event_build"))
      if (name=="composed") Sys.setenv(MQC_RECEIPT_ROOT=file.path(destination,"composed_output"))
      extra <- if (name=="key")c(dll,dll_sha,key_output)else character()
      require_ok(length(extra)==cli[[name]],paste(name,"CLI adapter arity changed"))
      args <- c("--vanilla",file.path(root,"application/tests",tests[[name]]),extra)
      log <- file.path(destination,paste0(name,".log"));start <- proc.time()
      status <- system2(rscript,shQuote(args),stdout=log,stderr=log)
      elapsed <- proc.time()-start
      lines <- readLines(log,warn=FALSE)
      # Surface real child output in the full repository harness as well.
      cat(paste(lines,collapse="\n"),"\n")
      require_ok(identical(as.integer(status),0L)&&any(grepl(markers[[name]],lines,fixed=TRUE)),
        paste(name,"test failed or omitted its completion marker"))
      if(name!="key")compilation_check(lines,name)
      results[[name]] <- list(test=tests[[name]],trailing_arguments=cli[[name]],exit_code=as.integer(status),
        marker=markers[[name]],log_sha256=unname(tools::sha256sum(log)),wall_seconds=unname(elapsed["elapsed"]))
      output_check()
    }
    require_ok(identical(pins,tools::sha256sum(source_files)),"source/test bytes changed during runner")
    write.csv(data.frame(path=source_files,size_bytes=as.numeric(file.info(source_files)$size),
      sha256=unname(pins)),file.path(destination,"source_and_test_pins.csv"),row.names=FALSE)
    jsonlite::write_json(list(schema_version="mq_native_generated_standalone_runner_v1",
      status="FOUR_GENERATED_TEST_ENTRYPOINTS_PASS",R=as.character(getRversion()),Rscript=rscript,
      compiler=compiler,compiler_version="8.5.0",native_R_libdir=native_lib,
      controlled_Makevars=readLines(makevars),tests=results,
      parameter_draws_pooled=FALSE,authentic_reads=0L,model_fits=0L,
      source_runtime_authenticated=FALSE,C_ABI_qualified=FALSE,production_authorized=FALSE),
      file.path(destination,"RUNNER_RECEIPT.json"),auto_unbox=TRUE,pretty=TRUE,digits=17)
    output_check()
    cat(sprintf("MQ_NATIVE_GENERATED_RUNNER_PASS tests=4 CLI=3,0,0,0 receipt=%s authentic_reads=0 production=FALSE\n",destination))
  },error=function(e){
    setwd(root)
    jsonlite::write_json(list(status="FAILED_GENERATED_TEST_RUNNER",error=conditionMessage(e),
      completed_tests=results,authentic_reads=0L,production_authorized=FALSE),
      file.path(destination,"RUNNER_FAILURE.json"),auto_unbox=TRUE,pretty=TRUE)
    stop(e)
  })
})
