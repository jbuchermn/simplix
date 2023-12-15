TODO

- [ ] Get cross-native compiler running
- [ ] Make toybox build with musl-cross-make toolchain (only linux headers missing)
- [ ] Build /init, initfs, bootfs, rootfs

--------

1. Setting up CC toolchain

https://nix.dev/tutorials/cross-compilation.html

2. QEMU

No SPL
    - Mainline OpenSBI
    - Mainline u-boot

3. D1 

- Compiling OpenSBI and u-boot

https://linux-sunxi.org/Allwinner_Nezha#Manual_build
    - Mainline OpenSBI
    - Patched u-boot smaeul/d1-wip
