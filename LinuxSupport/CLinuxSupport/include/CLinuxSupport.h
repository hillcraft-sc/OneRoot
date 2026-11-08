// Linux C APIs Swift's Glibc module doesn't bring in, for the shared core
// (OneRootCore) on Linux only.
#ifndef CLINUXSUPPORT_H
#define CLINUXSUPPORT_H
#ifdef __linux__
#include <sys/types.h>
#include <sys/xattr.h>

/// copy_file_range(2) from the current offsets of both files: the kernel
/// copies (or reflinks, on btrfs/XFS) without the data passing through
/// OneRoot. Returns bytes copied, 0 at the end, -1 with errno set.
ssize_t oneroot_copy_file_range(int in_fd, int out_fd, size_t length);
#endif
#endif
