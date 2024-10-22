const std = @import("std");
const platform = @import("./platform.zig");
const test_allocator = std.testing.allocator;

// Usage: see tests

// state which is enum with values uninitialized, testing, completed, and error
const Mode = enum {
    Uninitialized,
    Testing,
    Completed,
    Error,
};

pub const TestResults = struct {
    test_count: u64 = 0,
    total_time: u64 = 0,
    max_time: u64 = 0,
    min_time: u64 = std.math.maxInt(u64) - 1,
    max_time_page_faults: u64 = 0,
    min_time_page_faults: u64 = 0,
    total_page_faults: u64 = 0,
};

pub const RepetitionTester = struct {
    close_block_count: u64 = 0,
    cpu_freq: u64 = 0,
    mode: Mode = Mode.Uninitialized,
    open_block_count: u64 = 0,
    print_new_minimums: bool = true,
    results: TestResults = TestResults{},
    target_processed_byte_count: u64 = 0,
    tests_started_at: u64 = 0,
    try_for_time: u64 = 0,
    start_time: u64 = 0,
    start_page_faults: u64 = 0,
    page_faults_accumulated_on_this_test: u64 = 0,
    time_accumulated_on_this_test: u64 = 0,
    bytes_accumulated_on_this_test: u64 = 0,

    pub fn init() RepetitionTester {
        return RepetitionTester{};
    }

    pub fn new_test_wave(self: *RepetitionTester, target_processed_byte_count: u64, cpu_freq: u64, seconds_to_try: u8, stdout: anytype) !void {
        if (self.mode == Mode.Uninitialized) {
            self.mode = Mode.Testing;
            self.target_processed_byte_count = target_processed_byte_count;
            self.cpu_freq = cpu_freq;
            self.results.min_time = std.math.maxInt(u64) - 1;
        } else if (self.mode == Mode.Completed) {
            self.mode = Mode.Testing;

            if (self.target_processed_byte_count != target_processed_byte_count) {
                try self.err(stdout, "target_processed_byte_count changed");
            }
            if (self.cpu_freq != cpu_freq) {
                try self.err(stdout, "CPU frequency changed");
            }
        }

        self.try_for_time = cpu_freq * seconds_to_try;
        self.tests_started_at = platform.readCpuTimer();
    }

    fn print_time(self: *RepetitionTester, stdout: anytype, label: []const u8, cpu_time: u64, cpu_freq: ?u64, byte_count: ?u64, page_faults: ?u64) !void {
        _ = self;
        try stdout.print("{s}: {d:.2}", .{ label, cpu_time });

        if (cpu_freq) |cpu_freq_v| {
            const seconds: f64 = @as(f64, @floatFromInt(cpu_time)) / @as(f64, @floatFromInt(cpu_freq_v));
            try stdout.print(" ({d:0.2}ms)", .{1000 * seconds});

            if (byte_count) |bc| {
                const gigabyte = 1024.0 * 1024.0 * 1024.0;
                const best_bandwidth = @as(f64, @floatFromInt(bc)) / (gigabyte * seconds);
                try stdout.print(" {d:.2} gb/s", .{best_bandwidth});

                if (page_faults) |pf| {
                    const kb_per_fault = (@as(f64, @floatFromInt(bc)) / 1024.0) / @as(f64, @floatFromInt(pf));
                    try stdout.print(" PF: {d} ({d:.2}k/fault)", .{ pf, kb_per_fault });
                }
            }

            try stdout.print("\r", .{});
        }
    }

    pub fn start(self: *RepetitionTester) void {
        self.open_block_count += 1;
        self.start_time = platform.readCpuTimer();
        self.start_page_faults = platform.pageFaults();
    }

    pub fn stop(self: *RepetitionTester) void {
        self.close_block_count += 1;
        self.time_accumulated_on_this_test = platform.readCpuTimer() - self.start_time;
        self.page_faults_accumulated_on_this_test = platform.pageFaults() - self.start_page_faults;
    }

    pub fn err(self: *RepetitionTester, stdout: anytype, message: []const u8) !void {
        self.mode = Mode.Error;
        try stdout.print("ERROR: {s}\n", .{message});
    }

    pub fn count_bytes(self: *RepetitionTester, bytes: u64) void {
        self.bytes_accumulated_on_this_test += bytes;
    }

    pub fn print_results(self: *RepetitionTester, stdout: anytype) !void {
        try self.print_time(stdout, "Min", self.results.min_time, self.cpu_freq, self.target_processed_byte_count, self.results.min_time_page_faults);
        try stdout.print("\n", .{});
        try self.print_time(stdout, "Max", self.results.max_time, self.cpu_freq, self.target_processed_byte_count, self.results.max_time_page_faults);
        try stdout.print("\n", .{});
        if (self.results.test_count > 0) {
            try self.print_time(stdout, "Avg", self.results.total_time / self.results.test_count, self.cpu_freq, self.target_processed_byte_count, self.results.total_page_faults / self.results.test_count);
            try stdout.print("\n", .{});
        }
    }

    pub fn is_testing(self: *RepetitionTester, stdout: anytype) !bool {
        if (self.mode == Mode.Testing) {
            const current_time = platform.readCpuTimer();

            if (self.open_block_count > 0) {
                if (self.open_block_count != self.close_block_count) {
                    try self.err(stdout, "Unbalanced start/stop");
                }

                if (self.target_processed_byte_count != self.bytes_accumulated_on_this_test) {
                    var buffer: [100]u8 = undefined;
                    const msg = try std.fmt.bufPrint(&buffer, "Processed byte count mismatch. Expected {d}, got {d}", .{ self.target_processed_byte_count, self.bytes_accumulated_on_this_test });
                    try self.err(stdout, msg);
                }

                if (self.mode == Mode.Testing) {
                    const elapsed_time = self.time_accumulated_on_this_test;
                    const new_page_faults = self.page_faults_accumulated_on_this_test;

                    //std.debug.print("new_page_faults was {d}\n", .{new_page_faults});

                    self.results.test_count += 1;
                    self.results.total_time += elapsed_time;
                    self.results.total_page_faults += new_page_faults;

                    if (self.results.max_time < elapsed_time) {
                        self.results.max_time = elapsed_time;
                        self.results.max_time_page_faults = new_page_faults;
                    }

                    if (elapsed_time < self.results.min_time) {
                        //std.debug.print("new min {d}, old_min {d}\n", .{ elapsed_time, self.results.min_time });
                        self.results.min_time = elapsed_time;
                        self.results.min_time_page_faults = new_page_faults;

                        self.tests_started_at = current_time;

                        if (self.print_new_minimums) {
                            try self.print_time(stdout, "Min", self.results.min_time, self.cpu_freq, self.bytes_accumulated_on_this_test, null);
                        }
                    }

                    self.open_block_count = 0;
                    self.close_block_count = 0;
                    self.time_accumulated_on_this_test = 0;
                    self.start_time = 0;
                    self.bytes_accumulated_on_this_test = 0;
                }
            }

            if ((current_time - self.tests_started_at) > self.try_for_time) {
                self.mode = Mode.Completed;

                try self.print_results(stdout);
            }
        }

        return (self.mode == Mode.Testing);
    }
};

