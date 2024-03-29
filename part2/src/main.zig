const std = @import("std");
const fs = std.fs;
const cli = @import("zig-cli");
const platform = @import("./platform.zig");

const math = std.math;
const MismatchError = error{ DistanceMismatch, AvgMismatch };

fn square(x: f64) f64 {
    return x * x;
}

const earth_radius = 6371;

fn referenceHaversine(x0: f64, y0: f64, x1: f64, y1: f64) f64 {
    var lat1: f64 = y0;
    var lat2: f64 = y1;
    const lon1 = x0;
    const lon2 = x1;

    const d_lat = math.degreesToRadians(f64, lat2 - lat1);
    const d_lon = math.degreesToRadians(f64, lon2 - lon1);
    lat1 = math.degreesToRadians(f64, lat1);
    lat2 = math.degreesToRadians(f64, lat2);

    const a = square(math.sin(d_lat / 2.0)) + math.cos(lat1) * math.cos(lat2) * square(math.sin(d_lon / 2.0));
    const c = 2.0 * math.asin(math.sqrt(a));

    return earth_radius * c;
}

test "floating point binary conversion" {
    const float_value: f32 = 10.0;
    const float_as_bytes = [4]u8{
        0b00000000,
        0b00000000,
        0b00100000,
        0b01000001,
    };
    const bitcast_float = @as(f32, @bitCast(std.mem.readInt(u32, &float_as_bytes, std.builtin.Endian.little)));

    try std.testing.expectEqual(float_value, bitcast_float);
    try std.testing.expectEqual(float_as_bytes, std.mem.toBytes(float_value));
}

test "floating point binary conversion (f64)" {
    const float_value: f64 = -3.7541387e+230;
    const float_as_bytes = [8]u8{ 0x40, 0xb3, 0x97, 0x74, 0x9e, 0xf3, 0xce, 0xef };
    const bitcast_float = @as(f64, @bitCast(std.mem.readInt(u64, &float_as_bytes, std.builtin.Endian.little)));
    try std.testing.expectApproxEqRel(float_value, bitcast_float, 0.001);
}

test "maxint" {
    try std.testing.expectEqual(63, std.math.maxInt(u6));
}

test "Test referenceHaversine function" {
    const examples = [_]struct {
        x0: f64,
        y0: f64,
        x1: f64,
        y1: f64,
        expectedDistance: f64,
    }{
        // Examples around the world
        .{ .y0 = 36.12, .x0 = -86.67, .y1 = 33.94, .x1 = -118.40, .expectedDistance = 2886.444 },
        .{ .y0 = 51.51, .x0 = -0.13, .y1 = 48.85, .x1 = 2.35, .expectedDistance = 344.43 }, // London to Paris
    };

    // Test each example
    for (examples) |example| {
        const result = referenceHaversine(example.x0, example.y0, example.x1, example.y1);
        const epsilon = 0.0001; // Define an acceptable error margin

        try std.testing.expectApproxEqRel(result, example.expectedDistance, epsilon);
    }
}

const Config = struct {
    seed: u64 = undefined,
    method: []const u8 = "uniform",
    count: u64 = undefined,
    generate: ?[]const u8 = null,
    verify: ?[]const u8 = null,
};

const Allocator = std.mem.Allocator;

var config: Config = Config{};

var seed_opt = cli.Option{
    .long_name = "rseed", // For some reason, seed is a default option to zig run?
    .help = "Random seed",
    .value_ref = cli.mkRef(&config.seed),
};

var method_opt = cli.Option{
    .long_name = "method",
    .help = "Method (cluster or uniform)",
    .value_ref = cli.mkRef(&config.method),
};

var count_opt = cli.Option{
    .long_name = "count",
    .help = "Number of pairs to generate",
    .value_ref = cli.mkRef(&config.count),
};

var generate_opt = cli.Option{
    .long_name = "generate",
    .help = "Base file name to write to. Will write x.json and x.f64",
    .value_ref = cli.mkRef(&config.generate),
};

var verify_opt = cli.Option{
    .long_name = "verify",
    .help = "Base file name to read from. Will read x.json and x.f64",
    .value_ref = cli.mkRef(&config.verify),
};

