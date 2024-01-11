Simplix - hacky and simple linux distro for embedded using Nix
==============================================

Status:
- Basic system with WiFi and SSH on ARM / RISC-V

Next steps:
- Derivation to build all platforms in one go + test current status
- withHost should include nix (either provide a proper setup, or allow nix to be installed via script)
- root password and wpa_passphrase
- Clean up, minimize "script injection"

- Simple status display using gpio leds
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
