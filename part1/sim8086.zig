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
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

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
    jne,
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
    ip,
    pub fn string(self: RegisterName) []const u8 {
        return @tagName(self);
    }
};

const Location = struct {
    prefix: bool = false,
    wide: bool = false,
    reg1: ?RegisterName = null,
    reg2: ?RegisterName = null,
    displacement: ?u16 = null,

    pub fn address(self: Location, proc: *Processor) u16 {
        var addr: u16 = 0;

        if (self.reg1) |reg1| {
            addr += proc.read_reg(reg1);
        }

        if (self.reg2) |reg2| {
            addr += proc.read_reg(reg2);
        }

        if (self.displacement) |displacement| {
            addr += displacement;
        }

        return addr;
    }

    pub fn string(self: Location, alloc: Allocator) ![]const u8 {
        var prefix_str: []const u8 = "";
        var effective_address_str: []const u8 = undefined;
        defer alloc.free(effective_address_str);

        if (self.prefix) {
            prefix_str = if (self.wide) "word " else "byte ";
        }

        if (self.reg1) |reg1| {
            if (self.reg2) |reg2| {
                effective_address_str = try std.fmt.allocPrint(alloc, "[{s}+{s}]", .{ reg1.string(), reg2.string() });
            } else if (self.displacement) |displacement| {
                effective_address_str = try std.fmt.allocPrint(alloc, "[{s}+{d}]", .{ reg1.string(), displacement });
            } else {
                effective_address_str = try std.fmt.allocPrint(alloc, "[{s}]", .{reg1.string()});
            }
        } else if (self.displacement) |displacement| {
            effective_address_str = try std.fmt.allocPrint(alloc, "[+{d}]", .{displacement});
        } else {
            unreachable;
        }

        return try std.fmt.allocPrint(alloc, "{s}{s}", .{ prefix_str, effective_address_str });
    }
};

const OperandTag = enum { register, location, value };
const Operand = union(OperandTag) {
    register: RegisterName,
    value: u16,
    location: Location,

    pub fn string(self: Operand, alloc: Allocator) ![]const u8 {
        return switch (self) {
            // allocate so the caller can deallocate consistently
            Operand.register => try std.fmt.allocPrint(alloc, "{s}", .{self.register.string()}),
            Operand.location => self.location.string(alloc),
            Operand.value => try std.fmt.allocPrint(alloc, "{d}", .{self.value}),
        };
    }
};

const Instr = struct { name: InstrName, dest: ?Operand = null, source: ?Operand = null, bytes_read: u4, jmp_offset: ?i32 = null };
const InstType = enum { mov_imm_to_regmem, mov_regmem_to_regmem, mov_imm_to_reg, any_imm_to_regmem, any_regmem_to_regmem, add_sub_cmp_imm, any_imm_to_acc, any_jump, unknown };
const EffAddressCalc = struct { registers: []const u8, displacement: i32 = -1, direct_address: i32 = -1 };

