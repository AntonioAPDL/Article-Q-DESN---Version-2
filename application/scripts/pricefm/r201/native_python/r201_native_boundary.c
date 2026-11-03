#define _GNU_SOURCE
#include "r201_native_boundary.h"
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/filter.h>
#include <linux/fs.h>
#include <linux/seccomp.h>
#include <math.h>
#include <poll.h>
#include <sched.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>

/* New pure-C ABI. This source does not link R or CPython and does not parse
 * grants, input manifests, target values or JSON. Runtime acceptance of this
 * newly built library is a separate, compute-only qualification.
 *
 * The instruction array in r201_scientific_boundary_v1 is byte-for-byte the
 * original r157 scientific policy. This library is inert until explicit calls.
 */
static struct r201_receipt_v1 receipt;
static _Atomic int lifecycle; /* 0 fresh, 4 preparing, 1 prepared, 2 entering, 3 ACK earned, -1 failed */
static int permit_fd_saved = -1, proof_fd = -1, ack_fd = -1;
static _Atomic(const char *) failure;

static int refuse(const char *why) {
    const char *empty = NULL;
    atomic_compare_exchange_strong(&failure, &empty, why);
    atomic_store(&lifecycle, -1);
    errno = EPERM;
    return -1;
}
const char *r201_last_error_v1(void) {
    const char *value = atomic_load(&failure);
    return value ? value : "no native refusal";
}
uint64_t r201_receipt_size_v1(void) { return sizeof(struct r201_receipt_v1); }

static double epoch(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_REALTIME, &value)) return -1.0;
    return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}
