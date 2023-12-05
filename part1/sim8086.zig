// Usage:
// zig run sim8086.zig -- <binary file>

// Manual is https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf (page 164)

// To debug
// zig build-exe sim8086.zig
// lldb sim8086
// settings set -- target.run-args listing_0041_add_sub_cmp_jnz
// b <some method>
// run

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const stdout = std.io.getStdOut().writer();

const InstrName = enum {
    mov,
    add,
    sub,
    cmp,
    jo,
    jno,
    jb,
    jnb,
    je,
    jnz,
    jbe,
    ja,
    js,
    jns,
    jp,
    jnp,
    jl,
    jnl,
    jle,
    jg,
    loopnz,
    loopz,
    loop,
    jcxz,

    pub fn string(self: InstrName) []const u8 {
        return @tagName(self);
    }
};

const RegisterName = enum {
    ah,
    al,
    ax,
    bh,
    bl,
    bp,
    bx,
    ch,
    cl,
    cx,
    dh,
    di,
    dl,
    dx,
    si,
    sp,

    pub fn string(self: RegisterName) []const u8 {
        return @tagName(self);
    }
};

const Location = struct {
    reg1: ?RegisterName,
    reg2: ?RegisterName,
    offset: ?u16,
};

const OperandTag = enum { register, location, value };
const Operand = union(OperandTag) {
    register: RegisterName,
    value: u16,
    location: []const u8,

    pub fn string(self: Operand, alloc: Allocator) ![]const u8 {
        return switch (self) {
            Operand.register => self.register.string(),
            Operand.location => self.location,
            Operand.value => try std.fmt.allocPrint(alloc, "{d}", .{self.value}),
        };
    }
};
const Instr = struct { name: InstrName, dest: ?Operand = null, source: ?Operand = null, bytes_read: u4, jmp_offset: ?i32 = null };
const InstType = enum { mov_regmem_to_regmem, mov_imm_to_reg, any_imm_to_regmem, any_regmem_to_regmem, add_sub_cmp_imm, any_imm_to_acc, any_jump, unknown };
const EffAddressCalc = struct { registers: []const u8, displacement: i32 = -1, direct_address: i32 = -1 };

const MemorySim = struct {
    ax: u16 = 0,
    bx: u16 = 0,
    cx: u16 = 0,
    dx: u16 = 0,
    sp: u16 = 0,
    bp: u16 = 0,
    si: u16 = 0,
    di: u16 = 0,

    pub fn read(self: *MemorySim, register: RegisterName) u16 {
        return switch (register) {
            RegisterName.ax => self.ax,
            RegisterName.bx => self.bx,
            RegisterName.cx => self.cx,
            RegisterName.dx => self.dx,
            RegisterName.sp => self.sp,
            RegisterName.bp => self.bp,
            RegisterName.si => self.si,
            RegisterName.di => self.di,
            else => unreachable,
        };
    }

    pub fn copy(self: *MemorySim) MemorySim {
        return MemorySim{ .ax = self.ax, .bx = self.bx, .cx = self.cx, .dx = self.dx, .sp = self.sp, .bp = self.bp, .si = self.si, .di = self.di };
    }

    pub fn mov(self: *MemorySim, dest: Operand, source: Operand) void {
        switch (dest) {
            Operand.register => {
                switch (dest.register) {
                    RegisterName.ax => self.ax = source.value,
                    RegisterName.bx => self.bx = source.value,
                    RegisterName.cx => self.cx = source.value,
                    RegisterName.dx => self.dx = source.value,
                    RegisterName.sp => self.sp = source.value,
                    RegisterName.bp => self.bp = source.value,
                    RegisterName.si => self.si = source.value,
                    RegisterName.di => self.di = source.value,
                    else => unreachable,
                }
            },
            else => {
                unreachable;
            },
        }
    }
};

