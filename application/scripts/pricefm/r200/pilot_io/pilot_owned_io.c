/* New pilot-only bounded I/O. Never load this into the old diagnostic chain.
 * Source-only preparation: compile/ABI/syscall/serialization qualification is
 * mandatory in a separately admitted compute job. No sparse/rename fallback.
 */
#define _GNU_SOURCE
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Connections.h>
#if R_CONNECTIONS_VERSION != 1
#error Unsupported R custom-connection ABI
#endif
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <sys/file.h>
#include <linux/memfd.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <time.h>
#include <math.h>
#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE 1
#endif
#ifndef SYS_renameat2
#error renameat2 syscall is required
#endif
#ifndef SYS_memfd_create
#error memfd_create syscall is required
#endif
#define TAG "r200_owned_io_capability_v1"
#define PER_FILE (16ULL * 1024ULL * 1024ULL)
#define CHUNK 65536U
#define MAX_SLOTS 650
typedef struct {
    char *name; uint64_t bound, written; dev_t dev; ino_t ino;
    int opened, closed, committed; int fd;
} slot_t;
typedef struct { char *name,*path; uint64_t bytes; int sealed_fd; } input_t;
typedef struct {
    pid_t pid,parent; uid_t uid; unsigned long long parent_birth;
    int rootfd,failed; double expiry; char *job,*node;
    slot_t *slots; int nslots; input_t *inputs; int ninputs;
    uint64_t snapshot_limit,snapshot_used;
} cap_t;
typedef struct { cap_t *cap; int index; SEXP handle; } connection_t;

