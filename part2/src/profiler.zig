const std = @import("std");
const platform = @import("./platform.zig");

pub const ProfilerEntry = struct {
    name: []const u8 = undefined,
    begin: u64 = undefined,
    end: u64 = undefined,

    pub fn elapsed(self: ProfilerEntry) u64 {
        return self.end - self.begin;
    }
};

pub const Profiler = struct {
    idx: u32 = 0,
    entries: []ProfilerEntry,
    begin: u64 = 0, // We are counting timer, so after the machine boots, it will never be zero
    end: u64 = undefined,

    pub fn init(entries: []ProfilerEntry) Profiler {
        return Profiler{
            .idx = 0,
            .entries = entries,
        };
    }

    pub fn start(self: *Profiler, name: []const u8) u32 {
        defer self.idx += 1;

        if (self.begin == 0) {
            self.begin = platform.readCpuTimer();
        }

        self.entries[self.idx].name = name;
        self.entries[self.idx].begin = platform.readCpuTimer();

        return self.idx;
    }

    pub fn stop(self: *Profiler, idx: u32) void {
        self.entries[idx].end = platform.readCpuTimer();
    }

    pub fn print_summary(self: *Profiler, stdout: std.fs.File.Writer) !void {
        self.end = platform.readCpuTimer();

        const cpu_freq: u64 = platform.estimateCpuFreq(100);
        const total = self.end - self.begin;

        try stdout.print("Total time: {d:.2}ms (CPU freq {d})\n", .{ 1000.0 * @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(cpu_freq)), cpu_freq });

        for (0..self.idx) |idx| {
            const entry = self.entries[idx];
            const elapsed = entry.elapsed();
            const percent = 100.0 * @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(total));

            try stdout.print("{s}: {d} ({d:.2}%)\n", .{ entry.name, elapsed, percent });
        }
    }
};

test "readOSTimer" {
    try std.testing.expect(1 < platform.readOsTimer());
}

test "readCpuTimer" {
    try std.testing.expect(1 < platform.readCpuTimer());
}

test "estimateCpuFreq" {
    try std.testing.expect(24_000_000 < platform.estimateCpuFreq(1000));
    try std.testing.expect(24_000_000 < platform.estimateCpuFreq(100));
}