pub fn main() !void {
    var buffer: [20_000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = fba.allocator();

    //std.debug.print("allocator: {d} \n", .{fba.end_index});

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var filename: []const u8 = undefined;
    var exec: bool = false;

    if (args.len == 2) {
        filename = args[1];
    } else if (args.len == 3 and std.mem.eql(u8, args[1], "--exec")) {
        exec = true;
        filename = args[2];
    } else {
        unreachable;
    }

    //std.debug.print("allocator: {d} \n", .{fba.end_index});

    var instructions: []Instr = try alloc.alloc(Instr, 100);

    // std.debug.print("size of InstrName {}\n", .{@sizeOf(InstrName)});
    // std.debug.print("size of RegisterName {}\n", .{@sizeOf(RegisterName)});
    // std.debug.print("size of Operand {}\n", .{@sizeOf(Operand)});
    // std.debug.print("size of usize {}\n", .{@sizeOf(usize)});
    // std.debug.print("size of i32 {}\n", .{@sizeOf(i32)});
    // std.debug.print("size of []const u8 {}\n", .{@sizeOf([]const u8)});
    // std.debug.print("size of OperandTag {}\n", .{@sizeOf(OperandTag)});
    // std.debug.print("size of Instr {}\n", .{@sizeOf(Instr)});

    defer alloc.free(instructions);

    //std.debug.print("allocator: {d} \n", .{fba.end_index});

    const instr_length = try decode(filename, alloc, fba, &instructions);

    if (exec) {
        var memory = MemorySim{};
        try simulate_instructions(&instructions, instr_length, &memory, alloc);
        try print_memory(memory);
    } else {
        try print_instructions(&instructions, instr_length, alloc);
    }
}

fn simulate_instructions(instructions: *[]Instr, instr_length: u16, memory: *MemorySim, alloc: Allocator) !void {
    var i: u16 = 0;

    while (i < instr_length) : (i += 1) {
        var instr = instructions.*[i];
        try print_instruction(instr, alloc);
        try simulate_instruction(instr, memory);
        try stdout.print("\r\n", .{}); // stupid windows
    }
}

fn simulate_instruction(inst: Instr, memory: *MemorySim) !void {
    switch (inst.name) {
        InstrName.mov => {
            const register = inst.dest.?.register;
            const old_value = memory.read(register);
            memory.mov(inst.dest.?, inst.source.?);
            const new_value = memory.read(register);
            try stdout.print(" ; {s}:0x{x}->0x{x} ", .{ register.string(), old_value, new_value });
        },
        else => {
            unreachable;
        },
    }
}

fn print_memory(memory: MemorySim) !void {
    try stdout.print("Final registers:\r\n", .{});
    try stdout.print("      ax: 0x{x:0>4} ({d})\r\n", .{ memory.ax, memory.ax });
    try stdout.print("      bx: 0x{x:0>4} ({d})\r\n", .{ memory.bx, memory.bx });
    try stdout.print("      cx: 0x{x:0>4} ({d})\r\n", .{ memory.cx, memory.cx });
    try stdout.print("      dx: 0x{x:0>4} ({d})\r\n", .{ memory.dx, memory.dx });
    try stdout.print("      sp: 0x{x:0>4} ({d})\r\n", .{ memory.sp, memory.sp });
    try stdout.print("      bp: 0x{x:0>4} ({d})\r\n", .{ memory.bp, memory.bp });
    try stdout.print("      si: 0x{x:0>4} ({d})\r\n", .{ memory.si, memory.si });
    try stdout.print("      di: 0x{x:0>4} ({d})\r\n", .{ memory.di, memory.di });
}

fn print_instruction(instr: Instr, alloc: Allocator) !void {
    if (instr.jmp_offset) |label| {
        try stdout.print("{s} {?d}", .{ instr.name.string(), label });
    } else if (instr.dest) |dest| {
        if (instr.source) |source| {
            try stdout.print("{s} {s}, {s}", .{ instr.name.string(), try dest.string(alloc), try source.string(alloc) });
        } else {
            unreachable;
        }
    } else {
        unreachable;
    }
}

fn print_instructions(instructions: *[]Instr, instr_length: u16, alloc: Allocator) !void {
    try stdout.print("bits 16\n\n", .{});

    var i: u16 = 0;

    while (i < instr_length) : (i += 1) {
        var instr = instructions.*[i];
        try print_instruction(instr, alloc);
        try stdout.print("\n", .{});
    }
}

fn decode(filename: []const u8, alloc: Allocator, fba: FixedBufferAllocator, instructions: *[]Instr) !u16 {
    //std.debug.print("allocator: {d} \n", .{fba.end_index});
    _ = fba;

    var file = try fs.cwd().openFile(filename, .{});
    defer file.close();

    var buffer: [1000]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);

    var i: usize = 0;
    var idx: u16 = 0;

    while (i < bytes_read) {
        //std.debug.print("progress: {d} of {d}\n", .{ i, bytes_read });
        //std.debug.print("allocator: {d} \n", .{fba.end_index});
        var instr = try decode_instruction(buffer[i..], alloc);
        (instructions.*)[idx] = instr;
        i += instr.bytes_read;
        idx += 1;
    }

    return idx;
}

