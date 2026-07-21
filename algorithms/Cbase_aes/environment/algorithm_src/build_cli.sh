#!/bin/bash

cd "$(dirname "$0")"
gcc -O3 -o cli *.c
