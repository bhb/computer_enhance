Assemently for this zig code

```
fn writeAllBytes(dest_buffer: Buffer) void {
    // HERE - need to run this
    var idx: u64 = 0;
    while (idx < dest_buffer.count) : (idx += 1) {
        dest_buffer.data[idx] = @as(u8, @intCast(idx & 0xFF));
    }
    bufferToAvoidOptimization = dest_buffer;
}
```

```
-> 413          dest_buffer.data[idx] = @as(u8, @intCast(idx & 0xFF));
-> 414      }

->  0x1000074a0 <+1372>: add    x9, x27, x8

   410      // HERE - need to run this
   411      var idx: u64 = 0;
** 412      while (idx < dest_buffer.count) : (idx += 1) {

    0x1000074a4 <+1376>: adds   x8, x8, #0x20

** 413          dest_buffer.data[idx] = @as(u8, @intCast(idx & 0xFF));

    0x1000074a8 <+1380>: add.16b v1, v0, v2
    0x1000074ac <+1384>: str    q0, [x9, #0x2700]
    0x1000074b0 <+1388>: add.16b v0, v0, v3
    0x1000074b4 <+1392>: str    q1, [x9, #0x2710]

** 412      while (idx < dest_buffer.count) : (idx += 1) {

    0x1000074b8 <+1396>: b.ne   0x1000074a0               ; <+1372> [inlined] main.writeAllBytes at main.zig:413:41
```

### from claude

Certainly! Let's go through this assembly code step by step, focusing on the registers and their usage:

1. `0x1000074a4 <+1376>: adds   x8, x8, #0x20`
   - This instruction adds 32 (0x20 in hex) to the 64-bit register x8.
   - The 's' in 'adds' means it sets the condition flags based on the result.
   - x8 is likely being used as a loop counter or index.

2. `0x1000074a8 <+1380>: add.16b v1, v0, v2`
   - This is a SIMD instruction operating on 128-bit vector registers.
   - It adds the 16 bytes in v0 to the 16 bytes in v2, storing the result in v1.
   - v0, v1, v2 are 128-bit vector registers, each containing 16 bytes.

3. `0x1000074ac <+1384>: str    q0, [x9, #0x2700]`
   - This stores the entire 128-bit contents of q0 to memory.
   - q0 is the same as v0, just a different name for the full 128-bit register.
   - The memory address is calculated as x9 + 0x2700.

4. `0x1000074b0 <+1388>: add.16b v0, v0, v3`
   - Another SIMD instruction, adding v0 and v3, storing the result back in v0.

5. `0x1000074b4 <+1392>: str    q1, [x9, #0x2710]`
   - Stores the 128-bit contents of q1 (same as v1) to memory at address x9 + 0x2710.

6. `0x1000074b8 <+1396>: b.ne   0x1000074a0`
   - This is a conditional branch instruction.
   - It branches to address 0x1000074a0 if the condition flags indicate "not equal".
   - The condition flags were set by the 'adds' instruction at the beginning.

Regarding register naming:
- x0-x30 are 64-bit general-purpose registers.
- w0-w30 refer to the lower 32 bits of the corresponding x registers.
- v0-v31 are 128-bit vector registers used for SIMD operations.
- q0-q31 refer to the full 128 bits of the corresponding v registers.
- d0-d31 refer to the lower 64 bits of the corresponding v registers.
- s0-s31 refer to the lower 32 bits of the corresponding v registers.

In this code:
- x8 and x9 are used as general-purpose registers, likely for loop control and memory addressing.
- v0, v1, v2, v3 (and their q equivalents) are used for SIMD operations, processing 16 bytes at a time.

The code appears to be implementing a loop that processes data in 32-byte chunks (two 16-byte SIMD operations per iteration), which aligns with the original Zig code's purpose of filling a buffer.


### My summary

x8 is 64 bits
v0 is 128 bits or 64 bytes
q0 is same as v0, but we use the whole value

x8 = 0
v0 = 0 .. 16
v1 = 16 .. 31

then we store all of v0 (as q0) to memory at 0x2700 
then we store all of v1 (as q1) to memory at 0x2710 (0x0010 or 16 bytes later)

then we loop back, inc x8 by 32

instructions start at 0x1000074a0
last instruction is 0x1000074b8, but we need to include that instruction

Next line is

```
   95       pub fn stop(self: *RepetitionTester) void {
** 96           self.close_block_count += 1;

    0x1000074bc <+1400>: ldr    x8, [sp, #0x170]
```

So that's 0x1000074bc - 0x1000074a0 = 0x1C = 28
(or with offsets) +1400 - +1372 = 28

So that's 28 program bytes for each loop but each loop writes 32 bytes

Running the the program shows:

Min: 188 (0.01ms) 11.89 gb/s

Seems like a lot, but then again, it's doing 32 writes per loop

how many cycles per second is machine? (readings are 24000244, then 24000176, so let's say 24000000)

and bandwidth is 11.89 * 1024 * 1024

240000000 CPU cycles / (11.89 * 1024 * 1024) * bytes * (32 bytes / loop iteration ) =

61.6 cycles / loop iteration
and it's 28 program bytes of source
