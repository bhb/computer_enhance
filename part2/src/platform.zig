const builtin = @import("builtin");

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
