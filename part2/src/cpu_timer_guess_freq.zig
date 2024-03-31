// See https://www.computerenhance.com/p/introduction-to-rdtsc

// To run:
// zig run src/cpu_timer_guess_freq.zig

// Should look something like

const std = @import("std");
const platform = @import("./platform.zig");

pub fn main() !void {
    // Lower values will be less and less accurate when computing the CPU frequency
    const msToWait = 1000;

    const OsTimerFreq: u64 = platform.OsTimerFreq;
    std.debug.print("OS Freq: {d}\n", .{OsTimerFreq});

    const cpu_start = platform.readCpuTimer();
    const os_start = platform.readOsTimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;

    const osWaitTime = OsTimerFreq * msToWait / 1000;

    while (os_elapsed < osWaitTime) {
        os_end = platform.readOsTimer();
        os_elapsed = os_end - os_start;
    }

    const cpu_end = platform.readCpuTimer();
    const cpu_elapsed = cpu_end - cpu_start;
    var cpu_freq: u64 = undefined;

    if (0 < os_elapsed) {
        cpu_freq = OsTimerFreq * cpu_elapsed / os_elapsed;
    }

    std.debug.print("OS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print("OS Seconds: {d:.4}\n", .{@as(f64, @floatFromInt(os_elapsed)) / @as(f64, @floatFromInt(OsTimerFreq))});

    std.debug.print("CPU Timer: {d} -> {d} = {d} elapsed\n", .{ cpu_start, cpu_end, cpu_elapsed });
    std.debug.print("CPU Freq: {d:.4} (guessed)\n", .{cpu_freq});
}
