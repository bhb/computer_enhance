#  Usage:

`zig run sim8086.zig -- <binary file>`

Manual is https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf
Page 164 for byte patterns for instructions
 Page 64 for clocks

# To debug

```
zig build-exe sim8086.zig
lldb sim8086
settings set -- target.run-args listing_0041_add_sub_cmp_jnz
b <some method>
run
```