const Processor = struct {
    ax: u16 = 0,
    bx: u16 = 0,
    cx: u16 = 0,
    dx: u16 = 0,
    sp: u16 = 0,
    bp: u16 = 0,
    si: u16 = 0,
    di: u16 = 0,
    ip: u16 = 0,
    zero: bool = false,
    signed: bool = false,
    parity: bool = false,
    memory: []u8,

    pub fn update_flags(self: *Processor, value: u16) void {
        self.zero = (value == 0);
        self.signed = (nth_bits(u16, value, 15, 1) == 1);
    }

    pub fn flags(self: *Processor) []const u8 {
        const signed_int: u4 = @intFromBool(self.signed);
        const signed_parity: u2 = @intFromBool(self.parity);
        const signed_zero: u1 = @intFromBool(self.zero);

        const flagsValue = signed_int << 2 | signed_parity << 1 | signed_zero;

        return switch (flagsValue) {
            0b000 => "",
            0b001 => "Z",
            0b010 => "P",
            0b011 => "PZ",
            0b100 => "S",
            0b101 => "SZ",
            0b110 => "SP",
            0b111 => "SPZ",
            else => unreachable,
        };
    }

    pub fn read_reg(self: *Processor, register: RegisterName) u16 {
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

    pub fn read(self: *Processor, operand: Operand) u16 {
        switch (operand) {
            Operand.register => |register| {
                return read_reg(self, register);
            },
            Operand.value => |value| {
                return value;
            },
            Operand.location => |loc| {
                if (loc.displacement) |displacement| {
                    return self.memory[displacement];
                } else {
                    unreachable;
                }
            },
        }
    }

    pub fn write(self: *Processor, operand: Operand, value: u16) void {
        switch (operand) {
            Operand.register => |register| {
                switch (register) {
                    RegisterName.ax => self.ax = value,
                    RegisterName.bx => self.bx = value,
                    RegisterName.cx => self.cx = value,
                    RegisterName.dx => self.dx = value,
                    RegisterName.sp => self.sp = value,
                    RegisterName.bp => self.bp = value,
                    RegisterName.si => self.si = value,
                    RegisterName.di => self.di = value,
                    else => unreachable,
                }
            },
            Operand.location => |loc| {
                const address = loc.address(self);

                if (loc.wide) {
                    const high_bits: u8 = @as(u8, @intCast((value & 0b1111_1111_0000_0000) << 8));
                    const low_bits: u8 = @as(u8, @truncate(value));

                    self.memory[address] = low_bits;
                    self.memory[address + 1] = high_bits;
                } else {
                    self.memory[address] = @as(u8, @truncate(value));
                }
            },
            else => unreachable,
        }
    }

    pub fn copy(self: *Processor) Processor {
        return Processor{ .ax = self.ax, .bx = self.bx, .cx = self.cx, .dx = self.dx, .sp = self.sp, .bp = self.bp, .si = self.si, .di = self.di };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

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

    var file = try fs.cwd().openFile(filename, .{});
    defer file.close();
    try file.seekTo(0);
    var buffer: [10_000]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);

    if (exec) {
        var memory = [_]u8{0} ** 65536;
        var proc = Processor{ .memory = &memory };
        try simulate_instructions(&buffer, bytes_read, &proc, alloc);
        try print_proc(&proc);
        try dump_results_to_file(proc);
    } else {
        try print_instructions(&buffer, bytes_read, alloc);
    }
}

fn dump_results_to_file(proc: Processor) !void {
    const file = try std.fs.cwd().createFile(
        "dump.data",
        .{ .read = true },
    );
    defer file.close();

    try file.writeAll(proc.memory);
}

fn simulate_instructions(buffer: []u8, bytes_read: usize, proc: *Processor, alloc: Allocator) !void {
    while (proc.ip < bytes_read) {
        var instr = try decode_instruction(buffer[proc.ip..]);
        try print_instruction(instr, alloc);
        try simulate_instruction(instr, proc);
        try stdout.print("\r\n", .{}); // stupid windows
    }
}

fn simulate_instruction(inst: Instr, proc: *Processor) !void {
    var old_value: u16 = undefined;
    var new_value: u16 = undefined;
    const old_flags = proc.flags();
    const old_ip = proc.ip;

    proc.ip = old_ip + inst.bytes_read;

    switch (inst.name) {
        InstrName.mov => {
            old_value = proc.read(inst.dest.?);
            proc.write(inst.dest.?, proc.read(inst.source.?));
            new_value = proc.read(inst.dest.?);
        },
        InstrName.sub => {
            old_value = proc.read(inst.dest.?);
            const value = proc.read(inst.dest.?) -% proc.read(inst.source.?);
            proc.write(inst.dest.?, value);
            proc.update_flags(value);
            new_value = proc.read(inst.dest.?);
        },
        InstrName.add => {
            old_value = proc.read(inst.dest.?);
            const value = proc.read(inst.dest.?) +% proc.read(inst.source.?);
            proc.write(inst.dest.?, value);
            proc.update_flags(value);
            new_value = proc.read(inst.dest.?);
        },
        InstrName.cmp => {
            old_value = proc.read(inst.dest.?);
            const value = proc.read(inst.dest.?) -% proc.read(inst.source.?);
            proc.update_flags(value);
            new_value = proc.read(inst.dest.?);
        },
        InstrName.jne => {
            const offset: i32 = inst.jmp_offset.?;
            if (!proc.zero) {
                proc.ip = @as(u16, @intCast(proc.ip + offset));
            }
        },
        else => {
            unreachable;
        },
    }

    const new_flags = proc.flags();
    const new_ip = proc.ip;

    try stdout.print(" ; ", .{});

    if (inst.dest != null and inst.dest.? == OperandTag.register) {
        try stdout.print("{s}:0x{x}->0x{x} ", .{
            inst.dest.?.register.string(),
            old_value,
            new_value,
        });
    }

    try stdout.print("ip:0x{x}->0x{x} ", .{ old_ip, new_ip });

    if (!std.mem.eql(u8, old_flags, new_flags)) {
        try stdout.print("flags:{s}->{s} ", .{ old_flags, new_flags });
    }
}

fn print_proc(proc: *Processor) !void {
    try stdout.print("\r\nFinal registers:\r\n", .{});

    const registers = [_]struct { name: []const u8, value: u16 }{
        .{ .name = "ax", .value = proc.ax },
        .{ .name = "bx", .value = proc.bx },
        .{ .name = "cx", .value = proc.cx },
        .{ .name = "dx", .value = proc.dx },
        .{ .name = "sp", .value = proc.sp },
        .{ .name = "bp", .value = proc.bp },
        .{ .name = "si", .value = proc.si },
        .{ .name = "di", .value = proc.di },
        .{ .name = "ip", .value = proc.ip },
    };

    for (registers) |reg| {
        if (reg.value != 0) {
            try stdout.print("      {s}: 0x{x:0>4} ({d})\r\n", .{ reg.name, reg.value, reg.value });
        }
    }

    try stdout.print("   flags: {s}\r\n\r\n", .{proc.flags()});
}

test "allocPrint usage" {
    const alloc = std.testing.allocator;
    const str = try std.fmt.allocPrint(alloc, "[{d} {d}]", .{ 1, 2 });
    defer alloc.free(str);
    try stdout.print("      {s}\r\n", .{str});
}

fn print_instruction(instr: Instr, alloc: Allocator) !void {
    if (instr.jmp_offset) |label| {
        try stdout.print("{s} ${d}", .{ instr.name.string(), label + instr.bytes_read });
    } else if (instr.dest) |dest| {
        if (instr.source) |source| {
            const s1: []const u8 = try dest.string(alloc);
            const s2: []const u8 = try source.string(alloc);

            try stdout.print("s1: {s}, ptr {*} , len {d}\n", .{ s1, s1.ptr, s1.len });
            try stdout.print("s2: {s}, ptr {*} , len {d}\n", .{ s2, s2.ptr, s2.len });

            defer alloc.free(s1);
            defer alloc.free(s2);

            try stdout.print("{s} {s}, {s}", .{ instr.name.string(), s1, s2 });
        } else {
            unreachable;
        }
    } else {
        unreachable;
    }
}

fn print_instructions(buffer: []u8, bytes_read: usize, alloc: Allocator) !void {
    try stdout.print("bits 16\n\n", .{});

    var i: u16 = 0;

    while (i < bytes_read) {
        var instr = try decode_instruction(
            buffer[i..],
        );
        i += instr.bytes_read;
        try print_instruction(instr, alloc);
        try stdout.print("\n", .{});
    }
}

fn decode_instruction(bytes: []u8) !Instr {
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
        0b1100011 => InstType.mov_imm_to_regmem,
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
        InstType.mov_regmem_to_regmem => try decode_any_regmem_to_regmem(InstrName.mov, bytes),
        InstType.any_regmem_to_regmem => try decode_any_regmem_to_regmem(op_name(instr_type, six_bit_inst_code, bytes), bytes),
        InstType.any_imm_to_acc => try decode_any_imm_to_acc(op_name(instr_type, six_bit_inst_code, bytes), bytes),
        InstType.any_imm_to_regmem => try decode_any_imm_to_memreg(op_name(instr_type, six_bit_inst_code, bytes), bytes),
        InstType.mov_imm_to_regmem => try decode_any_imm_to_memreg(InstrName.mov, bytes),
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
        0b0111_0101 => InstrName.jne,
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

test "decode_any_imm_to_memreg" {
    // add
    var bytes = [_]u8{
        0b100000_11, // signed, wide
        0b00_000_110, // mod 00, rm = direct address
        0b11101000, // low bits of 1000
        0b00000011, // high bits of 1000
        0b00000001, // value is one (low bits)
        0b00000000, // rest of value (high bits)
    };
    var actual = try decode_instruction(&bytes);
    var expected = Instr{ .name = InstrName.add, .bytes_read = 5, .dest = Operand{ .location = Location{ .displacement = 1000, .prefix = true } }, .source = Operand{ .value = 1 } };
    try std.testing.expectEqual(expected.dest.?.location.displacement, actual.dest.?.location.displacement);
    try std.testing.expectEqual(expected.dest.?.location.prefix, actual.dest.?.location.prefix);
    try std.testing.expectEqual(expected.name, actual.name);
    try std.testing.expectEqual(expected.bytes_read, actual.bytes_read);
    try std.testing.expectEqual(expected.source.?.value, actual.source.?.value);

    // wide mov
    bytes = [_]u8{
        0b1100011_1, // wide
        0b00_000_110, // mod 00, rm = direct address
        0b11101000, // low bits of 1000
        0b00000011, // high bits of 1000
        0b00000001, // value is one (low bits)
        0b00000000, // rest of value (high bits)
    };
    actual = try decode_instruction(&bytes);
    expected = Instr{ .name = InstrName.mov, .bytes_read = 6, .dest = Operand{ .location = Location{ .prefix = true, .displacement = 1000 } }, .source = Operand{ .value = 1 } };
    try std.testing.expectEqual(expected.dest.?.location.displacement, actual.dest.?.location.displacement);
    try std.testing.expectEqual(expected.dest.?.location.prefix, actual.dest.?.location.prefix);
    try std.testing.expectEqual(expected.name, actual.name);
    try std.testing.expectEqual(expected.bytes_read, actual.bytes_read);
    try std.testing.expectEqual(expected.source.?.value, actual.source.?.value);
}

fn decode_any_imm_to_memreg(op: InstrName, bytes: []u8) !Instr {
    const wide = nth_bits(u8, bytes[0], 0, 1) == 1;
    const signed = (op != InstrName.mov and nth_bits(u8, bytes[0], 1, 1) == 1);
    const mod = (bytes[1] & 0b11000000) >> 6;
    const r_m = (bytes[1] & 0b00000111);
    var dest: Operand = undefined;

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
    } else if (mod == 0b00) {
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
        dest = Operand{ .location = location(r_m, mod, bytes[2..], signed, wide, true) };
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
        dest = Operand{ .location = location(r_m, mod, bytes[2..], signed, wide, true) };
    } else if (mod == 0b01) {
        // memory mode, 8-bit displacement
        if (!signed and wide) {
            // define a slice using the [start..end] syntax. slice begins at array[1] and ends just before array[4].
            imm_bytes = bytes[3..5];
        } else {
            imm_bytes = bytes[3..4];
        }

        // I know that the imm_bytes.length is 0 or 1
        bytes_read += @intCast(1 + imm_bytes.len);
        source = decode_value(imm_bytes, signed);
        dest = Operand{ .location = location(r_m, mod, bytes[2..], signed, wide, true) };
    } else {
        std.debug.print("unexpected mod {b}\n\n", .{mod});
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
// for n bits
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

test "decode_any_regmem_to_memreg" {
    var bytes = [_]u8{
        0b100010_11, // mov, wide and d=1
        0b00_011_110, // mod=0, reg=bx rm 110
        0b11101000, // 1000 (lower bits)
        0b00000011, // 1000 (upper bits, more significant)
    };
    var actual = try decode_any_regmem_to_regmem(InstrName.mov, &bytes);
    var expected = Instr{
        .name = InstrName.mov,
        .bytes_read = 4,
        .dest = Operand{ .register = RegisterName.bx },
        .source = Operand{ .location = Location{ .displacement = 1000 } },
    };
    try std.testing.expectEqual(expected.source.?.location.displacement, actual.source.?.location.displacement);
    try std.testing.expectEqual(expected.source.?.location.prefix, actual.source.?.location.prefix);
    try std.testing.expectEqual(expected.name, actual.name);
    try std.testing.expectEqual(expected.bytes_read, actual.bytes_read);
    try std.testing.expectEqual(expected.dest.?.register, actual.dest.?.register);
}

// rm = register or memory
fn decode_any_regmem_to_regmem(op: InstrName, bytes: []u8) !Instr {
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
        // register mode, no displacement
        var reg1 = register_name(reg, wide);
        var reg2 = register_name(r_m, wide);

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
            // 16-bit replacement follows
            bytes_read += 2;
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

        var source: Operand = Operand{ .location = location(r_m, mod, bytes[2..4], signed, wide, false) };

        if (d == 0) {
            dest = source;
            source = Operand{ .register = register_name(reg, wide) };
        }

        return Instr{ .name = op, .dest = dest, .source = source, .bytes_read = bytes_read };
    }
}

fn location(r_m: u8, mod: u8, bytes: []u8, signed: bool, wide: bool, prefix: bool) Location {
    var byte_value: u16 = 0;
    var word_value: u16 = 0;

    if (mod == 0b10 or (r_m == 0b110 and mod == 0b00)) {
        word_value = @as(u16, @intCast(decode_value(bytes[0..2], signed)));
    }
    if (mod == 0b01) {
        byte_value = @as(u16, @intCast(decode_value(bytes[0..1], signed)));
    }

    if (r_m == 0b000 and mod == 0b00) {
        return Location{
            .reg1 = RegisterName.bx,
            .reg2 = RegisterName.si,
        };
    } else if (r_m == 0b000 and mod == 0b01) {
        return Location{ .reg1 = RegisterName.bx, .reg2 = RegisterName.si, .displacement = byte_value, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b000 and mod == 0b10) {
        return Location{ .reg1 = RegisterName.bx, .reg2 = RegisterName.si, .displacement = word_value, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b001 and mod == 0b00) {
        return Location{ .reg1 = RegisterName.bx, .reg2 = RegisterName.di, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b001 and mod == 0b01) {
        unreachable;
    } else if (r_m == 0b001 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b010 and mod == 0b00) {
        return Location{ .reg1 = RegisterName.bp, .reg2 = RegisterName.si };
    } else if (r_m == 0b010 and mod == 0b01) {
        return Location{ .reg1 = RegisterName.bp, .reg2 = RegisterName.si, .displacement = byte_value, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b010 and mod == 0b10) {
        return Location{ .reg1 = RegisterName.bp, .reg2 = RegisterName.si, .displacement = word_value, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b011 and mod == 0b10) {
        return Location{ .reg1 = RegisterName.bp, .reg2 = RegisterName.di, .displacement = word_value, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b011 and mod == 0b00) {
        return Location{ .reg1 = RegisterName.bp, .reg2 = RegisterName.di, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b011 and mod == 0b01) {
        return Location{ .reg1 = RegisterName.bp, .reg2 = RegisterName.di, .displacement = byte_value, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b100 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b100 and mod == 0b00) {
        return Location{ .reg1 = RegisterName.si };
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

        return Location{ .displacement = word_value, .wide = wide, .prefix = prefix };
    } else if (r_m == 0b110 and mod == 0b01) {
        return Location{ .reg1 = RegisterName.bp, .displacement = byte_value, .prefix = prefix };
    } else if (r_m == 0b111 and mod == 0b10) {
        unreachable;
    } else if (r_m == 0b111 and mod == 0b00) {
        return Location{ .reg1 = RegisterName.bx };
    } else if (r_m == 0b111 and mod == 0b01) {
        return Location{ .reg1 = RegisterName.bx, .displacement = byte_value, .wide = wide, .prefix = prefix };
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
