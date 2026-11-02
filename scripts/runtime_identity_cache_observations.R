# Narrow host-OS observation boundary, not a scientific input exemption.
# Only Muscat's three SSSD identity-service mmap caches are observational.
# Software (including libnss*.so), packages and numerical inputs remain pinned.
runtime_ic_require <- function(ok,message) {
  if(!isTRUE(ok))stop(paste0("Runtime identity-cache classification: ",message),call.=FALSE)
  invisible(TRUE)
}
runtime_ic_paths <- function()paste0("/var/lib/sss/mc/",c("passwd","group","initgroups"))
runtime_ic_mappings <- function(lines) {
  q <- runtime_ic_require
  q(is.character(lines)&&!anyNA(lines),"native mapping records required")
  lines <- lines[grepl("/",lines)]
  q(!any(grepl(" \\(deleted\\)$",lines)),"deleted file-backed mapping forbidden")
  permissions <- vapply(strsplit(trimws(lines),"[[:space:]]+"),function(x)x[2L],character(1L))
  paths <- sub("^[^/]*(/.*)$","\\1",lines)
  q(all(grepl("^[r-][w-][x-][ps]$",permissions))&&all(startsWith(paths,"/")),
    "malformed file-backed mapping")
  data.frame(path=paths,permissions=permissions,stringsAsFactors=FALSE)
}

# Pure classifier: ownership/type evidence is supplied explicitly for tests.
# No prefix, generic data-file or arbitrary mutable-file exemption exists.
runtime_ic_classify <- function(mappings,metadata) {
  q <- runtime_ic_require
  q(is.data.frame(mappings)&&identical(names(mappings),c("path","permissions"))&&
    all(vapply(mappings,is.character,logical(1L)))&&!anyNA(mappings)&&
    all(startsWith(mappings$path,"/"))&&
    all(grepl("^[r-][w-][x-][ps]$",mappings$permissions)),"exact native mapping metadata required")
  allowed <- runtime_ic_paths();selected <- sort(unique(mappings$path[mappings$path%in%allowed]))
  q(!any(startsWith(mappings$path,"/var/lib/sss/")&!mappings$path%in%allowed),
    "unknown SSSD mapping is not an identity-cache exemption")
  fields <- c("path","canonical_path","uid","gid","mode","size_bytes","regular","symlink")
  q(is.data.frame(metadata)&&identical(names(metadata),fields)&&!anyNA(metadata)&&
    !anyDuplicated(metadata$path)&&setequal(metadata$path,selected),
    "exact cache file-type/ownership metadata required")
  if(length(selected)) {
    metadata <- metadata[match(selected,metadata$path),,drop=FALSE]
    q(all(metadata$canonical_path==metadata$path)&&is.logical(metadata$regular)&&
      is.logical(metadata$symlink)&&all(metadata$regular)&&!any(metadata$symlink),
      "cache must be canonical nonsymlink regular file")
    q(all(vapply(metadata[c("uid","gid","mode","size_bytes")],is.numeric,logical(1L)))&&
      all(is.finite(as.matrix(metadata[c("uid","gid","mode","size_bytes")]))),
      "finite numeric cache ownership/mode/size required")
    q(all(metadata$uid==981)&&all(metadata$gid==981),"cache must belong to Muscat SSSD service UID/GID981")
    q(all(metadata$mode==as.integer(as.octmode("0664")))&&
      all(bitwAnd(as.integer(metadata$mode),as.integer(as.octmode("0111")))==0L)&&
      !any(grepl("x",mappings$permissions[mappings$path%in%allowed],fixed=TRUE)),
      "identity cache file and every mapping must be non-executable with native mode0664")
    q(all(metadata$size_bytes>0&metadata$size_bytes<=64*1024^2&
      metadata$size_bytes==floor(metadata$size_bytes)),"bounded positive identity-cache size required")
  }
  list(strict_mapped_paths=sort(unique(mappings$path[!mappings$path%in%allowed])),
    observational_paths=selected,metadata=metadata)
}

runtime_ic_snapshot <- function() {
  q <- runtime_ic_require
  empty <- data.frame(path=character(),canonical_path=character(),uid=numeric(),gid=numeric(),
    mode=numeric(),size_bytes=numeric(),regular=logical(),symlink=logical(),stringsAsFactors=FALSE)
  read_maps <- function()runtime_ic_mappings(readLines("/proc/self/maps",warn=FALSE))
  maps <- read_maps();metadata <- empty
  # file.info's numeric ownership lookup can itself make another one of the
  # three NSS caches visible. Stabilize path discovery, never their bytes.
  for(attempt in 1:4) {
    paths <- sort(unique(maps$path[maps$path%in%runtime_ic_paths()]))
    if(length(paths)) {
      info <- file.info(paths)
      metadata <- data.frame(path=paths,canonical_path=normalizePath(paths,mustWork=TRUE),
        uid=as.numeric(info$uid),gid=as.numeric(info$gid),mode=as.numeric(info$mode),
        size_bytes=as.numeric(info$size),regular=file_test("-f",paths),
        symlink=nzchar(Sys.readlink(paths)),stringsAsFactors=FALSE)
    } else metadata <- empty
    newer <- read_maps()
    if(setequal(newer$path[newer$path%in%runtime_ic_paths()],paths)) {maps<-newer;break}
    maps <- newer
  }
  classified <- runtime_ic_classify(maps,metadata)
  paths <- classified$observational_paths
  observed <- classified$metadata
  observed$mode_octal <- if(length(paths))format(as.octmode(observed$mode),width=4L)else character()
  observed$mapping_permissions <- vapply(paths,function(p)
    paste(sort(unique(maps$permissions[maps$path==p])),collapse=","),character(1L))
  observed$observed_sha256 <- if(length(paths))unname(tools::sha256sum(paths))else character()
  q(!anyNA(observed$observed_sha256),"identity-cache observation hash unavailable")
  observed$classification <- rep("observational_SSSD_identity_service_OS_state_not_numerical_input",length(paths))
  observed$live_byte_equality_required <- rep(FALSE,length(paths))
  list(strict_mapped_paths=classified$strict_mapped_paths,observational_os_state=observed,
    observation_role="non_atomic_OS_identity_cache_metadata_and_hash_observation_not_software_pin",
    immutable_software_and_numerical_inputs_still_required=TRUE)
}