fn decode_instruction(bytes: []u8, alloc: Allocator) !Instr {
    const four_bit_inst_code: u8 = nth_bits(u8, bytes[0], 4, 4);
    const six_bit_inst_code: u8 = nth_bits(u8, bytes[0], 2, 6);
    const seven_bit_inst_code: u8 = nth_bits(u8, bytes[0], 1, 7);
    const eight_bit_inst_code: u8 = bytes[0];

    const four_bit_instruction = switch (four_bit_inst_code) {
        0b1011 => InstType.mov_imm_to_reg,
        else => null,
    };

    const six_bit_instruction = switch (six_bit_inst_code) {
        0b100010 => InstType.mov_regmem_to_regmem,
        0b000000, 0b001010, 0b001110 => InstType.any_regmem_to_regmem,
        0b100000 => InstType.any_imm_to_regmem,
        else => null,
    };

    const seven_bit_instruction = switch (seven_bit_inst_code) {
        0b0000010, 0b0010110, 0b001110, 0b0011110 => InstType.any_imm_to_acc,
        else => null,
    };

    const eight_bit_instruction = switch (eight_bit_inst_code) {
        0b0111_0000, 0b0111_0001, 0b0111_0010, 0b0111_0011, 0b0111_0100, 0b0111_0101, 0b0111_0110, 0b0111_0111, 0b0111_1000, 0b0111_1010, 0b0111_1011, 0b0111_1100, 0b0111_1101, 0b0111_1110, 0b0111_1111, 0b1110_0000, 0b1110_0001, 0b1110_0010, 0b1110_0011, 0b0111_1001 => InstType.any_jump,
        else => null,
    };

    //std.debug.print("{b:0>8}\n", .{bytes[0]});

    const instr_type = eight_bit_instruction orelse seven_bit_instruction orelse six_bit_instruction orelse four_bit_instruction orelse InstType.unknown;

    const inst = switch (instr_type) {
        InstType.mov_imm_to_reg => try decode_mov_imm_to_reg(bytes),
        InstType.mov_regmem_to_regmem => try decode_any_regmem_to_regmem(InstrName.mov, bytes, alloc),
        InstType.any_regmem_to_regmem => try decode_any_regmem_to_regmem(op_name(instr_type, six_bit_inst_code, bytes), bytes, alloc),
        InstType.any_imm_to_acc => try decode_any_imm_to_acc(op_name(instr_type, six_bit_inst_code, bytes), bytes),
        InstType.any_imm_to_regmem => try decode_any_imm_to_memreg(op_name(instr_type, six_bit_inst_code, bytes), bytes, alloc),
        InstType.any_jump => try any_jump(eight_bit_inst_code, bytes),
        else => unreachable,
    };

    return inst;
}

