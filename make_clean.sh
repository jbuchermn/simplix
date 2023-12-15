#!/bin/sh
# Clean deps
for i in deps/*; do pushd $i && make clean && popd; done

# Clean and setup dirs
rm -rf output
mkdir -p output/initfs
mkdir -p output/bootfs
mkdir -p output/rootfs
