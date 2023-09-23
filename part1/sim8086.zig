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

    try stdout.print("  {s}", .{filename});
}