fn op_name(instr_type: InstType, six_bit_inst_code: u8, bytes: []u8) InstrName {
    return switch (instr_type) {
        InstType.any_regmem_to_regmem => subcode_op_name(six_bit_inst_code, bytes),
        InstType.any_imm_to_acc => subcode_op_name(six_bit_inst_code, bytes),
        InstType.any_imm_to_regmem => subcode_op_name(six_bit_inst_code, bytes),
        else => unreachable,
    };
}

fn any_jump(eight_bit_instruction: u8, bytes: []u8) !Instr {
    //std.debug.print("{b:0>8} {b:0>8} {b:0>8} \n", .{ bytes[0], bytes[1], bytes[2] });

    const jmp_offset = decode_value(bytes[1..2], true);

    const name = switch (eight_bit_instruction) {
        0b0111_0000 => InstrName.jo,
        0b0111_0001 => InstrName.jno,
        0b0111_0010 => InstrName.jb,
        0b0111_0011 => InstrName.jnb,
        0b0111_0100 => InstrName.je,
        0b0111_0101 => InstrName.jnz,
        0b0111_0110 => InstrName.jbe,
        0b0111_0111 => InstrName.ja,
        0b0111_1000 => InstrName.js,
        0b0111_1001 => InstrName.jns,
        0b0111_1010 => InstrName.jp,
        0b0111_1011 => InstrName.jnp,
        0b0111_1100 => InstrName.jl,
        0b0111_1101 => InstrName.jnl,
        0b0111_1110 => InstrName.jle,
        0b0111_1111 => InstrName.jg,
        0b1110_0000 => InstrName.loopnz,
        0b1110_0001 => InstrName.loopz,
        0b1110_0010 => InstrName.loop,
        0b1110_0011 => InstrName.jcxz,
        else => unreachable,
    };

    return Instr{ .name = name, .jmp_offset = jmp_offset, .bytes_read = 2 };
}

fn decode_any_imm_to_acc(op: InstrName, bytes: []u8) !Instr {
    //std.debug.print("...all 6 bytes {b} {b} {b} {b} {b} {b}\n\n", .{ bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5] });

    const wide = (bytes[0] & 0b00000001) == 1;
    var reg: RegisterName = undefined;
    var value: i32 = undefined;
    var bytes_read: u4 = undefined;

    if (wide) {
        reg = RegisterName.ax;
        value = decode_value(bytes[1..3], true);
        bytes_read = 3;
    } else {
        reg = RegisterName.al;
        value = decode_value(bytes[1..2], true);
        bytes_read = 2;
    }

    return Instr{
        .name = op,
        .dest = Operand{ .register = reg },
        .source = Operand{ .value = @intCast(value) },
        .bytes_read = bytes_read,
    };
}

fn subcode_op_name(instr: u8, bytes: []u8) InstrName {
    const sub_code = switch (instr) {
        0b100000 => blk: {
            break :blk nth_bits(u8, bytes[1], 3, 3);
        },
        else => blk: {
            break :blk nth_bits(u8, bytes[0], 3, 3);
        },
    };

    //std.debug.print("subcode {b}", .{sub_code});

    const op = switch (sub_code) {
        0b000 => InstrName.add,
        0b101 => InstrName.sub,
        0b111 => InstrName.cmp,
        else => unreachable,
    };

    return op;
}

fn decode_mov_imm_to_reg(bytes: []u8) !Instr {
    const wide = ((bytes[0] & 0b00001000) >> 3) == 1;
    const reg_code = (bytes[0] & 0b00000111);

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

    return Instr{
        .name = InstrName.mov,
        .dest = Operand{ .register = reg },
        .source = Operand{ .value = @intCast(decode_value(imm_bytes, signed)) },
        .bytes_read = bytes_read,
    };
}

