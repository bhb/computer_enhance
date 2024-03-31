// See https://www.computerenhance.com/p/introduction-to-rdtsc

// To run:
// zig run src/timer.zig

// Should look something like
//    OS Freq: 1000000
//    OS Timer: 1711917870445228 -> 1711917871445228 = 1000000 elapsed
//    OS Seconds: 1.0000
//

const std = @import("std");
const platform = @import("./platform.zig");

pub fn main() !void {
    const OsTimerFreq: u64 = platform.OsTimerFreq;
    std.debug.print("    OS Freq: {d}\n", .{OsTimerFreq});

    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;
    const os_start = platform.readOsTimer();

    while (os_elapsed < OsTimerFreq) {
        os_end = platform.readOsTimer();
        os_elapsed = os_end - os_start;
    }

    std.debug.print("   OS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print("   OS Seconds: {d:.4}\n", .{@as(f64, @floatFromInt(os_elapsed)) / @as(f64, @floatFromInt(OsTimerFreq))});
}
