#define _GNU_SOURCE
#include <R.h>
#include <Rinternals.h>
#include <errno.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

/* Same no-process-creation policy as the old pre-exec boundary, applied with
 * TSYNC to every existing R thread after the fully traced bootstrap. */
SEXP r157_scientific_boundary(SEXP unused) {
    const uint32_t deny = SECCOMP_RET_ERRNO | EPERM;
    const uint32_t unavailable = SECCOMP_RET_ERRNO | ENOSYS;
    struct sock_filter f[] = {
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,4),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,0xc000003e,1,0),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,0),
        BPF_JUMP(BPF_JMP|BPF_JSET|BPF_K,0x40000000,0,1),
        BPF_STMT(BPF_RET|BPF_K,deny),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,57,0,1),
        BPF_STMT(BPF_RET|BPF_K,deny),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,58,0,1),
        BPF_STMT(BPF_RET|BPF_K,deny),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,435,0,1),
        BPF_STMT(BPF_RET|BPF_K,unavailable),
        BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,56,0,3),
        BPF_STMT(BPF_LD|BPF_W|BPF_ABS,16),
        BPF_JUMP(BPF_JMP|BPF_JSET|BPF_K,0x10000,1,0),
        BPF_STMT(BPF_RET|BPF_K,deny),
        BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW)
    };
    struct sock_fprog p = {.len=(unsigned short)(sizeof(f)/sizeof(f[0])),.filter=f};
    if (prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0)!=0 ||
        syscall(SYS_seccomp,SECCOMP_SET_MODE_FILTER,SECCOMP_FILTER_FLAG_TSYNC,&p)!=0)
        Rf_error("mandatory TSYNC scientific fork-denial boundary failed");
    const char *token=getenv("R157_FILTER_TOKEN");
    const char *out=getenv("R157_FILTER_PROOF_FD"), *in=getenv("R157_FILTER_ACK_FD");
    if (!token || !out || !in) Rf_error("missing owned supervisor handshake");
    int writefd=atoi(out),readfd=atoi(in);size_t length=strlen(token);
    if (write(writefd,token,length)!=(ssize_t)length) Rf_error("scientific proof write failed");
    close(writefd);char reply=0;
    if (read(readfd,&reply,1)!=1 || reply!='1') Rf_error("scientific target access not acknowledged");
    close(readfd);
    return ScalarLogical(1);
}
