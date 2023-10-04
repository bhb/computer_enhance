// Homework 1
// Once you’ve successfully disassembled the binaries from both listings thirty-seven and thirty-eight, you’re done!

// Homework 2
// Files: 0039
// Tables on page 162
// Immediate to register is page 164

// Usage:
// zig run sim8086.zig -- listing_0037_many_register_mov
// zig run sim8086.zig -- listing_0038_many_register_mov

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();

const Inst = struct { name: []const u8, dest: []const u8, source: []const u8, bytes_read: u4 };
const InstType = enum { mov_reg_to_reg, mov_imm_to_reg, unknown };

pub fn main() !void {
    //var x: u16 = 3948;

    //std.debug.print("{b}, {b}, {b}\n\n", .{ x, (~x + 1), 61588 });

    var buffer: [3000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const filename = args[1];

    try decode(filename, alloc);
}

fn decode(filename: []const u8, alloc: Allocator) !void {
    var file = try fs.cwd().openFile(filename, .{});
    defer file.close();

    var buffer: [100]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);

    try stdout.print("bits 16\n\n", .{});

    var i: usize = 0;
    var instr: Inst = undefined;
    var instr_str: []const u8 = undefined;

    while (i < bytes_read) {
        instr = try instruction(buffer[i..], alloc);
        i += instr.bytes_read;
        std.debug.print("i is {d}, bytes read last instr {d}, total bytes to read {d} \n", .{ i, instr.bytes_read, bytes_read });
        instr_str = try std.fmt.allocPrint(
            alloc,
            "{s} {s}, {s}",
            .{ instr.name, instr.dest, instr.source },
        );
        try stdout.print("{s}\n", .{instr_str});
    }
}

fn instruction(bytes: []u8, alloc: Allocator) !Inst {
    // Manual is https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf (page 164)
    // 6 bits are instruction code

    const byte0 = bytes[0];

    const four_bit_inst_code = (byte0 & 0b11110000) >> 4;
    const six_bit_inst_code = (byte0 & 0b11111100) >> 2;

    const four_bit_instruction = switch (four_bit_inst_code) {
        0b1011 => InstType.mov_imm_to_reg,
        else => null,
    };

    const six_bit_instruction = switch (six_bit_inst_code) {
        0b100010 => InstType.mov_reg_to_reg,
        else => null,
    };

    const instr_type = four_bit_instruction orelse six_bit_instruction orelse InstType.unknown;

    std.debug.print("instr_type: {} {b}\n", .{ instr_type, byte0 });

    const inst = switch (instr_type) {
        InstType.mov_imm_to_reg => try decode_mov_imm_to_reg(bytes, alloc),
        InstType.mov_reg_to_reg => try decode_mov_reg_to_reg(bytes, alloc),
        else => unreachable,
    };

    return inst;
}

fn decode_mov_imm_to_reg(bytes: []u8, alloc: Allocator) !Inst {
    const byte0 = bytes[0];

    const w = (byte0 & 0b00001000) >> 3;
    const reg_code = (byte0 & 0b00000111);

    const reg = register_name(reg_code, w);

    var imm_bytes: []u8 = undefined;

    var bytes_read: u4 = undefined;

    if (w == 1) {
        bytes_read = 3;
        imm_bytes = bytes[1..3];
    } else {
        bytes_read = 2;
        imm_bytes = bytes[1..2];
    }

    return Inst{
        .name = "mov2",
        .dest = reg,
        .source = try decode_value(imm_bytes, alloc),
        .bytes_read = bytes_read,
    };
}

fn decode_value(bytes: []u8, alloc: Allocator) ![]const u8 {
    var value: u16 = bytes[0];

    //std.debug.print("decode_value: {d} {b}\n", .{ value, value });

    if (bytes.len == 2) {
        value = bytes[1];
        value = value << 8;
        value += bytes[0];
        //std.debug.print("decode_value (2): {d} {b} {b} {b}\n", .{ value, value, bytes[0], bytes[1] });
    }

    var str = try std.fmt.allocPrint(alloc, "{d}", .{value});

    return str;
}

fn decode_mov_reg_to_reg(bytes: []u8, alloc: Allocator) !Inst {
    const byte0 = bytes[0];
    const byte1 = bytes[1];

    // 2 bits are "DW" (one bit each)
    // page 161 of manual
    const d = (byte0 & 0b00000010) >> 1;
    const w = (byte0 & 0b00000001);

    // 2 bits are "mod"
    // 3 bits are "reg"
    // 3 bits are r/m
    const mod = (byte1 & 0b11000000) >> 6;
    const reg = (byte1 & 0b00111000) >> 3;
    const r_m = (byte1 & 0b00000111);

    // HERE - starting to handle other mod values
    std.debug.print("mod - {b}, r/m {b}\n\n", .{ mod, r_m });
    if (mod == 0b11) {
        var reg1 = register_name(reg, w);
        var reg2 = register_name(r_m, w);

        if (d == 0) {
            var temp = reg1;
            reg1 = reg2;
            reg2 = temp;
        }

        return Inst{ .name = "mov", .dest = reg1, .source = reg2, .bytes_read = 2 };
    } else {
        var bytes_read: u4 = 2;

        if (mod == 0b01) {
            bytes_read += 1;
        } else if (mod == 0b10) {
            bytes_read += 2;
        } else if (mod == 0b00 and r_m == 0b110) {
            unreachable;
        } else {
            bytes_read += 0;
        }

        const reg_name = register_name(reg, w);

        const eac = try effective_address_calculation(r_m, mod, bytes[2..4], alloc);

        return Inst{ .name = "mov3", .dest = reg_name, .source = eac, .bytes_read = bytes_read };
    }
}

fn effective_address_calculation(r_m: u8, mod: u8, bytes: []u8, alloc: Allocator) ![]const u8 {
    std.debug.print("eac --- {b} {b}\n", .{ r_m, mod });

    if (r_m == 0b000 and mod == 0b00) {
        return "[bx + si]";
    } else if (r_m == 0b000 and mod == 0b01) {
        // TODO - replace d8
        const value = try decode_value(bytes[0..1], alloc);
        return try std.fmt.allocPrint(alloc, "[bx + si + {s}]", .{value});
    } else if (r_m == 0b000 and mod == 0b10) {
        return "[bx + si + d16]";
    } else if (r_m == 0b001 and mod == 0b00) {
        return "[bx + di]";
    } else if (r_m == 0b001 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b001 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b010 and mod == 0b00) {
        return "[bp + si]";
    } else if (r_m == 0b010 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b011 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b011 and mod == 0b00) {
        return "[bp + di]";
    } else if (r_m == 0b011 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b100 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b100 and mod == 0b00) {
        unreachable;
    } else if (r_m == 0b100 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b101 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b101 and mod == 0b00) {
        unreachable;
    } else if (r_m == 0b101 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b110 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b110 and mod == 0b00) {
        unreachable;
    } else if (r_m == 0b110 and mod == 0b01) {
        // TODO - d8 should be displacement number
        return "[bp + d8]";
    } else if (r_m == 0b111 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b00) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b000 and mod == 0b01) {} else {
        unreachable;
    }

    return "flunk";
}

// Register table is page 162
fn register_name(reg_code: u8, w: u8) []const u8 {
    //std.debug.print("reg {b} w: {b}\n", .{ reg_code, w });

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