test "erroring" {
    var list = std.ArrayList(u8).init(test_allocator);
    defer list.deinit();
    const fake_stdout = list.writer();

    var tester = RepetitionTester.init();

    try std.testing.expectEqual(Mode.Uninitialized, tester.mode);

    try tester.err(fake_stdout, "message");
    try std.testing.expectEqual(Mode.Error, tester.mode);
}

test "if params change" {
    var list = std.ArrayList(u8).init(test_allocator);
    defer list.deinit();

    var list2 = std.ArrayList(u8).init(test_allocator);
    defer list2.deinit();

    const fake_stdout = list.writer();
    const fake_stdout2 = list2.writer();

    const cpu_freq = platform.estimateCpuFreq(1000);
    const seconds_to_try = 0;
    const byte_count = 10;

    var tester = RepetitionTester.init();

    try std.testing.expectEqual(Mode.Uninitialized, tester.mode);

    try tester.new_test_wave(byte_count, cpu_freq, seconds_to_try, fake_stdout);

    tester.mode = Mode.Completed;

    try tester.new_test_wave(byte_count + 1, cpu_freq, seconds_to_try, fake_stdout);

    try std.testing.expectEqual(Mode.Error, tester.mode);

    try std.testing.expectEqualStrings("ERROR: target_processed_byte_count changed\n", list.items);

    tester.mode = Mode.Completed;

    try tester.new_test_wave(byte_count, cpu_freq + 1, seconds_to_try, fake_stdout2);

    try std.testing.expectEqual(Mode.Error, tester.mode);

    try std.testing.expectEqualStrings("ERROR: CPU frequency changed\n", list2.items);
}

