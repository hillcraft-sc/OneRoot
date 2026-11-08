#include "CMainQueue.h"
#include <fcntl.h>
#include <stdint.h>
#include <unistd.h>

// libdispatch's hooks for run loops (CoreFoundation uses the same ones).
extern int _dispatch_get_main_queue_handle_4CF(void);
extern void _dispatch_main_queue_callback_4CF(void *message);

int oneroot_main_queue_fd(void) {
    int fd = _dispatch_get_main_queue_handle_4CF();
    int flags = fcntl(fd, F_GETFL);
    if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    return fd;
}

void oneroot_drain_main_queue(void) {
    uint64_t value;
    // An eventfd: reading resets it, so GLib stops reporting it ready.
    (void)read(_dispatch_get_main_queue_handle_4CF(), &value, sizeof value);
    _dispatch_main_queue_callback_4CF(0);
}
