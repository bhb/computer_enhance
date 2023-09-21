// Once you’ve successfully disassembled the binaries from both listings thirty-seven and thirty-eight, you’re done!

const std = @import("std");
const fs = std.fs;

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    try decode("foobar");
}

fn decode(filename: []const u8) !void {
    var file = try fs.cwd().openFile(filename, .{});
    defer file.close();

    try stdout.print("  {s}", .{filename});
}
