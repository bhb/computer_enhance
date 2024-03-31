// To run:
// zig run src/timer.zig

const std = @import("std");
const platform = @import("./platform.zig");

pub fn main() !void {
    const OsTimerFreq: u64 = platform.OsTimerFreq;
    std.debug.print("    OS Freq: {d}\n", .{OsTimerFreq});

    const os_start = platform.readOsTimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;

    while (os_elapsed < OsTimerFreq) {
        os_end = platform.readOsTimer();
        os_elapsed = os_end - os_start;
    }

    std.debug.print("   OS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print(" OS Seconds: {d:.4}\n", .{@as(f64, @floatFromInt(os_elapsed)) / @as(f64, @floatFromInt(OsTimerFreq))});
}
