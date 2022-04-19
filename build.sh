#!/bin/bash

mkdir -p build
rm -f build/*

for i in 82 A0 D0 E0 F0
do
    beebasm -D test_start=\&${i}00 -v -i src/RAMTest.asm -o build/RAMTST${i} > build/RAMTST${i}.log
    dd if=build/RAMTST${i} of=build/RAMTST${i}.rom bs=1 skip=22
done

ls -l build

cd build
zip -qr ../ram_test.zip *
cd ..