fn eac_string(r_m: u8, mod: u8, bytes: []u8, signed: bool, wide: bool, alloc: Allocator, add_prefix: bool) ![]const u8 {
    const eac = effective_address_calculation(r_m, mod, bytes, signed);
    var str: []const u8 = undefined;
    if (eac.direct_address > -1) {
        str = try std.fmt.allocPrint(alloc, "[{d}]", .{eac.direct_address});
    } else if (eac.displacement > -1) {
        str = try std.fmt.allocPrint(alloc, "[{s} + {d}]", .{ eac.registers, eac.displacement });
    } else {
        str = try std.fmt.allocPrint(alloc, "[{s}]", .{eac.registers});
    }

    var prefix: []const u8 = undefined;

    if (add_prefix) {
        prefix = if (wide) "word " else "byte ";
    } else {
        prefix = "";
    }

    return try std.fmt.allocPrint(alloc, "{s}{s}", .{ prefix, str });
}

fn decode_any_imm_to_memreg(op: InstrName, bytes: []u8, alloc: Allocator) !Instr {
    const wide = nth_bits(u8, bytes[0], 0, 1) == 1;
    const signed = nth_bits(u8, bytes[0], 1, 1) == 1;
    const mod = (bytes[1] & 0b11000000) >> 6;
    const r_m = (bytes[1] & 0b00000111);
    var dest: Operand = undefined;

    //std.debug.print("w: {}, mod: {b}, r_m: {b}, wide {}, signed {}\n", .{ wide, mod, r_m, wide, signed });

    var bytes_read: u4 = 2;

    var source: i32 = undefined;
    var imm_bytes: []u8 = undefined;

    if (mod == 0b11) {
        // mod == 11 is "register mode", so there are no displacement bytes
        const reg = register_name(r_m, wide);

        if (!signed and wide) {
            // define a slice using the [start..end] syntax. slice begins at array[start] and ends just before array[end].
            imm_bytes = bytes[2..4];
        } else {
            imm_bytes = bytes[2..3];
        }

        // I know that the imm_bytes.length is 0 or 1
        bytes_read += @intCast(imm_bytes.len);
        source = decode_value(imm_bytes, signed);
        dest = Operand{ .register = reg };
    } else if ((mod == 0b00)) {
        // memory mode, no displacement follows
        // Except when R/M = 110, then 16-bit displacement follows

        //std.debug.print("w: {}, mod: {b}, r_m: {b}, wide {}, signed {}\n", .{ wide, mod, r_m, wide, signed });

        //std.debug.print("all 6 bytes {b} {b} {b} {b} {b} {b}\n\n", .{ bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5] });

        var imm_byte_index: u8 = 2;
        if (r_m == 0b110) {
            // Except when R/M = 110, then 16-bit displacement follows
            imm_byte_index += 2;
            bytes_read += 2;
        }

        if (!signed and wide) {
            // define a slice using the [start..end] syntax. slice begins at array[start] and ends just before array[end].
            imm_bytes = bytes[imm_byte_index .. imm_byte_index + 2];
        } else {
            imm_bytes = bytes[imm_byte_index .. imm_byte_index + 1];
        }

        // I know that the imm_bytes.length is 0 or 1
        bytes_read += @intCast(imm_bytes.len);
        source = decode_value(imm_bytes, signed);
        dest = Operand{ .location = try eac_string(r_m, mod, bytes[2..], signed, wide, alloc, true) };
    } else if (mod == 0b10) {
        // memory mode, 16-bit displacement
        if (!signed and wide) {
            // define a slice using the [start..end] syntax. slice begins at array[1] and ends just before array[4].
            imm_bytes = bytes[4..6];
        } else {
            imm_bytes = bytes[4..5];
        }

        // I know that the imm_bytes.length is 0 or 1
        bytes_read += @intCast(2 + imm_bytes.len);
        source = decode_value(imm_bytes, signed);
        dest = Operand{ .location = try eac_string(r_m, mod, bytes[2..], signed, wide, alloc, true) };
    } else {
        //std.debug.print("mod {b}\n\n", .{mod});
        unreachable;
    }

    return Instr{
        .name = op,
        .dest = dest,
        .source = Operand{ .value = @intCast(source) },
        .bytes_read = bytes_read,
    };
}

