# Pure metadata only. These synthetic paths are never opened.
source("scripts/runtime_identity_cache_observations.R",local=TRUE)
ic_n <- 0L
ic_check <- function(x){stopifnot(isTRUE(x));ic_n <<- ic_n+1L}
ic_reject <- function(x,text=NULL) {
  e<-tryCatch({force(x);NULL},error=identity)
  ic_check(inherits(e,"error")&&(is.null(text)||grepl(text,conditionMessage(e),fixed=TRUE)))
}
cache_paths <- runtime_ic_paths()
maps <- data.frame(path=c(cache_paths,"/usr/lib64/libnss_sss.so.2"),
  permissions=c("r--s","rw-s","r--s","r-xp"),stringsAsFactors=FALSE)
meta <- data.frame(path=cache_paths,canonical_path=cache_paths,uid=rep(981,3),gid=rep(981,3),
  mode=rep(as.numeric(as.octmode("0664")),3),size_bytes=c(9253600,6940392,11567160),
  regular=rep(TRUE,3),symlink=rep(FALSE,3),stringsAsFactors=FALSE)
classes <- runtime_ic_classify(maps,meta)
ic_check(identical(classes$strict_mapped_paths,"/usr/lib64/libnss_sss.so.2"))
ic_check(setequal(classes$observational_paths,cache_paths))
for(mut in list(function(x){x$uid[1]<-1000;x},function(x){x$gid[1]<-1000;x},
  function(x){x$mode[1]<-as.numeric(as.octmode("0755"));x},
  function(x){x$mode[1]<-as.numeric(as.octmode("0600"));x},
  function(x){x$regular[1]<-FALSE;x},function(x){x$symlink[1]<-TRUE;x},
  function(x){x$canonical_path[1]<-"/tmp/cache";x},function(x){x$size_bytes[1]<-0;x},
  function(x){x$size_bytes[1]<-64*1024^2+1;x},function(x){x<-rbind(x,x[1,]);x},
  function(x){x$path[1]<-"/var/lib/sss/mc/other";x},function(x){x$uid[1]<-NA_real_;x}))
  ic_reject(runtime_ic_classify(maps,mut(meta)))
bad <- maps;bad$permissions[1]<-"r-xs"
ic_reject(runtime_ic_classify(bad,meta),"non-executable")
bad <- rbind(maps,data.frame(path=cache_paths[1],permissions="r-xs"))
ic_reject(runtime_ic_classify(bad,meta),"non-executable")
for(path in c("/var/lib/sss/mc/other","/var/lib/sss/mc/passwd.backup","/var/lib/sss/mc/passwd (deleted)",
  "/var/lib/sss/other")) {
  bad <- rbind(maps,data.frame(path=path,permissions="r--s"))
  ic_reject(runtime_ic_classify(bad,meta),"unknown SSSD")
}
parsed <- runtime_ic_mappings(c("1000-2000 r--s 00000000 00:00 1 /var/lib/sss/mc/passwd",
  "2000-3000 r-xp 00000000 00:00 2 /usr/lib64/libnss_sss.so.2","3000-4000 rw-p 00000000 00:00 0"))
ic_check(identical(parsed$path,c(cache_paths[1],"/usr/lib64/libnss_sss.so.2")))
ic_reject(runtime_ic_mappings("1000-2000 r--s 00000000 00:00 1 /var/lib/sss/mc/passwd (deleted)"),"deleted")
ic_reject(runtime_ic_mappings("1000-2000 bad! 00000000 00:00 1 /var/lib/sss/mc/passwd"),"malformed")
empty_meta <- meta[FALSE,,drop=FALSE]
none <- runtime_ic_classify(maps[4L,,drop=FALSE],empty_meta)
ic_check(length(none$observational_paths)==0L&&identical(none$strict_mapped_paths,"/usr/lib64/libnss_sss.so.2"))
# No generic /var/lib exemption: unrelated mapped data stays strictly pinned.
other <- maps[4L,,drop=FALSE];other$path <- "/var/lib/unrelated/data"
ic_check(identical(runtime_ic_classify(other,empty_meta)$strict_mapped_paths,other$path))
cat(sprintf("RUNTIME_IDENTITY_CACHE_CLASSIFIER=%d PASS; metadata_only=TRUE authentic_reads=0\n",ic_n))
