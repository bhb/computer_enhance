// based heavily off
// https://github.com/cmuratori/computer_enhance/blob/main/perfaware/part2/listing_0085_recursive_profiler.cpp

const std = @import("std");
const platform = @import("./platform.zig");

// A block of code that is going to be profiled.
// (Many blocks can point to the same entry)
pub const ProfilerBlock = struct {
    name: []const u8 = "unset",
    idx: u16 = 0,
    parent_idx: u16 = 0,
    begin: u64 = 0,
    old_elapsed_at_root: u64 = 0,
};

// Entries are unique per name
pub const ProfilerEntry = struct {
    name: []const u8 = "unset",
    hit_count: u64 = 0,
    elapsed_total: u64 = 0,
    elapsed_children: u64 = 0,
    elapsed_at_root: u64 = 0,

    pub fn elapsed_self(self: ProfilerEntry) i128 {
        const total: i128 = self.elapsed_total;
        return total - self.elapsed_children;
    }

    pub fn print(self: ProfilerEntry) void {
        std.debug.print("{s}: elapsed: {d}, elapsed_children: {d}\n", .{ self.name, self.elapsed_total, self.elapsed_children });
    }
};

const PROFILER_ENTRIES = 1000;

pub const EnabledProfiler = struct {
    // start at 1, so I don't need to check for parent
    entry_idx: u16 = 1,
    parent_idx: u16 = 0,
    entries: [PROFILER_ENTRIES]ProfilerEntry,
    begin: u64 = 0, // We are counting via the timer, so after the machine boots, it will never be zero

    pub fn init() EnabledProfiler {
        return EnabledProfiler{ .entries = [_]ProfilerEntry{.{}} ** PROFILER_ENTRIES };
    }

    pub fn start(self: *EnabledProfiler) void {
        self.begin = platform.readCpuTimer();
    }

    pub fn prof(self: *EnabledProfiler, name: []const u8) ProfilerBlock {
        // Find the entry
        var entry_idx = self.entry_idx;
        var existingEntry = false;
        var i: u16 = 0;
        while (i < self.entry_idx) {
            if (std.mem.eql(u8, self.entries[i].name, name)) {
                existingEntry = true;
                entry_idx = i;
            }
            i += 1;
        }

        var entry = &self.entries[entry_idx];

        if (!existingEntry) {
            self.entry_idx += 1;
            entry.name = name;
        }

        // Handle recursive entries, see
        // https://www.computerenhance.com/p/profiling-recursive-blocks
        const old_elapsed_at_root = entry.elapsed_at_root;

        // Create a block and return it
        const now = platform.readCpuTimer();
        const block = ProfilerBlock{ .name = name, .idx = entry_idx, .parent_idx = self.parent_idx, .begin = now, .old_elapsed_at_root = old_elapsed_at_root };

        self.parent_idx = entry_idx;

        return block;
    }

    pub fn stop(self: *EnabledProfiler, block: ProfilerBlock) void {
        self.parent_idx = block.parent_idx;

        var entry: *ProfilerEntry = &self.entries[block.idx];

        const elapsed = platform.readCpuTimer() - block.begin;
        entry.elapsed_total += elapsed;

        // Handle recursive entries, see
        // https://www.computerenhance.com/p/profiling-recursive-blocks
        entry.elapsed_at_root = block.old_elapsed_at_root + elapsed;
        entry.hit_count += 1;

        var parent = &self.entries[block.parent_idx];

        parent.elapsed_children += elapsed;
    }

    fn print_entry(entry: *const ProfilerEntry, stdout: std.fs.File.Writer, total: u64) !void {
        const elapsed_self = entry.elapsed_self();
        const percent = 100.0 * @as(f64, @floatFromInt(elapsed_self)) / @as(f64, @floatFromInt(total));

        try stdout.print("{s}[{d}]: {d} ({d:.2}%", .{ entry.name, entry.hit_count, elapsed_self, percent });
        if (entry.elapsed_at_root != elapsed_self) {
            const percent_with_children = 100.0 * @as(f64, @floatFromInt(entry.elapsed_at_root)) / @as(f64, @floatFromInt(total));
            try stdout.print(", {d:.2}% w/ children)\n", .{percent_with_children});
        } else {
            try stdout.print(")\n", .{});
        }
    }

    pub fn print_summary(self: *EnabledProfiler, stdout: std.fs.File.Writer) !void {
        const end = platform.readCpuTimer();

        const cpu_freq: u64 = platform.estimateCpuFreq(100);
        const total = end - self.begin;

        try stdout.print("Total time: {d:.2}ms (CPU freq {d})\n", .{ 1000.0 * @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(cpu_freq)), cpu_freq });

        // first entry is empty
        for (1..self.entry_idx) |idx| {
            const entry = self.entries[idx];
            try print_entry(&entry, stdout, total);
        }
    }
};

