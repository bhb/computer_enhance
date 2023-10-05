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
const EffAddressCalc = struct { registers: []const u8, displacement: u16 = 0 };

pub fn main() !void {
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
        .name = "mov",
        .dest = reg,
        .source = try decode_value_str(imm_bytes, alloc),
        .bytes_read = bytes_read,
    };
}

fn decode_value(bytes: []u8) u16 {
    var value: u16 = bytes[0];

    if (bytes.len == 2) {
        value = bytes[1];
        value = value << 8;
        value += bytes[0];
    }

    return value;
}

fn decode_value_str(bytes: []u8, alloc: Allocator) ![]const u8 {
    const value = decode_value(bytes);

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

        const eac = effective_address_calculation(r_m, mod, bytes[2..4]);

        var dest = reg_name;
        var source: []const u8 = undefined;

        if (eac.displacement == 0) {
            source = try std.fmt.allocPrint(alloc, "[{s}]", .{eac.registers});
        } else {
            source = try std.fmt.allocPrint(alloc, "[{s} + {d}]", .{ eac.registers, eac.displacement });
        }

        if (d == 0) {
            var temp = dest;
            dest = source;
            source = temp;
        }

        return Inst{ .name = "mov", .dest = dest, .source = source, .bytes_read = bytes_read };
    }
}

fn effective_address_calculation(r_m: u8, mod: u8, bytes: []u8) EffAddressCalc {
    if (r_m == 0b000 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bx + si" };
    } else if (r_m == 0b000 and mod == 0b01) {
        const value = decode_value(bytes[0..1]);
        return EffAddressCalc{ .registers = "bx + si", .displacement = value };
    } else if (r_m == 0b000 and mod == 0b10) {
        const value = decode_value(bytes[0..2]);
        return EffAddressCalc{ .registers = "bx + si", .displacement = value };
    } else if (r_m == 0b001 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bx + di" };
    } else if (r_m == 0b001 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b001 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b010 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bp + si" };
    } else if (r_m == 0b010 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b011 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b011 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bp + di" };
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
        const value = decode_value(bytes[0..1]);
        return EffAddressCalc{ .registers = "bp", .displacement = value };
    } else if (r_m == 0b111 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b00) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b000 and mod == 0b01) {} else {
        unreachable;
    }

    unreachable;
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
