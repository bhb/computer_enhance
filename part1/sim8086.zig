// Homework 1
// Once you’ve successfully disassembled the binaries from both listings thirty-seven and thirty-eight, you’re done!

// Homework 2
// Files: 0039
// Tables on page 162
// Immediate to register is page 164

// Homework 3
// Files: 0041
// Page 165, 166 for add, sub, cmp
// Page 168 for jmp

// Usage:
// zig run sim8086.zig -- <binary file>

// Manual is https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf (page 164)

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();

const Inst = struct { name: []const u8, dest: []const u8, source: []const u8, bytes_read: u4 };
const InstType = enum { mov_regmem_to_regmem, mov_imm_to_reg, add_sub_cmp, add_sub_cmp_imm, unknown };
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
    const byte0 = bytes[0];

    const four_bit_inst_code = (byte0 & 0b11110000) >> 4;
    const six_bit_inst_code = (byte0 & 0b11111100) >> 2;

    const four_bit_instruction = switch (four_bit_inst_code) {
        0b1011 => InstType.mov_imm_to_reg,
        else => null,
    };

    const six_bit_instruction = switch (six_bit_inst_code) {
        0b100010 => InstType.mov_regmem_to_regmem,
        0b000000, 0b100000, 0b000001 => InstType.add_sub_cmp,
        else => null,
    };

    const instr_type = four_bit_instruction orelse six_bit_instruction orelse InstType.unknown;

    const inst = switch (instr_type) {
        InstType.mov_imm_to_reg => try decode_mov_imm_to_reg(bytes, alloc),
        InstType.mov_regmem_to_regmem => try decode_mov_regmem_to_regmem(bytes, alloc),
        InstType.add_sub_cmp => try decode_add_sub_cmp(six_bit_inst_code, bytes, alloc),
        else => unreachable,
    };

    return inst;
}

fn decode_add_sub_cmp(instr: u8, bytes: []u8, alloc: Allocator) !Inst {
    const foo = try std.fmt.allocPrint(alloc, "{d}", .{2});
    _ = foo;

    const sub_code = switch (instr) {
        0b100000 => blk: {
            break :blk bytes[1] & 0b00111000;
        },
        else => blk: {
            break :blk instr & 0b001110;
        },
    };

    //std.debug.print("bytes[0] {b}, bytes[1] {b}, instr: {b}, sub_code {b}\n", .{ bytes[0], bytes[1], instr, sub_code });

    const op = switch (sub_code) {
        0b000 => "add",
        0b101 => "sub",
        0b111 => "cmp",
        else => unreachable,
    };

    switch (instr) {
        0b100000 => {
            std.debug.print("bytes[0] {b}, bytes[1] {b}, instr: {b}, sub_code {b}\n", .{ bytes[0], bytes[1], instr, sub_code });
            return decode_any_imm_to_memreg(op, bytes, alloc);
        },
        else => {
            return decode_any_regmem_to_regmem(op, bytes, alloc);
        },
    }
}

fn decode_mov_imm_to_reg(bytes: []u8, alloc: Allocator) !Inst {
    return decode_any_imm_to_reg("mov", bytes, alloc);
}

fn decode_any_imm_to_memreg(op: []const u8, bytes: []u8, alloc: Allocator) !Inst {
    const byte0 = bytes[0];
    const byte1 = bytes[1];

    const wide = (byte0 & 0b00000001) == 1;
    const signed = (byte0 & 0b00000010) == 1;
    const mod = (byte1 & 0b11000000) >> 6;
    const r_m = (byte1 & 0b00000111);

    std.debug.print("w: {}, mod: {b}, r_m: {b}\n", .{ wide, mod, r_m });

    const reg = register_name(r_m, wide);

    // TODO - what do I need imm_bytes for?
    var imm_bytes: []u8 = undefined;

    var bytes_read: u4 = undefined;

    std.debug.print("all 6 bytes {b} {b} {b} {b} {b} {b}\n\n", .{ bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5] });

    var source: []const u8 = undefined;

    // define a slice using the [start..end] syntax. slice begins at array[1] and ends just before array[4].
    if (mod == 0b11) {
        if (signed and wide) {
            bytes_read = 4;
            imm_bytes = bytes[2..4];
        } else {
            bytes_read = 3;
            imm_bytes = bytes[2..3];
        }
        source = try std.fmt.allocPrint(alloc, "{d}", .{decode_value(imm_bytes, signed)});
    } else {
        // TODO - refactor to avoid duplication
        const eac = effective_address_calculation(r_m, mod, bytes[2..], signed);

        if (eac.displacement == 0) {
            source = try std.fmt.allocPrint(alloc, "[{s}]", .{eac.registers});
        } else {
            source = try std.fmt.allocPrint(alloc, "[{s} + {d}]", .{ eac.registers, eac.displacement });
        }
    }

    return Inst{
        .name = op,
        .dest = reg,
        .source = source,
        .bytes_read = bytes_read,
    };
}

