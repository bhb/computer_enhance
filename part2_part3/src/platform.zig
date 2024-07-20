const builtin = @import("builtin");
const std = @import("std");

const time = @cImport({
    @cInclude("sys/time.h");
});

pub const OsTimerFreq = 1_000_000;

pub fn readOsTimer() u64 {
    var value = time.timeval{
        .tv_sec = 0, // Seconds
        .tv_usec = 0, // Microseconds
    };

    _ = time.gettimeofday(&value, null);

    return OsTimerFreq * @as(u64, @bitCast(value.tv_sec)) + @as(u32, @bitCast(value.tv_usec));
}

// Might need antoher instruction to figure out timer frequency?
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