// get the bit at the kth position (from the right)
// for n biths
fn nth_bits(comptime T: type, value: T, comptime k: u4, comptime n: u4) T {
    var i: u4 = 1;
    var bitmask: T = 1;

    while (i < n) {
        bitmask = bitmask << 1;
        bitmask += 1;
        i += 1;
    }

    bitmask = (bitmask << k);

    const masked = (value & bitmask);
    return masked >> k;
}

test "nth_bits" {
    try std.testing.expectEqual(@as(i32, 1), nth_bits(u8, 0b0000_0001, 0, 1));
    try std.testing.expectEqual(@as(i32, 0), nth_bits(u8, 0b0000_0001, 1, 1));

    try std.testing.expectEqual(@as(i32, 1), nth_bits(u8, 0b1111_1111, 1, 1));
    try std.testing.expectEqual(@as(i32, 1), nth_bits(u8, 0b1111_1111, 7, 1));

    try std.testing.expectEqual(@as(i32, 3), nth_bits(u8, 0b1111_1111, 0, 2));
    try std.testing.expectEqual(@as(i32, 7), nth_bits(u8, 0b1111_1111, 0, 3));
}

fn decode_value(bytes: []u8, signed: bool) i32 {
    //std.debug.print("bytes! {b}, signed: {}\n\n", .{ bytes, signed });

    if (bytes.len == 2) {
        var value: u16 = bytes[0];
        value = bytes[1];
        value = value << 8;
        value += bytes[0];

        if (signed and nth_bits(u16, value, 15, 1) == 1) {
            value = ~(value - 1);
            const ret: i16 = @intCast(value);
            return -ret;
        } else {
            return @intCast(value);
        }

        return value;
    } else {
        var value: u8 = bytes[0];

        if (signed and nth_bits(u8, value, 7, 1) == 1) {
            value = ~(value - 1);
            const ret: i16 = @intCast(value);
            return -ret;
        } else {
            return @intCast(value);
        }
    }

    // "S is used in conjunction with W to indicate sign extension
    // of immediate fields in arithmetic instructions"
    // "Sign extend 8-bit immediate data to 16 bits if W=1"
    // "If the displacement is only a single byte, the 8086 or 8088 automatically sign-extends this quantity to 16-bits before using the information in further address calculation"
}

// rm = register or memory
fn decode_any_regmem_to_regmem(op: InstrName, bytes: []u8, alloc: Allocator) !Instr {
    const signed = false;

    // 2 bits are "DW" (one bit each)
    // page 161 of manual
    const d = (bytes[0] & 0b00000010) >> 1;
    const wide = ((bytes[0] & 0b00000001) == 1);

    // 2 bits are "mod"
    // 3 bits are "reg"
    // 3 bits are r/m
    const mod = (bytes[1] & 0b11000000) >> 6;
    const reg = (bytes[1] & 0b00111000) >> 3;
    const r_m = (bytes[1] & 0b00000111);

    if (mod == 0b11) {
        var reg1 = register_name(reg, wide);
        var reg2 = register_name(r_m, wide);

        // TODO - restore
        // if (d == 0) {
        //     var temp = reg1;
        //     reg1 = reg2;
        //     reg2 = temp;
        // }
        if (d == 0) {
            reg1 = register_name(r_m, wide);
            reg2 = register_name(reg, wide);
        }

        return Instr{ .name = op, .dest = Operand{ .register = reg1 }, .source = Operand{ .register = reg2 }, .bytes_read = 2 };
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

        var dest = Operand{ .register = register_name(reg, wide) };

        //const eac = effective_address_calculation(r_m, mod, bytes[2..4], signed);

        // var source: []const u8 = undefined;

        // if (eac.displacement == -1) {
        //     source = try std.fmt.allocPrint(alloc, "[{s}]", .{eac.registers});
        // } else {
        //     source = try std.fmt.allocPrint(alloc, "[{s} + {d}]", .{ eac.registers, eac.displacement });
        // }

        var source: Operand = Operand{ .location = try eac_string(r_m, mod, bytes[2..4], signed, wide, alloc, false) };

        // TODO restore
        // if (d == 0) {
        //     var temp = dest;
        //     dest = source;
        //     source = temp;
        // }

        if (d == 0) {
            var temp = dest;
            _ = temp;
            dest = source;
            source = Operand{ .register = register_name(reg, wide) };
        }

        return Instr{ .name = op, .dest = dest, .source = source, .bytes_read = bytes_read };
    }
}

