Simplix - hacky and simple linux distro for embedded using Nix
==============================================

Status:
- Basic system with WiFi and SSH on ARM / RISC-V

Next steps:
- Simple status display using gpio leds
    - Incorporate ping status and move from fast / slow to okay / inprog / error / normal / ...
- Test support on
    - [x] Sipeed Lichee RV
    - [ ] BPI M2 zero
    - [ ] RPi Zero W
    - [ ] OPi Zero3
    - [ ] arm qemu
    - [ ] arm64 qemu
    - [ ] RISC-V qemu
- withHost should include nix
    - either provide a proper setup
    - or allow nix to be installed via script
    - check out closure-info and how nixos does it (maybe minimzie script creation)
- Stop services and proper shutdown
- root password and wpa_passphrase
- Clean up, minimize "script injection"

- Derivation to build all platforms in one go
- Create common nix for kernel / u-boot - or use nixpkgs version
- Adjust partition sizes
- Allow only changing certain parts in make.sh by flags
    - [m]ount
    - [b]ootfs
    - [B]ootloader
    - [r]ootfs (inc. home, secrets)
- Swap
- Optimize kernel size (specifically qemu)

Ideas / Notes:
- Have an eye on kernel version (nix headers / glibc v. manually compiled kernel)
- Test hw acceleration and other D1 / H3 / ... features
- OTA updates of the root fs (maybe bluetooth) + get logs