test "basic repetition tester usage" {
    var list = std.ArrayList(u8).init(test_allocator);
    defer list.deinit();
    const fake_stdout = list.writer();
    const cpu_freq = platform.estimateCpuFreq(1000);
    const seconds_to_try = 1;
    const byte_count = 10;

    var tester = RepetitionTester.init();

    try std.testing.expectEqual(Mode.Uninitialized, tester.mode);

    try tester.new_test_wave(byte_count, cpu_freq, seconds_to_try, fake_stdout);

    try std.testing.expectEqual(0, tester.open_block_count);
    try std.testing.expectEqual(0, tester.close_block_count);

    try std.testing.expectEqual(Mode.Testing, tester.mode);

    var i: u64 = 1;

    while (try tester.is_testing(fake_stdout)) : (i += 1) {
        tester.start();
        try std.testing.expectEqual(1, tester.open_block_count);

        try std.testing.expectEqual(Mode.Testing, tester.mode);
        std.time.sleep(1_000_000_000 / 2 * i);
        tester.stop();
        try std.testing.expectEqual(1, tester.close_block_count);

        tester.count_bytes(10);
    }

    try std.testing.expectEqual(Mode.Completed, tester.mode);
}

test "errors when running" {
    {
        var list = std.ArrayList(u8).init(test_allocator);
        defer list.deinit();
        const fake_stdout = list.writer();
        const cpu_freq = platform.estimateCpuFreq(1000);
        const seconds_to_try = 1;
        const byte_count = 10;

        var tester = RepetitionTester.init();
        try tester.new_test_wave(byte_count, cpu_freq, seconds_to_try, fake_stdout);

        var i: u64 = 1;

        while (try tester.is_testing(fake_stdout)) : (i += 100_000) {
            tester.start();
            std.time.sleep(1_000_000_000 / 2 * i);
            tester.count_bytes(byte_count);
        }

        try std.testing.expectEqualStrings("ERROR: Unbalanced start/stop\n", list.items);
    }

    {
        var list = std.ArrayList(u8).init(test_allocator);
        defer list.deinit();
        const fake_stdout = list.writer();
        const cpu_freq = platform.estimateCpuFreq(1000);
        const seconds_to_try = 1;
        const byte_count = 10;

        var tester = RepetitionTester.init();
        try tester.new_test_wave(byte_count, cpu_freq, seconds_to_try, fake_stdout);

        var i: u64 = 1;

        while (try tester.is_testing(fake_stdout)) : (i += 1) {
            tester.start();
            std.time.sleep(1_000_000_000 / 2 * i);
            tester.count_bytes(byte_count + 1);
            tester.stop();
        }

        try std.testing.expectEqualStrings("ERROR: Processed byte count mismatch\n", list.items);
    }
}

test "getting result from repetition tester" {
    var list = std.ArrayList(u8).init(test_allocator);
    defer list.deinit();
    const fake_stdout = list.writer();
    const cpu_freq = platform.estimateCpuFreq(1000);
    const seconds_to_try = 1;
    const byte_count = 10;

    var tester = RepetitionTester.init();

    try tester.new_test_wave(byte_count, cpu_freq, seconds_to_try, fake_stdout);

    const rough_ns = 1_000_000_000 / 3;
    const rough_ms = rough_ns / 1_000_000;

    // increasing the sleep substantially reduces the chance for a mew min
    var i: u64 = 1;

    while (try tester.is_testing(fake_stdout)) : (i += 1) {
        tester.start();
        std.time.sleep(rough_ns * i);
        tester.stop();

        tester.count_bytes(byte_count);
    }

    // Each wait is roughly 1/3 of a second and we wait a second
    try std.testing.expectEqual(3, tester.results.test_count);

    try std.testing.expect(rough_ms < tester.results.max_time);
    try std.testing.expect(rough_ms * 9 / 10 < tester.results.min_time);
    try std.testing.expect(tester.results.min_time < tester.results.max_time);
    try std.testing.expect(1 < tester.results.total_time);
}