fn effective_address_calculation(r_m: u8, mod: u8, bytes: []u8, signed: bool) EffAddressCalc {
    //std.debug.print("r_m {b}, mod {b}\n\n", .{ r_m, mod });

    const byte_value = decode_value(bytes[0..1], signed);
    const word_value = decode_value(bytes[0..2], signed);

    if (r_m == 0b000 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bx + si" };
    } else if (r_m == 0b000 and mod == 0b01) {
        return EffAddressCalc{ .registers = "bx + si", .displacement = byte_value };
    } else if (r_m == 0b000 and mod == 0b10) {
        return EffAddressCalc{ .registers = "bx + si", .displacement = word_value };
    } else if (r_m == 0b001 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bx + di" };
    } else if (r_m == 0b001 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b001 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b010 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bp + si" };
    } else if (r_m == 0b010 and mod == 0b01) {
        return EffAddressCalc{ .registers = "bp + si", .displacement = byte_value };
    } else if (r_m == 0b010 and mod == 0b10) {
        return EffAddressCalc{ .registers = "bp + si", .displacement = word_value };
    } else if (r_m == 0b011 and mod == 0b10) {
        return EffAddressCalc{ .registers = "bp + di", .displacement = word_value };
    } else if (r_m == 0b011 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bp + di" };
    } else if (r_m == 0b011 and mod == 0b01) {
        return EffAddressCalc{ .registers = "bp + di", .displacement = byte_value };
    } else if (r_m == 0b100 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b100 and mod == 0b00) {
        return EffAddressCalc{ .registers = "si" };
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
        // direct address
        return EffAddressCalc{ .registers = "none", .direct_address = word_value };
    } else if (r_m == 0b110 and mod == 0b01) {
        return EffAddressCalc{ .registers = "bp", .displacement = byte_value };
    } else if (r_m == 0b111 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b00) {
        return EffAddressCalc{ .registers = "bx" };
    } else if (r_m == 0b111 and mod == 0b01) {
        return EffAddressCalc{ .registers = "bx", .displacement = byte_value };
    } else {
        unreachable;
    }

    unreachable;
}

// Register table is page 162
fn register_name(reg_code: u8, wide: bool) RegisterName {
    return switch (reg_code) {
        0b000 => (if (!wide) RegisterName.al else RegisterName.ax),
        0b001 => (if (!wide) RegisterName.cl else RegisterName.cx),
        0b010 => (if (!wide) RegisterName.dl else RegisterName.dx),
        0b011 => (if (!wide) RegisterName.bl else RegisterName.bx),
        0b100 => (if (!wide) RegisterName.ah else RegisterName.sp),
        0b101 => (if (!wide) RegisterName.ch else RegisterName.bp),
        0b110 => (if (!wide) RegisterName.dh else RegisterName.si),
        0b111 => (if (!wide) RegisterName.bh else RegisterName.di),
        else => unreachable,
    };
}
