const builtin = @import("builtin");
const std = @import("std");

const time = @cImport({
    @cInclude("sys/time.h");
});

const resource = @cImport({
    @cInclude("sys/resource.h");
});

pub const OsTimerFreq = 1_000_000;

// sysctl -a hw machdep.cpu | grep page
// hw.pagesize: 16384
// hw.pagesize32: 16384
// so page size is about 16K

// man 2 getrusage
pub fn pageFaults() u64 {
    const default_timeval = resource.timeval{
        .tv_sec = 0, // Seconds
        .tv_usec = 0, // Microseconds
    };

    var r_usage = resource.rusage{
        // user time used
        .ru_utime = default_timeval,
        // system time used
        .ru_stime = default_timeval,
        .ru_maxrss = 0, // max resident set size
        .ru_ixrss = 0, // integral shared text memory size
        .ru_idrss = 0, // integral unshared data size
        .ru_isrss = 0, // integral unshared stack size
        .ru_minflt = 0, // page reclaims
        .ru_majflt = 0, // page faults
        .ru_nswap = 0, // swaps
        .ru_inblock = 0, // block input operations
        .ru_oublock = 0, // block output operations
        .ru_msgsnd = 0, // messages sent
        .ru_msgrcv = 0, // messages received
        .ru_nsignals = 0, // signals received
        .ru_nvcsw = 0, // voluntary context switches
        .ru_nivcsw = 0, // involuntary context switches
    };

    // First param is either RUSAGE_SELF or RUSAGE_CHILDREN.
    _ = resource.getrusage(resource.RUSAGE_SELF, &r_usage);

    const x = @as(u64, @bitCast(r_usage.ru_minflt));
    return x;
}

pub fn readOsTimer() u64 {
    var value = time.timeval{
        .tv_sec = 0, // Seconds
        .tv_usec = 0, // Microseconds
    };

    _ = time.gettimeofday(&value, null);

    return OsTimerFreq * @as(u64, @bitCast(value.tv_sec)) + @as(u32, @bitCast(value.tv_usec));
}

// Might need another instruction to figure out timer frequency?
// https://cpufun.substack.com/i/32886352/aarch-timer

pub fn readCpuFreq() u64 {
    var val: u64 = undefined;

    asm volatile ("mrs %[val], cntvfreq_el0"
        : [val] "=r" (val),
    );

    return val;
}

pub fn readCpuTimer() u64 {
    var val: u64 = undefined;

    asm volatile ("mrs %[val], cntvct_el0"
        : [val] "=r" (val),
    );

    return val;
}

pub fn estimateCpuFreq(msToWait: u64) u64 {
    const cpu_start = readCpuTimer();
    const os_start = readOsTimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;

    const osWaitTime = OsTimerFreq * msToWait / 1000;

    while (os_elapsed < osWaitTime) {
        os_end = readOsTimer();
        os_elapsed = os_end - os_start;
    }

    const cpu_end = readCpuTimer();
    const cpu_elapsed = cpu_end - cpu_start;
    var cpu_freq: u64 = undefined;

    if (0 < os_elapsed) {
        cpu_freq = OsTimerFreq * cpu_elapsed / os_elapsed;
    }

    return cpu_freq;
}
