// Swift's main queue (libdispatch) as a file descriptor GLib can watch, and
// a call to run what's queued on it — what Foundation's run loop does on
// Linux, for an app whose main loop is GLib's.
#ifndef CMAINQUEUE_H
#define CMAINQUEUE_H

/// The descriptor that becomes readable when work is queued on the main
/// queue (set non-blocking).
int oneroot_main_queue_fd(void);

/// Clears the wake-up and runs everything queued on the main queue.
void oneroot_drain_main_queue(void);

#endif