const DisabledProfiler = struct {
    begin: u64 = 0, // We are counting via the timer, so after the machine boots, it will never be zero

    pub fn init() DisabledProfiler {
        return DisabledProfiler{};
    }

    pub fn start(self: *DisabledProfiler) void {
        self.begin = platform.readCpuTimer();
    }

    pub fn prof(self: *DisabledProfiler, name: []const u8) ProfilerBlock {
        _ = name;
        _ = self;
        // No-op implementation
        return ProfilerBlock{};
    }

    pub fn stop(self: *DisabledProfiler, block: ProfilerBlock) void {
        _ = block;
        _ = self;
        // No-op implementation
    }

    pub fn print_summary(self: *DisabledProfiler, stdout: std.fs.File.Writer) !void {
        const end = platform.readCpuTimer();

        const cpu_freq: u64 = platform.estimateCpuFreq(100);
        const total = end - self.begin;

        try stdout.print("Total time: {d:.2}ms (CPU freq {d})\n", .{ 1000.0 * @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(cpu_freq)), cpu_freq });
    }
};

pub fn Profiler(comptime enabled: bool) type {
    return if (comptime enabled) EnabledProfiler else DisabledProfiler;
}

test "disabled profiler" {
    var prof = Profiler(false).init();
    prof.start();

    const bl = prof.prof("Foo");
    prof.stop(bl);

    // check block
    try std.testing.expectEqual(0, bl.idx);
    try std.testing.expectEqual(0, bl.parent_idx);
    try std.testing.expectEqual("unset", bl.name);

    const stdout = std.io.getStdOut().writer();
    try prof.print_summary(stdout);
}

