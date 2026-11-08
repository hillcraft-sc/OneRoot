#ifdef __linux__
#define _GNU_SOURCE
#include <unistd.h>
#include "CLinuxSupport.h"

ssize_t oneroot_copy_file_range(int in_fd, int out_fd, size_t length) {
    return copy_file_range(in_fd, NULL, out_fd, NULL, length, 0);
}
#endif
