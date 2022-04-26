#!/bin/bash

mkdir -p build
rm -f build/*

bulk_build_names=(
    ROM060
    ROM066
    ROM068
    ROM160
    ROM166
    ROM168
    ROM320
)

individual_build_names=(
    ROM326
    ROM328
    RAM060
    RAM160
    RAM320
    RAM006
    RAM008
    RAM246
    RAM248
    RAMCL4
)


declare -A params

# Bulk builds (ROM, assemled to A0 C0 D0 E0 F0)

params[ROM060]="-D page_start1=&00 -D page_end1=&03 -D page_start2=&28 -D page_end2=&3B"
params[ROM066]="-D page_start1=&00 -D page_end1=&03 -D page_start2=&28 -D page_end2=&3B -D page_start3=&82 -D page_end3=&97"
params[ROM068]="-D page_start1=&00 -D page_end1=&03 -D page_start2=&28 -D page_end2=&3B -D page_start3=&82 -D page_end3=&9F"
params[ROM160]="-D page_start1=&00 -D page_end1=&3F"
params[ROM166]="-D page_start1=&00 -D page_end1=&3F -D page_start2=&82 -D page_end2=&97"
params[ROM168]="-D page_start1=&00 -D page_end1=&3F -D page_start2=&82 -D page_end2=&9F"
params[ROM320]="-D page_start1=&00 -D page_end1=&7F"

# Individual builds

params[ROM326]="-D exec_page=&E0 -D page_start1=&00 -D page_end1=&7F -D page_start2=&82 -D page_end2=&97 -D rom_size=&2000"
params[ROM328]="-D exec_page=&E0 -D page_start1=&00 -D page_end1=&7F -D page_start2=&82 -D page_end2=&9F -D rom_size=&2000"
params[RAM060]="-D exec_page=&82 -D page_start1=&00 -D page_end1=&03 -D page_start2=&28 -D page_end2=&3B"
params[RAM160]="-D exec_page=&82 -D page_start1=&00 -D page_end1=&3F"
params[RAM320]="-D exec_page=&82 -D page_start1=&00 -D page_end1=&7F"
params[RAM006]="-D exec_page=&29 -D page_start1=&82 -D page_end1=&97"
params[RAM008]="-D exec_page=&29 -D page_start1=&82 -D page_end1=&9F"
params[RAM246]="-D exec_page=&70 -D page_start1=&00 -D page_end1=&5F -D page_start2=&82 -D page_end2=&97"
params[RAM248]="-D exec_page=&70 -D page_start1=&00 -D page_end1=&5F -D page_start2=&82 -D page_end2=&9F"
params[RAMCL4]="-D exec_page=&29 -D page_start1=&80 -D page_end1=&97 -D screen_base=&3A00 -D screen_init=&F0"

for build in "${bulk_build_names[@]}"
do
    for exec in A0 C0 D0 E0 F0
    do
        name=${build}${exec}
        echo $name
        CMD="beebasm ${params[${build}]} -D exec_page=&${exec} -v -i src/RAMTest.asm -o build/${name}"
        $CMD > build/${name}.log
        tail -c +23 <build/${name} >build/${name}.rom
        grep -i "Free Space" build/${name}.log
        md5sum build/${name}.rom
    done
done

for build in "${individual_build_names[@]}"
do
    name=${build}
    echo $name
    CMD="beebasm ${params[${build}]} -v -i src/RAMTest.asm -o build/${name}"
    $CMD > build/${name}.log
    tail -c +23 <build/${name} >build/${name}.rom
    grep -i "Free Space" build/${name}.log
    md5sum build/${name}.rom
done

ls -l build

cd build
zip -qr ../ram_test.zip *
cd ..
