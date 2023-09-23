// Once you’ve successfully disassembled the binaries from both listings thirty-seven and thirty-eight, you’re done!

const std = @import("std");
const fs = std.fs;

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    std.debug.print("Arguments: {s}\n", .{args});

    const filename = args[1];

    try decode(filename);
}

fn decode(filename: []const u8) !void {
    var file = try fs.cwd().openFile(filename, .{});
    defer file.close();

    var buffer: [100]u8 = undefined;
    try file.seekTo(0);
    _ = try file.readAll(&buffer);

    // Manual is https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf (page 164)
    // 6 bits are instruction code
    const inst_code = (buffer[0] & 0b11111100) >> 2;

    // 2 bits are "DW" (one bit each)
    const dw = (buffer[0] & 0b00000011);

    // 2 bits are "mod"
    // 3 bits are "reg"
    // 3 bits are r/m
    const mod = (buffer[1] & 0b11000000) >> 6;
    _ = mod; // we know mod is always 11

    const reg = (buffer[1] & 0b00111000) >> 3;
    const r_m = (buffer[1] & 0b00000111);

    const instruction = switch (inst_code) {
        0b100010 => "mov",
        else => "unknown",
    };

    try stdout.print("  {s} {s} {b} {b}", .{ filename, instruction, inst_code, dw });
}