// TODO - not actually useful as "any" method
fn decode_any_imm_to_reg(op: []const u8, bytes: []u8, alloc: Allocator) !Inst {
    const byte0 = bytes[0];

    const wide = ((byte0 & 0b00001000) >> 3) == 1;
    const reg_code = (byte0 & 0b00000111);

    const reg = register_name(reg_code, wide);

    var imm_bytes: []u8 = undefined;

    var bytes_read: u4 = undefined;

    if (wide) {
        bytes_read = 3;
        imm_bytes = bytes[1..3];
    } else {
        bytes_read = 2;
        imm_bytes = bytes[1..2];
    }

    const signed = false;

    return Inst{
        .name = op,
        .dest = reg,
        .source = try std.fmt.allocPrint(alloc, "{d}", .{decode_value(imm_bytes, signed)}),
        .bytes_read = bytes_read,
    };
}

fn decode_value(bytes: []u8, signed: bool) u16 {
    std.debug.print("bytes! {b}, signed: {}\n\n", .{ bytes, signed });

    var value: u16 = bytes[0];

    if (bytes.len == 2) {
        value = bytes[1];
        value = value << 8;
        value += bytes[0];
    }

    // "S is used in conjunction with W to indicate sign extension
    // of immediate fields in arithmetic instructions"
    // "Sign extend 8-bit immediate data to 16 bits if W=1"
    // "If the displacement is only a single byte, the 8086 or 8088 automatically sign-extends this quantity to 16-bits before using the information in further address calculation"

    // HERE - need to check if the first bit is zero or one,  but
    // before that, I should be getting the correct value
    // if (signed) {
    //     value = (value - 1);
    // }

    return value;
}

fn decode_mov_regmem_to_regmem(bytes: []u8, alloc: Allocator) !Inst {
    return decode_any_regmem_to_regmem("mov", bytes, alloc);
}

// rm = register or memory
fn decode_any_regmem_to_regmem(op: []const u8, bytes: []u8, alloc: Allocator) !Inst {
    const signed = false;

    const byte0 = bytes[0];
    const byte1 = bytes[1];

    // 2 bits are "DW" (one bit each)
    // page 161 of manual
    const d = (byte0 & 0b00000010) >> 1;
    const wide = ((byte0 & 0b00000001) == 1);

    // 2 bits are "mod"
    // 3 bits are "reg"
    // 3 bits are r/m
    const mod = (byte1 & 0b11000000) >> 6;
    const reg = (byte1 & 0b00111000) >> 3;
    const r_m = (byte1 & 0b00000111);

    if (mod == 0b11) {
        var reg1 = register_name(reg, wide);
        var reg2 = register_name(r_m, wide);

        if (d == 0) {
            var temp = reg1;
            reg1 = reg2;
            reg2 = temp;
        }

        return Inst{ .name = op, .dest = reg1, .source = reg2, .bytes_read = 2 };
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

        const reg_name = register_name(reg, wide);

        const eac = effective_address_calculation(r_m, mod, bytes[2..4], signed);

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

        return Inst{ .name = op, .dest = dest, .source = source, .bytes_read = bytes_read };
    }
}

fn effective_address_calculation(r_m: u8, mod: u8, bytes: []u8, signed: bool) EffAddressCalc {
    if (r_m == 0b000 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bx + si" };
    } else if (r_m == 0b000 and mod == 0b01) {
        const value = decode_value(bytes[0..1], signed);
        return EffAddressCalc{ .registers = "bx + si", .displacement = value };
    } else if (r_m == 0b000 and mod == 0b10) {
        const value = decode_value(bytes[0..2], signed);
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
        const value = decode_value(bytes[0..2], signed);
        return EffAddressCalc{ .registers = "bp + di", .displacement = value };
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
        const value = decode_value(bytes[0..1], signed);
        return EffAddressCalc{ .registers = "bp", .displacement = value };
    } else if (r_m == 0b111 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b00) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b000 and mod == 0b01) {} else {
        const value = decode_value(bytes[0..1], signed);
        return EffAddressCalc{ .registers = "bx + si", .displacement = value };
    }

    unreachable;
}

// Register table is page 162
fn register_name(reg_code: u8, wide: bool) []const u8 {
    return switch (reg_code) {
        0b000 => (if (!wide) "al" else "ax"),
        0b001 => (if (!wide) "cl" else "cx"),
        0b010 => (if (!wide) "dl" else "dx"),
        0b011 => (if (!wide) "bl" else "bx"),
        0b100 => (if (!wide) "ah" else "sp"),
        0b101 => (if (!wide) "ch" else "bp"),
        0b110 => (if (!wide) "dh" else "si"),
        0b111 => (if (!wide) "bh" else "di"),
        else => "unknown register",
    };
}
