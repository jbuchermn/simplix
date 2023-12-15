export CROSS_TARGET=riscv64-unknown-linux-musl
export CROSS_COMPILE=${CROSS_TARGET}-
export PATH=$(pwd)/tools/cross-toolchain/${CROSS_TARGET}/bin:$PATH
