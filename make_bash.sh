#!/bin/sh
pushd deps/bash
export CC=${CROSS_COMPILE}gcc
make clean
./configure --host=${CROSS_TARGET} --without-bash-malloc
make
popd
