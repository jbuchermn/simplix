#!/bin/sh
gcc $SIMPLIX_C_FLAGS -c main.c -o main.o
gcc $SIMPLIX_LD_FLAGS -lgpiod -o main main.o
