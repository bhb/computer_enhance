// Once you’ve successfully disassembled the binaries from both listings thirty-seven and thirty-eight, you’re done!

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    std.debug.print("Arguments: {s}\n", .{args});

    const filename = args[1];

    try decode(filename, alloc);
}

fn decode(filename: []const u8, alloc: Allocator) !void {
    var file = try fs.cwd().openFile(filename, .{});
    defer file.close();

    var buffer: [100]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);
    _ = bytes_read;

    try stdout.print("bits 16\n\n", .{});

    try stdout.print("{s}\n", .{try instruction_string(buffer[0], buffer[1], alloc)});

    //try stdout.print("{s} {s}, {s}\n", .{ instruction, reg1, reg2 });
}

fn instruction_string(byte0: u8, byte1: u8, alloc: Allocator) ![]const u8 {
    // Manual is https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf (page 164)
    // 6 bits are instruction code
    const inst_code = (byte0 & 0b11111100) >> 2;

    // 2 bits are "DW" (one bit each)
    // page 161 of manual
    const d = (byte0 & 0b00000010) >> 1;
    const w = (byte0 & 0b00000001);

    // 2 bits are "mod"
    // 3 bits are "reg"
    // 3 bits are r/m
    const mod = (byte1 & 0b11000000) >> 6;
    _ = mod; // we know mod is always 11

    const reg = (byte1 & 0b00111000) >> 3;
    const r_m = (byte1 & 0b00000111);

    const instruction = switch (inst_code) {
        0b100010 => "mov",
        else => "unknown",
    };

    var reg1 = register_name(reg, w);
    var reg2 = register_name(r_m, w);

    if (d == 0) {
        var temp = reg1;
        reg1 = reg2;
        reg2 = temp;
    }

    return try std.fmt.allocPrint(
        alloc,
        "{s} {s}, {s}",
        .{ instruction, reg1, reg2 },
    );
}

// Register table is page 162
fn register_name(reg_code: u8, w: u8) []const u8 {
    return switch (reg_code) {
        0b000 => (if (w == 0) "al" else "ax"),
        0b001 => (if (w == 0) "cl" else "cx"),
        0b010 => (if (w == 0) "dl" else "dx"),
        0b011 => (if (w == 0) "bl" else "bx"),
        0b100 => (if (w == 0) "ah" else "sp"),
        0b101 => (if (w == 0) "ch" else "bp"),
        0b110 => (if (w == 0) "dh" else "si"),
        0b111 => (if (w == 0) "bh" else "di"),
        else => "unknown register",
    };
}