var app = &cli.App{
    .command = cli.Command{
        .name = "haversine_generator",
        .description = cli.Description{
            .one_line = "Generates points and computes haversine distance",
        },
        .options = &.{ &seed_opt, &method_opt, &count_opt, &generate_opt, &verify_opt },
        .target = cli.CommandTarget{ .action = cli.CommandAction{ .exec = run } },
    },
    .version = "0.0.1",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    try cli.run(app, alloc);
}

fn run() !void {
    const stdout = std.io.getStdOut().writer();

    if ((config.generate == null) and (config.verify == null)) {
        try stdout.print("You must specificy --generate or --verify\n", .{});
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const binary_file_name = try std.fmt.allocPrint(alloc, "{?s}.f64", .{config.generate orelse config.verify});
    const json_file_name = try std.fmt.allocPrint(alloc, "{?s}.json", .{config.generate orelse config.verify});

    if (config.generate != null) {
        var prng = std.rand.DefaultPrng.init(config.seed);

        std.debug.print("-- starting pair generation\n", .{});
        const pairs = try generate_pairs(config, &prng, alloc);
        defer alloc.free(pairs);

        std.debug.print("-- writing reference numbers to disk\n", .{});

        var avg: f64 = 0;
        var distances = try std.ArrayList(f64).initCapacity(alloc, config.count);
        defer distances.deinit();

        for (pairs) |pair| {
            const dist = referenceHaversine(pair.x0, pair.y0, pair.x1, pair.y1);
            distances.appendAssumeCapacity(dist);
            avg += dist;
        }

        const distancesSlice = try distances.toOwnedSlice();
        defer alloc.free(distancesSlice);

        std.debug.print("-- writing bytes to disk\n", .{});

        try writeAnswers(
            distancesSlice,
            avg,
            binary_file_name,
        );

        avg = avg / @as(f64, @floatFromInt(config.count));

        std.debug.print("-- writing json to disk\n", .{});
        try print_json(pairs, json_file_name);

        try stdout.print("Method: {s}\n", .{config.method});
        try stdout.print("Random seed: {d}\n", .{config.seed});
        try stdout.print("Pair count: {d}\n", .{config.count});
        try stdout.print("Expected average: {d}\n", .{avg});
    } else if (config.verify != null) {
        const data: ParsedData = try readJson(json_file_name, alloc);
        defer data.deinit();

        const pairs = data.value.pairs;
        //defer alloc.free(pairs);

        const answers: []f64 = try readAnswers(binary_file_name, alloc);
        defer alloc.free(answers);

        var avg: f64 = 0;

        for (pairs, 0..) |pair, i| {
            const answer = answers[i];
            const dist = referenceHaversine(pair.x0, pair.y0, pair.x1, pair.y1);
            if (answer != dist) {
                return MismatchError.DistanceMismatch;
            }
            avg += dist;
        }

        if (avg != answers[answers.len - 1]) {
            return MismatchError.AvgMismatch;
        }

        try stdout.print("All values match.\n", .{});
    }
}

fn writeAnswers(distances: []f64, avg: f64, binary_file_name: []const u8) !void {
    var file = try fs.cwd().createFile(binary_file_name, .{});
    defer file.close();

    var bufferedWriter = std.io.bufferedWriter(file.writer());

    for (distances) |distance| {
        const buffer: [8]u8 = std.mem.toBytes(distance);
        try bufferedWriter.writer().writeAll(&buffer);
    }

    std.debug.print("writing avg {d}\n", .{avg});

    const buffer: [8]u8 = std.mem.toBytes(avg);
    try bufferedWriter.writer().writeAll(&buffer);

    try bufferedWriter.flush();
}

// caller must dealloc array
fn readAnswers(binary_file_name: []u8, alloc: Allocator) ![]f64 {
    const max_bytes = 1 * 1024 * 1024 * 1024; // 1 GB limit
    const data = try fs.cwd().readFileAlloc(alloc, binary_file_name, max_bytes);
    const answers: []f64 = try alloc.alloc(f64, data.len / 8);

    var idx: u64 = 0;
    while (idx < data.len) : (idx += 8) {
        var float_as_bytes: [8]u8 = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
        std.mem.copyForwards(u8, &float_as_bytes, data[idx .. idx + 8]);
        const bitcast_float = @as(f64, @bitCast(std.mem.readInt(u64, &float_as_bytes, std.builtin.Endian.little)));
        answers[idx / 8] = bitcast_float;
    }
    return answers;
}

const PointPair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

const Data = struct {
    pairs: []PointPair,
};

const EarthRadius = 6372.8;

fn generate_pairs(c: Config, prng: *std.rand.Xoshiro256, alloc: Allocator) ![]PointPair {
    var pairs = try std.ArrayList(PointPair).initCapacity(alloc, c.count);
    defer pairs.deinit();

    var random = prng.random();

    // "The valid range of latitude in degrees is -90 and +90 for the southern and northern hemisphere, respectively.
    // Longitude is in the range -180 and +180"
    const x_cluster_size = 360.0 / 64.0;
    const y_cluster_size = 180.0 / 64.0;

    const x0_cluster_index = @as(f64, @floatFromInt(random.int(u6))); // between 0-63
    const y0_cluster_index = @as(f64, @floatFromInt(random.int(u6))); // between 0-63
    const x1_cluster_index = @as(f64, @floatFromInt(random.int(u6))); // between 0-63
    const y1_cluster_index = @as(f64, @floatFromInt(random.int(u6))); // between 0-63

    var x0_min: f64 = -180;
    var x0_max: f64 = 180;
    var y0_min: f64 = -90;
    var y0_max: f64 = 90;

    var x1_min: f64 = -180;
    var x1_max: f64 = 180;
    var y1_min: f64 = -90;
    var y1_max: f64 = 90;

    if (std.mem.eql(u8, c.method, "cluster")) {
        x0_min = x0_cluster_index * x_cluster_size - 180;
        x0_max = x0_min + x_cluster_size;

        y0_min = y0_cluster_index * y_cluster_size - 90;
        y0_max = y0_min + y_cluster_size;

        x1_min = x1_cluster_index * x_cluster_size - 180;
        x1_max = x1_min + x_cluster_size;

        y1_min = y1_cluster_index * y_cluster_size - 90;
        y1_max = y1_min + y_cluster_size;
    }

    std.debug.assert(-180 <= x0_min);
    std.debug.assert(-90 <= y0_min);
    std.debug.assert(x0_max <= 180);
    std.debug.assert(y0_min <= 90);
    std.debug.assert(-180 <= x1_min);
    std.debug.assert(-90 <= y1_min);
    std.debug.assert(x1_max <= 180);
    std.debug.assert(y1_min <= 90);

    std.debug.print("x0_min {d}, y0_min {d}, x0_max {d}, y0_max {d}", .{ x0_min, y0_min, x0_max, y0_max });
    std.debug.print("x1_min {d}, y1_min {d}, x1_max {d}, y1_max {d}", .{ x1_min, y1_min, x1_max, y1_max });

    for (0..c.count) |i| {
        _ = i;
        // rand will be range 0-1
        const x0 = random.float(f64) * (x0_max - x0_min) + x0_min;
        const y0 = random.float(f64) * (y0_max - y0_min) + y0_min;
        const x1 = random.float(f64) * (x1_max - x1_min) + x1_min;
        const y1 = random.float(f64) * (y1_max - y1_min) + y1_min;

        const pair = PointPair{
            .x0 = x0,
            .y0 = y0,
            .x1 = x1,
            .y1 = y1,
        };
        pairs.appendAssumeCapacity(pair);
    }

    return try pairs.toOwnedSlice();
}

fn print_json(pairs: []PointPair, json_file_name: []const u8) !void {
    const data = Data{
        .pairs = pairs,
    };

    const options = std.json.StringifyOptions{};

    var file = try fs.cwd().createFile(json_file_name, .{});
    defer file.close();

    var bufferedWriter = std.io.bufferedWriter(file.writer());

    try std.json.stringify(data, options, bufferedWriter.writer());

    try bufferedWriter.flush();
}

const ParsedData = std.json.Parsed(Data);

// caller must clean up data
fn readJson(json_file_name: []const u8, alloc: Allocator) !ParsedData {
    const max_bytes = 1 * 1024 * 1024 * 1024; // 1 GB limit
    const string = try fs.cwd().readFileAlloc(alloc, json_file_name, max_bytes);
    defer alloc.free(string);

    const data = try std.json.parseFromSlice(Data, alloc, string, .{});
    return data;
}

test "readOSTimer" {
    try std.testing.expect(1 < platform.readOSTimer());
}

test "readCpuTimer" {
    try std.testing.expect(1 < platform.readCpuTimer());
}
