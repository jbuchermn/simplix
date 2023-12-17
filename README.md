Playground for Allwinner D1 / Sipeed Lichee RV
==============================================

Ideas:
- Get minimal self-hosting linux running
- Get WiFi and networking running
- Test hw acceleration and other D1 features
- Try to build distro using nix on host

Next steps:
- Move from ./make_[...].sh to derivations
- Have an eye on kernel version (nix headers / glibc v. manually compiled kernel)

Issues:
- cross-native gcc with musl can't compile anything - issues with collect2

Some notes:
- Weird issues configuring u-boot... Fix ```touch scripts/kconfig/confdata.c```
