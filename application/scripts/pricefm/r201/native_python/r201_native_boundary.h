#ifndef PRICEFM_R201_NATIVE_BOUNDARY_H
#define PRICEFM_R201_NATIVE_BOUNDARY_H
#include <stdint.h>
#define R201_ABI_VERSION 1u
#define R201_ROLE_INITIAL_QUALIFICATION 1
#define R201_ROLE_LT_NO4_REFERENCE 2
#define R201_STATE_ACK_EARNED 3
struct r201_receipt_v1 {
    uint32_t abi_version, state, role, uid;
    int64_t child_pid, owner_pid;
    uint64_t child_start_ticks, owner_start_ticks, permit_device, permit_inode;
    double expires_epoch;
    char boot_id[37], job_id[21], node[256], cgroup[8192];
};
/* All int functions return 0 on success and -1 on terminal refusal.
 * Preparation is not an ACK or a grant. No function accepts a callback or
 * caller-supplied acknowledgement. The library has no active constructor. */
int r201_prepare_v1(int64_t owner_pid, uint64_t owner_start_ticks,
                    int permit_fd, int role, double expires_epoch);
int r201_scientific_boundary_v1(void);
int r201_validate_live_v1(void);
int r201_rename_noreplace_v1(int directory_fd, const char *partial_basename,
                            const char *final_basename);
int r201_receipt_v1(struct r201_receipt_v1 *out);
uint64_t r201_receipt_size_v1(void);
const char *r201_last_error_v1(void);
#endif
