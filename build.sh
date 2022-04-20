#!/bin/bash

mkdir -p build
rm -f build/*

for i in 82 A0 D0 E0 F0
do
    beebasm -D test_start=\&${i}00 -v -i src/RAMTest.asm -o build/RAMTST${i} > build/RAMTST${i}.log
    tail -c +23 <build/RAMTST${i} >build/RAMTST${i}.rom
    grep -i "Free Space" build/RAMTST${i}.log
    md5sum build/RAMTST${i}.rom
done

# Build a special; test version that runs in CLEAR 4
beebasm -D test_start=\&2900 -D screen_base=\&4000 -D screen_init=\&F0 -D page_start=\&80 -D page_end=\&97 -v -i src/RAMTest.asm -o build/RAMTST29 > build/RAMTST29.log
tail -c +23 <build/RAMTST29 >build/RAMTST29.rom

ls -l build

cd build
zip -qr ../ram_test.zip *
cd ..