static SEXP field(SEXP x,const char *name) {
    SEXP names=getAttrib(x,R_NamesSymbol);
    if(TYPEOF(x)!=VECSXP || TYPEOF(names)!=STRSXP) Rf_error("closed named object required");
    for(R_xlen_t i=0;i<XLENGTH(x);i++) if(!strcmp(CHAR(STRING_ELT(names,i)),name)) return VECTOR_ELT(x,i);
    Rf_error("required field missing: %s",name); return R_NilValue;
}
static const char *text(SEXP x) {
    if(TYPEOF(x)!=STRSXP || XLENGTH(x)!=1 || STRING_ELT(x,0)==NA_STRING) Rf_error("scalar text required");
    return CHAR(STRING_ELT(x,0));
}
static uint64_t number(SEXP x,uint64_t max) {
    double v=asReal(x);
    if((TYPEOF(x)!=INTSXP&&TYPEOF(x)!=REALSXP)||XLENGTH(x)!=1 || !R_FINITE(v) || v<0 || v>9007199254740991.0 || floor(v)!=v || v>(double)max)
        Rf_error("bounded exact integer required");
    return (uint64_t)v;
}
static void fail(cap_t *c,const char *why) { if(c)c->failed=1; Rf_error("%s (paid reservations/partials retained)",why); }
static unsigned long long birth(pid_t pid) {
    char path[64],buf[8192]; snprintf(path,sizeof(path),"/proc/%ld/stat",(long)pid);
    FILE *f=fopen(path,"r"); if(!f) Rf_error("current parent lifetime absent");
    size_t n=fread(buf,1,sizeof(buf)-1,f);fclose(f);buf[n]=0;
    char *p=strrchr(buf,')'); if(!p) Rf_error("proc stat malformed");p+=2;
    for(int i=0;i<19;i++){p=strchr(p,' ');if(!p)Rf_error("proc stat short");p++;}
    char *end;unsigned long long v=strtoull(p,&end,10);if(end==p||!v)Rf_error("birth ticks missing");return v;
}
static int kernel_context(void) {
    FILE *f=fopen("/proc/self/status","r"); if(!f)return 0;
    char line[1024];int sec=0,np=0;
    while(fgets(line,sizeof(line),f)){if(sscanf(line,"Seccomp:%d",&sec)==1)continue;if(sscanf(line,"NoNewPrivs:%d",&np)==1)continue;}
    fclose(f);return sec==2&&np==1;
}
static int job_cgroup(const char *job) {
    FILE *f=fopen("/proc/self/cgroup","r");if(!f)return 0;
    char line[8192],needle[64];snprintf(needle,sizeof(needle),"job_%s",job);int ok=0;
    while(fgets(line,sizeof(line),f)){char *p=strstr(line,needle);if(p){char after=p[strlen(needle)];if(after=='/'||after=='.'||after=='\n'||after==0)ok=1;}}
    fclose(f);return ok;
}
static void current(cap_t *c) {
    const char *job=getenv("SLURM_JOB_ID"),*node=getenv("SLURMD_NODENAME");
    if(!c||c->failed||getpid()!=c->pid||getuid()!=c->uid||getppid()!=c->parent||
       birth(c->parent)!=c->parent_birth||!job||strcmp(job,c->job)||!node||strcmp(node,c->node)||
       strncmp(node,"node-",5)||!job_cgroup(job)||!kernel_context()||difftime(time(NULL),0)>=c->expiry)
        fail(c,"current owned post-ACK compute lifetime required");
}
static cap_t *getcap(SEXP x) {
    if(TYPEOF(x)!=EXTPTRSXP||R_ExternalPtrTag(x)!=install(TAG)||!R_ExternalPtrAddr(x))Rf_error("opaque native capability required");
    cap_t *c=R_ExternalPtrAddr(x);current(c);return c;
}
static int valid_relative(const char *s) {
    if(!*s||*s=='/'||strlen(s)>1900)return 0;
    const char *p=s;
    while(*p){const char *start=p;while(*p&&*p!='/'){unsigned char a=*p;if(!((a>='a'&&a<='z')||(a>='A'&&a<='Z')||(a>='0'&&a<='9')||a=='_'||a=='-'||a=='.'))return 0;p++;}
        size_t n=(size_t)(p-start);if(!n||(n==1&&start[0]=='.')||(n==2&&start[0]=='.'&&start[1]=='.'))return 0;
        if(*p)p++;
        if(!*p&&p>s&&p[-1]=='/')return 0;
    }return 1;
}
/* Walk every ancestor using directory descriptors; never resolve a symlink. */
static int physical_open(const char *absolute,int flags) {
    if(*absolute!='/'||strlen(absolute)>2047)Rf_error("absolute physical path required");
    char *copy=strdup(absolute+1),*save=NULL,*part=strtok_r(copy,"/",&save);
    int parent=open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(parent<0){free(copy);Rf_error("root open failed");}
    while(part){if(!strcmp(part,".")||!strcmp(part,"..")){close(parent);free(copy);Rf_error("path component refused");}
        char *next=strtok_r(NULL,"/",&save);int fd=openat(parent,part,next?(O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC):(flags|O_NOFOLLOW|O_CLOEXEC));
        close(parent);if(fd<0){free(copy);Rf_error("physical path open failed");}parent=fd;part=next;
    }free(copy);return parent;
}
static int parent_dir(cap_t *c,const char *relative,char **base,int create) {
    if(!valid_relative(relative))fail(c,"canonical output slot required");
    char *copy=strdup(relative),*slash=strrchr(copy,'/');int fd=dup(c->rootfd);
    if(fd<0){free(copy);fail(c,"directory duplication failed");}
    if(!slash){*base=strdup(copy);free(copy);return fd;}
    *slash=0;*base=strdup(slash+1);char *save=NULL,*part=strtok_r(copy,"/",&save);
    while(part){
        if(create&&mkdirat(fd,part,0700)<0&&errno!=EEXIST){close(fd);free(copy);free(*base);fail(c,"private reservation directory failed");}
        int next=openat(fd,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(fd);
        if(next<0){free(copy);free(*base);fail(c,"physical reservation directory failed");}
        struct stat st;if(fstat(next,&st)||st.st_uid!=c->uid||(st.st_mode&0777)!=0700){close(next);free(copy);free(*base);fail(c,"owned private directory required");}
        fd=next;part=strtok_r(NULL,"/",&save);
    }free(copy);return fd;
}
static void finalizer(SEXP handle) {
    cap_t *c=R_ExternalPtrAddr(handle);if(!c)return;c->failed=1;
    if(c->rootfd>=0)close(c->rootfd);
    if(c->slots)for(int i=0;i<c->nslots;i++){if(c->slots[i].fd>=0)close(c->slots[i].fd);free(c->slots[i].name);}
    if(c->inputs)for(int i=0;i<c->ninputs;i++){if(c->inputs[i].sealed_fd>=0)close(c->inputs[i].sealed_fd);free(c->inputs[i].name);free(c->inputs[i].path);}
    free(c->slots);free(c->inputs);free(c->job);free(c->node);free(c);R_ClearExternalPtr(handle);
}
static uint64_t available(cap_t *c) {struct statvfs s;if(fstatvfs(c->rootfd,&s))fail(c,"filesystem capacity unknown");if(s.f_bavail>UINT64_MAX/s.f_frsize)fail(c,"filesystem capacity overflow");return (uint64_t)s.f_bavail*s.f_frsize;}
SEXP r200_io_activate(SEXP cfg) {
    cap_t *c=calloc(1,sizeof(*c));if(!c)Rf_error("allocation failed");c->rootfd=-1;
    SEXP result=PROTECT(R_MakeExternalPtr(c,install(TAG),R_NilValue));R_RegisterCFinalizerEx(result,finalizer,TRUE);
    c->pid=getpid();c->uid=getuid();c->parent=(pid_t)number(field(cfg,"parent_pid"),INT_MAX);
    c->parent_birth=number(field(cfg,"parent_birth_ticks"),9007199254740991ULL);
    if(number(field(cfg,"uid"),UINT_MAX)!=(uint64_t)c->uid)fail(c,"current UID differs");
    c->expiry=asReal(field(cfg,"expires_epoch"));if(!R_FINITE(c->expiry))fail(c,"finite expiry required");
    c->job=strdup(text(field(cfg,"job_id")));c->node=strdup(text(field(cfg,"node")));
    current(c);
    int lockfd=(int)number(field(cfg,"resource_lock_fd"),INT_MAX);char lockpath[80],line[1024];snprintf(lockpath,sizeof(lockpath),"/proc/self/fdinfo/%d",lockfd);
    FILE *lf=fopen(lockpath,"r");int held=0;if(lf){while(fgets(line,sizeof(line),lf))if(strstr(line,"FLOCK")&&strstr(line,"WRITE"))held=1;fclose(lf);}
    if(!held)fail(c,"inherited actual global permit FLOCK required");
    c->rootfd=physical_open(text(field(cfg,"output_root")),O_RDONLY|O_DIRECTORY);
    struct stat root;if(fstat(c->rootfd,&root)||root.st_uid!=c->uid||(root.st_mode&0777)!=0700)fail(c,"private owned output root required");
    SEXP slots=field(cfg,"slots");c->nslots=(int)XLENGTH(slots);if(TYPEOF(slots)!=VECSXP||c->nslots<1||c->nslots>MAX_SLOTS)fail(c,"finite slot manifest required");
    c->slots=calloc((size_t)c->nslots,sizeof(slot_t));if(!c->slots)fail(c,"allocation failed");
    for(int i=0;i<c->nslots;i++)c->slots[i].fd=-1;
    uint64_t total=0,headroom=number(field(cfg,"headroom_bytes"),9007199254740991ULL);
    if(!headroom)fail(c,"mandatory headroom required");
    for(int i=0;i<c->nslots;i++){
        SEXP row=VECTOR_ELT(slots,i);slot_t *s=c->slots+i;s->name=strdup(text(field(row,"name")));s->bound=number(field(row,"max_bytes"),PER_FILE);
        if(!valid_relative(s->name)||!s->bound)fail(c,"bounded slot required");
        for(int j=0;j<i;j++)if(!strcmp(s->name,c->slots[j].name))fail(c,"duplicate slot refused");
        if(total>UINT64_MAX-s->bound)fail(c,"reservation overflow");total+=s->bound;
    }
    if(total>UINT64_MAX-headroom||available(c)<total+headroom)fail(c,"complete retained slots plus nextwrite and headroom do not fit");
    for(int i=0;i<c->nslots;i++){
        slot_t *s=c->slots+i;char *base=NULL;int dir=parent_dir(c,s->name,&base,1);
        if(faccessat(dir,base,F_OK,AT_SYMLINK_NOFOLLOW)==0){close(dir);free(base);fail(c,"preexisting final refused");}
        char temporary[2048];if(snprintf(temporary,sizeof(temporary),"%s.part",base)>=(int)sizeof(temporary)){close(dir);free(base);fail(c,"slot path too long");}
        int fd=openat(dir,temporary,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        close(dir);free(base);if(fd<0)fail(c,"create-only reservation failed");
        /* posix_fallocate allocates physical blocks and earns actual quota.
           No ftruncate/sparse fallback is permitted. */
        int error=posix_fallocate(fd,0,(off_t)s->bound);struct stat st;
        if(error||fstat(fd,&st)||st.st_uid!=c->uid||st.st_nlink!=1||!S_ISREG(st.st_mode)||(uint64_t)st.st_size!=s->bound||(uint64_t)st.st_blocks*512<s->bound){
            close(fd);fail(c,"physical allocation/quota guarantee unavailable");
        }
        s->dev=st.st_dev;s->ino=st.st_ino;if(fsync(fd)){close(fd);fail(c,"reservation persistence failed");}close(fd);
    }
    if(available(c)<headroom)fail(c,"postallocation mandatory headroom lost");
    SEXP inputs=field(cfg,"inputs"),names=getAttrib(inputs,R_NamesSymbol);c->ninputs=(int)XLENGTH(inputs);
    if(TYPEOF(inputs)!=VECSXP||TYPEOF(names)!=STRSXP||c->ninputs!=13)fail(c,"exact three payload and ten proof snapshot allowlist required");
    c->inputs=calloc((size_t)c->ninputs,sizeof(input_t));if(!c->inputs)fail(c,"allocation failed");
    for(int i=0;i<c->ninputs;i++)c->inputs[i].sealed_fd=-1;
    c->snapshot_limit=number(field(cfg,"max_snapshot_bytes"),1024ULL*1024ULL*1024ULL);
    uint64_t sum=0;
    for(int i=0;i<c->ninputs;i++){input_t *in=c->inputs+i;in->sealed_fd=-1;SEXP row=VECTOR_ELT(inputs,i);in->name=strdup(CHAR(STRING_ELT(names,i)));in->path=strdup(text(field(row,"physical")));in->bytes=number(field(row,"bytes"),1024ULL*1024ULL*1024ULL);sum+=in->bytes;}
    if(sum>c->snapshot_limit)fail(c,"complete sealed input snapshot memory budget missing");
    UNPROTECT(1);return result;
}
static size_t bounded_write(const void *data,size_t size,size_t count,Rconnection con) {
    connection_t *w=con->private;cap_t *c=w->cap;current(c);slot_t *s=c->slots+w->index;
    if(size&&count>SIZE_MAX/size)fail(c,"serialization write integer overflow");
    size_t n=size*count;if((uint64_t)n>s->bound-s->written)fail(c,"serialization bound crossed before any overflowing write");
    const unsigned char *p=data;size_t done=0;
    while(done<n){size_t chunk=n-done;if(chunk>CHUNK)chunk=CHUNK;ssize_t wrote=pwrite(s->fd,p+done,chunk,(off_t)(s->written+done));
        if(wrote<0&&errno==EINTR)continue;if(wrote<=0)fail(c,"serialization write failed");done+=(size_t)wrote;}
    s->written+=n;return count;
}
static int bounded_vfprintf(Rconnection con,const char *format,va_list args) {
    connection_t *w=con->private;current(w->cap);slot_t *s=w->cap->slots+w->index;
    va_list count;va_copy(count,args);int n=vsnprintf(NULL,0,format,count);va_end(count);
    if(n<0||(uint64_t)n>s->bound-s->written)fail(w->cap,"formatted output exceeds prewrite ceiling");
    char *buf=malloc((size_t)n+1);if(!buf)fail(w->cap,"bounded format allocation failed");
    va_list copy;va_copy(copy,args);int made=vsnprintf(buf,(size_t)n+1,format,copy);va_end(copy);
    if(made!=n){free(buf);fail(w->cap,"format size changed");}
    bounded_write(buf,1,(size_t)n,con);free(buf);return n;
}
static int bounded_flush(Rconnection con){connection_t *w=con->private;slot_t *s=w->cap->slots+w->index;if(s->fd>=0&&fsync(s->fd)){w->cap->failed=1;return -1;}return 0;}
static void bounded_close(Rconnection con){connection_t *w=con->private;if(!w)return;slot_t *s=w->cap->slots+w->index;
    if(s->fd>=0){if(fsync(s->fd))w->cap->failed=1;close(s->fd);s->fd=-1;}s->closed=1;con->isopen=FALSE;}
static void bounded_destroy(Rconnection con){connection_t *w=con->private;if(!w)return;bounded_close(con);R_ReleaseObject(w->handle);free(w);con->private=NULL;}
SEXP r200_io_connection(SEXP handle,SEXP name) {
    cap_t *c=getcap(handle);const char *wanted=text(name);int index=-1;
    for(int i=0;i<c->nslots;i++)if(!strcmp(wanted,c->slots[i].name))index=i;
    if(index<0)fail(c,"undeclared output refused");slot_t *s=c->slots+index;
    if(s->opened||s->closed||s->committed)fail(c,"slot already spent; retry forbidden");
    char *base=NULL;int dir=parent_dir(c,s->name,&base,0);char tmp[2048];snprintf(tmp,sizeof(tmp),"%s.part",base);
    s->fd=openat(dir,tmp,O_RDWR|O_NOFOLLOW|O_CLOEXEC);close(dir);free(base);struct stat st;
    if(s->fd<0||fstat(s->fd,&st)||st.st_dev!=s->dev||st.st_ino!=s->ino||st.st_nlink!=1||st.st_uid!=c->uid||(uint64_t)st.st_size!=s->bound)fail(c,"reserved inode changed");
    s->opened=1;connection_t *w=calloc(1,sizeof(*w));if(!w)fail(c,"connection allocation failed");w->cap=c;w->index=index;w->handle=handle;R_PreserveObject(handle);
    Rconnection con;SEXP result=PROTECT(R_new_custom_connection(wanted,"wb","r200_bounded_reservation",&con));
    con->private=w;con->text=FALSE;con->isopen=TRUE;con->canread=FALSE;con->canwrite=TRUE;con->canseek=FALSE;con->blocking=TRUE;con->write=bounded_write;con->vfprintf=bounded_vfprintf;con->fflush=bounded_flush;con->close=bounded_close;con->destroy=bounded_destroy;
    UNPROTECT(1);return result;
}
SEXP r200_io_commit(SEXP handle,SEXP name) {
    cap_t *c=getcap(handle);slot_t *s=NULL;const char *wanted=text(name);
    for(int i=0;i<c->nslots;i++)if(!strcmp(wanted,c->slots[i].name))s=c->slots+i;
    if(!s||!s->opened||!s->closed||s->committed||!s->written)fail(c,"one successfully closed nonempty serialization required");
    char *base=NULL;int dir=parent_dir(c,s->name,&base,0);char tmp[2048];snprintf(tmp,sizeof(tmp),"%s.part",base);
    int fd=openat(dir,tmp,O_RDWR|O_NOFOLLOW|O_CLOEXEC);struct stat st;
    if(fd<0||fstat(fd,&st)||st.st_dev!=s->dev||st.st_ino!=s->ino||st.st_nlink!=1||st.st_uid!=c->uid){if(fd>=0)close(fd);close(dir);free(base);fail(c,"reserved commit inode changed");}
    /* Release only unused padding of THIS completed slot. Every future slot
       is already physically allocated; no future write borrows this space. */
    if(ftruncate(fd,(off_t)s->written)||fsync(fd)){close(fd);close(dir);free(base);fail(c,"completed serialization persistence failed");}close(fd);
    if(syscall(SYS_renameat2,dir,tmp,dir,base,RENAME_NOREPLACE)<0){close(dir);free(base);fail(c,"atomic no-replace commit unavailable or destination exists");}
    s->committed=1;
    if(fsync(dir)){close(dir);free(base);fail(c,"committed directory persistence uncertain");}close(dir);free(base);
    return ScalarReal((double)s->written);
}
SEXP r200_io_snapshot(SEXP handle,SEXP name) {
    cap_t *c=getcap(handle);input_t *in=NULL;const char *wanted=text(name);
    for(int i=0;i<c->ninputs;i++)if(!strcmp(wanted,c->inputs[i].name))in=c->inputs+i;
    if(!in)fail(c,"undeclared scientific input refused");
    if(in->sealed_fd<0){
        int source=physical_open(in->path,O_RDONLY);struct stat before,after;
        if(fstat(source,&before)||before.st_uid!=c->uid||before.st_nlink!=1||!S_ISREG(before.st_mode)||(uint64_t)before.st_size!=in->bytes){close(source);fail(c,"input inode/size/UID rejected");}
        if(c->snapshot_used>c->snapshot_limit-in->bytes){close(source);fail(c,"sealed snapshot memory ceiling");}
        int out=(int)syscall(SYS_memfd_create,"r200_owned_input",MFD_CLOEXEC|MFD_ALLOW_SEALING);
        if(out<0){close(source);fail(c,"sealed snapshot kernel API unavailable");}in->sealed_fd=out;
        unsigned char buf[CHUNK];uint64_t copied=0;
        while(copied<in->bytes){size_t need=(size_t)(in->bytes-copied);if(need>CHUNK)need=CHUNK;ssize_t got=read(source,buf,need);if(got<0&&errno==EINTR)continue;if(got<=0){close(source);fail(c,"input snapshot premature EOF");}
            size_t done=0;while(done<(size_t)got){ssize_t w=write(out,buf+done,(size_t)got-done);if(w<0&&errno==EINTR)continue;if(w<=0){close(source);fail(c,"snapshot write failed");}done+=(size_t)w;}copied+=(uint64_t)got;}
        unsigned char extra;ssize_t tail=read(source,&extra,1);
        if(tail!=0||fstat(source,&after)||before.st_dev!=after.st_dev||before.st_ino!=after.st_ino||before.st_size!=after.st_size||before.st_mtim.tv_sec!=after.st_mtim.tv_sec||before.st_mtim.tv_nsec!=after.st_mtim.tv_nsec||before.st_ctim.tv_sec!=after.st_ctim.tv_sec||before.st_ctim.tv_nsec!=after.st_ctim.tv_nsec){close(source);fail(c,"input changed while creating sealed snapshot");}
        close(source);
        if(fcntl(out,F_ADD_SEALS,F_SEAL_WRITE|F_SEAL_GROW|F_SEAL_SHRINK|F_SEAL_SEAL)<0)fail(c,"immutable snapshot seals unavailable");
        c->snapshot_used+=in->bytes;
    }
    char path[64];snprintf(path,sizeof(path),"/proc/self/fd/%d",in->sealed_fd);
    return mkString(path);
}
SEXP r200_io_fail(SEXP handle) {
    if(TYPEOF(handle)!=EXTPTRSXP||R_ExternalPtrTag(handle)!=install(TAG)||!R_ExternalPtrAddr(handle))Rf_error("opaque capability required");
    ((cap_t*)R_ExternalPtrAddr(handle))->failed=1;return ScalarLogical(1);
}
SEXP r200_io_validate_live(SEXP handle) { getcap(handle); return ScalarLogical(1); }
SEXP r200_io_inventory(SEXP handle) {
    if(TYPEOF(handle)!=EXTPTRSXP||R_ExternalPtrTag(handle)!=install(TAG)||!R_ExternalPtrAddr(handle))Rf_error("opaque audit capability required");
    cap_t *c=R_ExternalPtrAddr(handle);if(getpid()!=c->pid||getuid()!=c->uid)Rf_error("own process audit only");SEXP out=PROTECT(allocVector(VECSXP,c->nslots));
    for(int i=0;i<c->nslots;i++){slot_t *s=c->slots+i;SEXP row=PROTECT(allocVector(VECSXP,4)),names=PROTECT(allocVector(STRSXP,4));
        SET_STRING_ELT(names,0,mkChar("name"));SET_STRING_ELT(names,1,mkChar("committed"));SET_STRING_ELT(names,2,mkChar("bytes"));SET_STRING_ELT(names,3,mkChar("reserved_bound"));
        SET_VECTOR_ELT(row,0,mkString(s->name));SET_VECTOR_ELT(row,1,ScalarLogical(s->committed));SET_VECTOR_ELT(row,2,ScalarReal((double)s->written));SET_VECTOR_ELT(row,3,ScalarReal((double)s->bound));setAttrib(row,R_NamesSymbol,names);SET_VECTOR_ELT(out,i,row);UNPROTECT(2);}
    UNPROTECT(1);return out;
}
static const R_CallMethodDef calls[]={
 {"r200_io_activate",(DL_FUNC)&r200_io_activate,1},
 {"r200_io_connection",(DL_FUNC)&r200_io_connection,2},
 {"r200_io_commit",(DL_FUNC)&r200_io_commit,2},
 {"r200_io_snapshot",(DL_FUNC)&r200_io_snapshot,2},
 {"r200_io_fail",(DL_FUNC)&r200_io_fail,1},
 {"r200_io_inventory",(DL_FUNC)&r200_io_inventory,1},
 {"r200_io_validate_live",(DL_FUNC)&r200_io_validate_live,1},
 {NULL,NULL,0}
};
void R_init_pilot_owned_io(DllInfo *dll){R_registerRoutines(dll,NULL,calls,NULL,NULL);R_useDynamicSymbols(dll,FALSE);}
