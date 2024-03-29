const builtin = @import("builtin");

const time = @cImport({
    @cInclude("sys/time.h");
});

const OsTimerFreq = 1_000_000;

pub fn readOSTimer() i64 {
    var value = time.timeval{
        .tv_sec = 0, // Seconds
        .tv_usec = 0, // Microseconds
    };

    _ = time.gettimeofday(&value, null);

    return value.tv_sec;
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
