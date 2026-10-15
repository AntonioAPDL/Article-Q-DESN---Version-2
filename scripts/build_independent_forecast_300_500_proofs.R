#!/usr/bin/env Rscript
options(stringsAsFactors=FALSE)
file <- normalizePath(sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1L]))
root <- normalizePath(file.path(dirname(file),".."))
args <- commandArgs(TRUE)
at <- match("--source-root",args)
if (!is.na(at)) { stopifnot(at < length(args)); root <- normalizePath(args[at+1L],mustWork=TRUE) }
setwd(root)
out <- file.path(root,"local_trackers/independent_forecast_300_500_v1/build")
for(doc in c("main","qdesn-supplement")) {
  dir <- file.path(out,doc); dir.create(dir,recursive=TRUE,showWarnings=FALSE)
  args <- c("-interaction=nonstopmode","-halt-on-error","-recorder",paste0("-output-directory=",dir),paste0(doc,".tex"))
  run <- function(name) {
    status <- system2("/usr/bin/pdflatex",shQuote(args),stdout=file.path(dir,paste0(name,".txt")),
      stderr=file.path(dir,paste0(name,"_stderr.txt")))
    if(status!=0L) stop(paste("TeX failure",doc,name,"see",dir),call.=FALSE)
  }
  run("pass1")
  old <- getwd(); setwd(dir)
  status <- system2("/usr/bin/bibtex",doc,env=c(paste0("BIBINPUTS=",root,":"),paste0("BSTINPUTS=",root,":")),
    stdout="bibtex.txt",stderr="bibtex_stderr.txt")
  setwd(old)
  if(status!=0L) stop(paste("BibTeX failure",doc),call.=FALSE)
  for(pass in 2:4) run(paste0("pass",pass))
  cat("COMPILED",doc,"\n")
}
cat("BUILD_ROOT",out,"\n")