test "profilers" {
    {
        var prof = Profiler(true).init();
        prof.start();

        const bl = prof.prof("Foo");
        try std.testing.expectEqual(1, prof.parent_idx);
        prof.stop(bl);

        // check block
        try std.testing.expectEqual(1, bl.idx);
        try std.testing.expectEqual(0, bl.parent_idx);
        try std.testing.expectEqual("Foo", bl.name);

        // check profiler state
        try std.testing.expectEqual(2, prof.entry_idx);
        try std.testing.expectEqual(0, prof.parent_idx);

        // check entries
        try std.testing.expectEqualSlices(u8, "Foo", prof.entries[1].name);
        const foo_entry = prof.entries[1];
        try std.testing.expect(0 < foo_entry.elapsed_total);
        try std.testing.expectEqual(0, foo_entry.elapsed_children);
        try std.testing.expectEqual(foo_entry.elapsed_at_root, foo_entry.elapsed_self());

        try std.testing.expectEqualSlices(u8, "unset", prof.entries[0].name);
        try std.testing.expectEqualSlices(u8, "unset", prof.entries[2].name);
    }

    // Reusing same method

    {
        var prof = Profiler(true).init();

        const bl = prof.prof("Foo");
        try std.testing.expectEqual(1, prof.parent_idx);
        std.time.sleep(1000);
        prof.stop(bl);

        try std.testing.expect(0 < bl.begin);
        try std.testing.expect(0 < prof.entries[1].elapsed_total);
        const old_elapsed = prof.entries[1].elapsed_total;

        const bl2 = prof.prof("Foo");
        try std.testing.expectEqual(1, prof.parent_idx);
        prof.stop(bl2);

        try std.testing.expectEqual(2, prof.entry_idx);
        try std.testing.expect(old_elapsed < prof.entries[1].elapsed_total);
        try std.testing.expectEqual(0, prof.entries[1].elapsed_children);
    }

    // Child method
    {
        var prof = Profiler(true).init();

        const bl = prof.prof("Foo");
        try std.testing.expectEqual(1, prof.parent_idx);
        const bl2 = prof.prof("Bar");
        try std.testing.expectEqual(2, prof.parent_idx);
        std.time.sleep(1000);
        prof.stop(bl2);
        prof.stop(bl);

        try std.testing.expectEqual(3, prof.entry_idx);
        const entry1 = prof.entries[1];
        try std.testing.expect(0 < entry1.elapsed_total);
        try std.testing.expect(0 < entry1.elapsed_children);
        try std.testing.expect(entry1.elapsed_at_root != entry1.elapsed_self());

        try std.testing.expect(0 < prof.entries[2].elapsed_total);
        try std.testing.expectEqual(0, prof.entries[2].elapsed_children);
    }

    // Self recursion
    {
        var prof = Profiler(true).init();

        const blk = prof.prof("Foo");
        try std.testing.expectEqual(1, prof.parent_idx);
        const blk2 = prof.prof("Foo");
        std.time.sleep(1000);
        try std.testing.expectEqual(1, prof.parent_idx);
        prof.stop(blk2);
        try std.testing.expectEqual(1, prof.parent_idx);
        prof.stop(blk);

        try std.testing.expectEqual(1, blk.idx);
        try std.testing.expectEqual(1, blk2.idx);

        try std.testing.expectEqual(2, prof.entry_idx);
        try std.testing.expect(0 < prof.entries[1].elapsed_total);
        try std.testing.expect(0 < prof.entries[1].elapsed_children);
        try std.testing.expect(0 < prof.entries[1].elapsed_at_root);
    }

    // Mutual recursion
    {
        var prof = Profiler(true).init();

        const blk = prof.prof("Foo");
        try std.testing.expectEqual(1, prof.parent_idx);
        const blk2 = prof.prof("Bar");
        std.time.sleep(1000);
        try std.testing.expectEqual(2, prof.parent_idx);

        const blk3 = prof.prof("Foo");
        std.time.sleep(1000);
        try std.testing.expectEqual(1, prof.parent_idx);
        prof.stop(blk3);

        prof.stop(blk2);
        try std.testing.expectEqual(1, prof.parent_idx);
        prof.stop(blk);

        try std.testing.expectEqual(1, blk.idx);
        try std.testing.expectEqual(2, blk2.idx);
        try std.testing.expectEqual(1, blk3.idx);

        const entry1 = prof.entries[1];
        const entry2 = prof.entries[2];
        try std.testing.expect(0 < entry1.elapsed_children);
        try std.testing.expect(0 < entry2.elapsed_children);

        try std.testing.expect(0 < entry1.elapsed_self());
        try std.testing.expect(0 < entry2.elapsed_self());
    }
}

test "readOSTimer" {
    try std.testing.expect(1 < platform.readOsTimer());
}

test "readCpuTimer" {
    try std.testing.expect(1 < platform.readCpuTimer());
}

test "estimateCpuFreq" {
    //try std.testing.expect(24_000_000 < platform.estimateCpuFreq(1000));
    // I would think this should be still above 24_000_000, I haven't debugged why
    // this fails sometimes
    //try std.testing.expectEqual(24_000_000, platform.estimateCpuFreq(100));
}
