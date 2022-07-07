#!/bin/bash
releases=$(ls -A ./)

declare -a darwin_builds
declare -a linux_builds

for release in $releases; do
    oss=$(ls -A ./$release)
    for os in $oss; do
        cpus=$(ls -A ./$release/$os)
        for cpu in $cpus; do
            if [ "$os" = "linux" ]; then
                abis=$(ls -A ./$release/$os/$cpu)
                for abi in $abis; do
                    linux_builds+=("./$release/$os/$cpu/$abi")
                done
            else
                darwin_builds+=("./$release/$os/$cpu")
            fi
        done
    done
done

echo "Darwin Builds:" ${#darwin_builds[@]}
echo "Linux Builds:" ${#linux_builds[@]}

for build_path in $linux_builds do
    if test -f "$build_path/BUILD_OK"; then
        echo "$build_path OK [Already Built]"
    else
        orig_path=$(pwd)
        cd $build_path
        do-build-in-dir-linux.sh > /dev/null 2>&1
        status=$?
        [ $status -eq 0 ] && echo "$build_dir OK" || echo "$build_dir FAILED [Status: $status]"
        cd $orig_path
    fi
done