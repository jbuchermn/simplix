Simplix - hacky and simple linux distro for embedded using Nix
==============================================

Done:
- Get WiFi and networking running
- Try to build distro using nix on host

Next steps:
- ARM64
    - Boot qemu with ATF
    - Boot Raspberry Pi
    - Boot BPI M2 ZERO
- Simple status display using gpio leds
- Create common nix for kernel / u-boot - or use nixpkgs version
- Adjust partition sizes
- Allow only changing certain parts in make.sh

Ideas / Notes:
- Have an eye on kernel version (nix headers / glibc v. manually compiled kernel)
- Get minimal self-hosting linux running
- Test hw acceleration and other D1 features
- OTA updates of the root fs (maybe bluetooth) + get logs