static int read_text(const char *path, char *out, size_t cap) {
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0 || cap < 2) { if (fd >= 0) close(fd); return -1; }
    size_t used = 0;
    while (used < cap - 1) {
        ssize_t got = read(fd, out + used, cap - 1 - used);
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) { close(fd); return -1; }
        if (!got) { out[used] = 0; close(fd); return (int)used; }
        used += (size_t)got;
    }
    char more;
    ssize_t got = read(fd, &more, 1);
    close(fd);
    if (got != 0) return -1;
    out[used] = 0;
    return (int)used;
}
static int proc_text(pid_t pid, const char *leaf, char *out, size_t cap) {
    char path[128];
    if (snprintf(path, sizeof path, "/proc/%ld/%s", (long)pid, leaf) >= (int)sizeof path)
        return -1;
    return read_text(path, out, cap);
}
static int process(pid_t pid, uint64_t *birth, pid_t *ppid,
                   pid_t *tracer, int *seccomp, int *nnp) {
    char text[16384];
    if (proc_text(pid, "stat", text, sizeof text) < 0) return -1;
    char *end = strrchr(text, ')');
    if (!end || end[1] != ' ') return -1;
    char *save = NULL, *token = strtok_r(end + 2, " ", &save);
    unsigned field = 3;
    *birth = 0; *ppid = -1;
    for (; token; token = strtok_r(NULL, " ", &save), ++field) {
        if (field == 4) { char *e; long v = strtol(token, &e, 10);
            if (*e || v <= 0 || v > INT_MAX) return -1;
            *ppid = (pid_t)v;
        }
        if (field == 22) { char *e; unsigned long long v = strtoull(token, &e, 10);
            if (*e || !v) return -1;
            *birth = (uint64_t)v;
            break;
        }
    }
    if (!*birth || *ppid <= 0 ||
        proc_text(pid, "status", text, sizeof text) < 0) return -1;
    *tracer = -1; *seccomp = -1; *nnp = -1;
    unsigned uid[4] = {UINT_MAX, UINT_MAX, UINT_MAX, UINT_MAX};
    for (char *line = strtok_r(text, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        long value;
        if (sscanf(line, "TracerPid:%ld", &value) == 1) *tracer = (pid_t)value;
        if (sscanf(line, "Seccomp:%d", seccomp) == 1) continue;
        if (sscanf(line, "NoNewPrivs:%d", nnp) == 1) continue;
        if (sscanf(line, "Uid:%u %u %u %u", &uid[0], &uid[1], &uid[2], &uid[3]) == 4) continue;
    }
    for (unsigned i = 0; i < 4; ++i) if (uid[i] != getuid()) return -1;
    return *tracer < 0 || *seccomp < 0 || *nnp < 0 ? -1 : 0;
}
static int decimal(const char *s, long *out) {
    if (!s || !*s || strlen(s) > 20) return -1;
    for (const char *p = s; *p; ++p) if (!isdigit((unsigned char)*p)) return -1;
    char *e; errno = 0; long value = strtol(s, &e, 10);
    if (errno || *e || value < 0 || value > INT_MAX) return -1;
    *out = value; return 0;
}
static int same_inode(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}
static int parent_fd(int fd, struct stat *out) {
    char path[128];
    snprintf(path, sizeof path, "/proc/%lld/fd/%d", (long long)receipt.owner_pid, fd);
    return stat(path, out);
}
static int fdinfo_flock(pid_t pid, int fd, const struct stat *held) {
    char path[128], text[8192];
    if (snprintf(path, sizeof path, "/proc/%ld/fdinfo/%d", (long)pid, fd) >= (int)sizeof path ||
        read_text(path, text, sizeof text) < 0) return -1;
    unsigned inode_rows = 0, flag_rows = 0, lock_rows = 0;
    int actual_flags = fcntl(permit_fd_saved, F_GETFL);
    if (actual_flags < 0) return -1;
    char *save = NULL;
    for (char *line = strtok_r(text, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        int consumed = 0;
        if (!strncmp(line, "ino:", 4)) {
            unsigned long long inode;
            if (++inode_rows != 1 || sscanf(line, "ino: %llu %n", &inode, &consumed) != 1 ||
                line[consumed] || inode != held->st_ino) return -1;
        } else if (!strncmp(line, "flags:", 6)) {
            unsigned long flags;
            if (++flag_rows != 1 || sscanf(line, "flags: %lo %n", &flags, &consumed) != 1 ||
                line[consumed] || (flags & O_ACCMODE) != (unsigned)(actual_flags & O_ACCMODE))
                return -1;
        } else if (!strncmp(line, "lock:", 5)) {
            char kind[16], advisory[16], access[16], begin[32], end[32];
            long long owner; unsigned major_id, minor_id; unsigned long long inode;
            if (++lock_rows != 1 ||
                sscanf(line, "lock: %*u: %15s %15s %15s %lld %x:%x:%llu %31s %31s %n",
                       kind, advisory, access, &owner, &major_id, &minor_id, &inode,
                       begin, end, &consumed) != 9 ||
                line[consumed] || strcmp(kind, "FLOCK") || strcmp(advisory, "ADVISORY") ||
                strcmp(access, "WRITE") || owner != receipt.owner_pid ||
                major_id != major(held->st_dev) || minor_id != minor(held->st_dev) ||
                inode != held->st_ino || strcmp(begin, "0") || strcmp(end, "EOF"))
                return -1;
        }
    }
    return inode_rows == 1 && flag_rows == 1 && lock_rows == 1 ? 0 : -1;
}
static int permit_live(void) {
    struct stat held, parent;
    if (fcntl(permit_fd_saved, F_GETFD) < 0 || fstat(permit_fd_saved, &held) ||
        !S_ISREG(held.st_mode) || held.st_uid != getuid() || held.st_nlink != 1 ||
        (held.st_mode & 0022) || held.st_dev != receipt.permit_device ||
        held.st_ino != receipt.permit_inode || parent_fd(permit_fd_saved, &parent) ||
        !same_inode(&held, &parent) ||
        fdinfo_flock(getpid(), permit_fd_saved, &held) ||
        fdinfo_flock((pid_t)receipt.owner_pid, permit_fd_saved, &held))
        return -1;
    /* Read only: never acquire, reacquire, replace, release or mutate a permit.
     * Both exact inherited descriptors must independently expose the existing
     * kernel FLOCK WRITE owned by the same still-live parent PID/birth.
     * Inaccessible or unsupported parent fdinfo refuses; qualification cannot
     * infer parent dumpability from the child's descriptor. */
    return 0;
}
static int peer_pipe(int fd, int child_mode) {
    struct stat held;
    if (fstat(fd, &held) || !S_ISFIFO(held.st_mode) ||
        (fcntl(fd, F_GETFL) & O_ACCMODE) != child_mode) return -1;
    char root[128];
    snprintf(root, sizeof root, "/proc/%lld/fd", (long long)receipt.owner_pid);
    DIR *directory = opendir(root);
    if (!directory) return -1;
    int found = 0;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
        long value;
        if (decimal(entry->d_name, &value)) continue;
        struct stat other;
        if (parent_fd((int)value, &other) || !same_inode(&held, &other)) continue;
        char info[128], text[1024];
        snprintf(info, sizeof info, "/proc/%lld/fdinfo/%ld",
                 (long long)receipt.owner_pid, value);
        if (read_text(info, text, sizeof text) < 0) continue;
        char *flags = strstr(text, "\nflags:");
        if (flags) ++flags;
        else if (!strncmp(text, "flags:", 6)) flags = text;
        if (flags) {
            unsigned long bits;
            if (sscanf(flags, "flags:%lo", &bits) == 1 &&
                (bits & O_ACCMODE) == (child_mode == O_WRONLY ? O_RDONLY : O_WRONLY))
                found = 1;
        }
    }
    closedir(directory);
    return found ? 0 : -1;
}
static int identities(int require_filter) {
    pid_t child_parent, child_tracer, parent_parent, parent_tracer;
    uint64_t child_birth, parent_birth; int child_seccomp, child_nnp, parent_seccomp, parent_nnp;
    char boot[64], child_cgroup[8192], parent_cgroup[8192], node[256];
    if (getpid() != receipt.child_pid || getppid() != receipt.owner_pid ||
        getuid() != receipt.uid || epoch() < 0 || epoch() >= receipt.expires_epoch ||
        process(getpid(), &child_birth, &child_parent, &child_tracer, &child_seccomp, &child_nnp) ||
        process((pid_t)receipt.owner_pid, &parent_birth, &parent_parent, &parent_tracer,
                &parent_seccomp, &parent_nnp) ||
        child_birth != receipt.child_start_ticks || parent_birth != receipt.owner_start_ticks ||
        child_parent != receipt.owner_pid || child_tracer != receipt.owner_pid ||
        (require_filter && (child_seccomp != 2 || child_nnp != 1)) ||
        read_text("/proc/sys/kernel/random/boot_id", boot, sizeof boot) < 0 ||
        proc_text(getpid(), "cgroup", child_cgroup, sizeof child_cgroup) < 0 ||
        proc_text((pid_t)receipt.owner_pid, "cgroup", parent_cgroup, sizeof parent_cgroup) < 0 ||
        gethostname(node, sizeof node) || !memchr(node, 0, sizeof node))
        return -1;
    boot[strcspn(boot, "\n")] = 0;
    if (strcmp(boot, receipt.boot_id) || strcmp(node, receipt.node) ||
        strcmp(child_cgroup, receipt.cgroup) || strcmp(child_cgroup, parent_cgroup) ||
        permit_live()) return -1;
    const char *job = getenv("SLURM_JOB_ID");
    if (!job || strcmp(job, receipt.job_id)) return -1;
    char job_component[64];
    snprintf(job_component, sizeof job_component, "job_%s", job);
    char *match = strstr(child_cgroup, job_component);
    if (!strstr(child_cgroup, "slurm") || !match ||
        (match[strlen(job_component)] && match[strlen(job_component)] != '/' &&
         match[strlen(job_component)] != '\n')) return -1;
    cpu_set_t affinity;
    CPU_ZERO(&affinity);
    if (sched_getaffinity(0, sizeof affinity, &affinity) || CPU_COUNT(&affinity) != 1)
        return -1;
    return 0;
}
int r201_prepare_v1(int64_t owner_pid, uint64_t owner_start_ticks,
                    int permit_fd, int role, double expires_epoch) {
    int expected = 0;
    if (!atomic_compare_exchange_strong(&lifecycle, &expected, 4))
        return refuse("native preparation is create-once");
    if (owner_pid <= 1 || owner_pid > INT_MAX || owner_pid != getppid() ||
        !owner_start_ticks || permit_fd < 3 ||
        (role != R201_ROLE_INITIAL_QUALIFICATION && role != R201_ROLE_LT_NO4_REFERENCE) ||
        !isfinite(expires_epoch) || expires_epoch <= epoch())
        return refuse("invalid typed owner role deadline");
    memset(&receipt, 0, sizeof receipt);
    receipt.abi_version = R201_ABI_VERSION; receipt.role = (uint32_t)role;
    receipt.uid = getuid(); receipt.child_pid = getpid(); receipt.owner_pid = owner_pid;
    receipt.owner_start_ticks = owner_start_ticks; receipt.expires_epoch = expires_epoch;
    pid_t ppid, tracer; int seccomp, nnp;
    if (process(getpid(), &receipt.child_start_ticks, &ppid, &tracer, &seccomp, &nnp))
        return refuse("actual child lifetime unavailable");
    char boot[64]; const char *job = getenv("SLURM_JOB_ID"); long numeric;
    if (decimal(job, &numeric) || numeric <= 0 || strlen(job) >= sizeof receipt.job_id ||
        read_text("/proc/sys/kernel/random/boot_id", boot, sizeof boot) < 0 ||
        proc_text(getpid(), "cgroup", receipt.cgroup, sizeof receipt.cgroup) < 0 ||
        gethostname(receipt.node, sizeof receipt.node) ||
        !memchr(receipt.node, 0, sizeof receipt.node))
        return refuse("actual native Slurm namespace unavailable");
    boot[strcspn(boot, "\n")] = 0;
    if (strlen(boot) != 36) return refuse("actual boot identity unavailable");
    memcpy(receipt.boot_id, boot, 37); strcpy(receipt.job_id, job);
    permit_fd_saved = permit_fd;
    struct stat held;
    if (fstat(permit_fd_saved, &held)) return refuse("inherited permit missing");
    receipt.permit_device = held.st_dev; receipt.permit_inode = held.st_ino;
    long inherited, proof, ack;
    if (decimal(getenv("R154_GLOBAL_PERMIT_LOCK_FD"), &inherited) || inherited != permit_fd ||
        decimal(getenv("R157_FILTER_PROOF_FD"), &proof) ||
        decimal(getenv("R157_FILTER_ACK_FD"), &ack) ||
        proof < 3 || ack < 3 || proof == ack || proof == permit_fd || ack == permit_fd ||
        !getenv("R157_FILTER_TOKEN") ||
        strcmp(getenv("R157_FILTER_TOKEN"), "R157_TSYNC_FORK_DENIAL_READY_V1"))
        return refuse("exact inherited original handshake unavailable");
    proof_fd = (int)proof; ack_fd = (int)ack;
    if (identities(0) || peer_pipe(proof_fd, O_WRONLY) || peer_pipe(ack_fd, O_RDONLY))
        return refuse("actual owner trace permit or handshake pipe mismatch");
    expected = 4;
    if (!atomic_compare_exchange_strong(&lifecycle, &expected, 1))
        return refuse("concurrent preparation refusal remains terminal");
    return 0;
}
int r201_scientific_boundary_v1(void) {
    int expected = 1;
    if (!atomic_compare_exchange_strong(&lifecycle, &expected, 2) || identities(0))
        return refuse("actual prepared owner required before once-only kernel transition");
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
        return refuse("mandatory original TSYNC fork-denial boundary failed");
    const char *token = "R157_TSYNC_FORK_DENIAL_READY_V1";
    size_t length = strlen(token);
    if (write(proof_fd, token, length) != (ssize_t)length)
        return refuse("actual original proof pipe write failed");
    if (close(proof_fd)) return refuse("actual proof close failed");
    proof_fd = -1;
    struct pollfd pending = {.fd=ack_fd, .events=POLLIN};
    int ready;
    for (;;) {
        double remaining = receipt.expires_epoch - epoch();
        if (remaining <= 0) return refuse("actual parent ACK deadline expired");
        int milliseconds = remaining > INT_MAX / 1000.0 ? INT_MAX : (int)(remaining * 1000);
        ready = poll(&pending, 1, milliseconds);
        if (ready < 0 && errno == EINTR) continue;
        break;
    }
    char reply = 0;
    if (ready != 1 || !(pending.revents & POLLIN) ||
        read(ack_fd, &reply, 1) != 1 || reply != '1')
        return refuse("actual original supervisor ACK not earned");
    if (close(ack_fd)) return refuse("actual ACK close failed");
    ack_fd = -1;
    if (identities(1)) return refuse("actual owner lifetime changed across kernel ACK");
    receipt.state = R201_STATE_ACK_EARNED;
    expected = 2;
    if (!atomic_compare_exchange_strong(&lifecycle, &expected, R201_STATE_ACK_EARNED))
        return refuse("concurrent boundary refusal remains terminal");
    return 0;
}
int r201_validate_live_v1(void) {
    if (atomic_load(&lifecycle) != R201_STATE_ACK_EARNED || identities(1))
        return refuse("actual once-earned native lifetime is no longer live");
    return 0;
}
int r201_receipt_v1(struct r201_receipt_v1 *out) {
    if (!out || r201_validate_live_v1()) return refuse("actual live native receipt required");
    memcpy(out, &receipt, sizeof receipt);
    return 0;
}

static int basename_only(const char *name) {
    if (!name || !*name || strlen(name) > 128 ||
        !strcmp(name, ".") || !strcmp(name, "..")) return -1;
    for (const unsigned char *p = (const unsigned char *)name; *p; ++p)
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') || *p == '_' || *p == '-' || *p == '.'))
            return -1;
    return 0;
}
int r201_rename_noreplace_v1(int directory_fd, const char *partial_basename,
                            const char *final_basename) {
    if (r201_validate_live_v1()) return -1;
    struct stat directory, partial, final;
    if (directory_fd < 3 || fstat(directory_fd, &directory) ||
        !S_ISDIR(directory.st_mode) || directory.st_uid != getuid() ||
        (directory.st_mode & 0777) != 0700 ||
        basename_only(partial_basename) || basename_only(final_basename) ||
        !strcmp(partial_basename, final_basename) ||
        fstatat(directory_fd, partial_basename, &partial, AT_SYMLINK_NOFOLLOW) ||
        !S_ISREG(partial.st_mode) || partial.st_uid != getuid() ||
        partial.st_nlink != 1 || (partial.st_mode & 0777) != 0600)
        return refuse("owned private directory and paid partial required");
    errno = 0;
    if (!fstatat(directory_fd, final_basename, &final, AT_SYMLINK_NOFOLLOW) || errno != ENOENT)
        return refuse("existing or unprovable final refuses without cleanup");
    if (syscall(SYS_renameat2, directory_fd, partial_basename,
                directory_fd, final_basename, RENAME_NOREPLACE))
        return refuse("kernel renameat2 NOREPLACE failed; no fallback");
    /* Final remains paid and retained if fsync or lifetime validation fails. */
    if (fsync(directory_fd) || r201_validate_live_v1())
        return refuse("retained final commit fsync or live proof failed");
    return 0;
}
