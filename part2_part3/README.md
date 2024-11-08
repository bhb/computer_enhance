# Usage

`zig build run -- --help`


```
zig build -Doptimize=ReleaseFast
./zig-out/bin/part2 --count 1000000 --rseed 234809
```

## Timing

723625bd87b6cf90928f5c85c0d27c1d5c6d8e34 - 3.8s for 1,000,00 pairs

## Debugger example

```
zig build
lldb ./zig-out/bin/part2 -- --count 10 --rseed 20801 --method cluster --verify foo --profile
b 'readJson'
r
```

## Disassembly

1. Pull relevant code into function (makes disassembly easier to see, I think)
2. `zig build -Doptimize=ReleaseFast -Dcpu="baseline"` . Simplifies code, but beware that optimizer may delete code if variables are not used. 'baseline' does not eliminate simd, but seems to make assembly a little simpler (?)
3. `lldb ./zig-out/bin/part2 -- --count 10 --rseed 20801 --method cluster --verify foo --profile`
4. `b <method name>` (or `br <line number>`)
5. `dis -m`
6. Scroll up to find the relevant code
