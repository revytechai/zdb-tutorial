#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# zdb(8) hands-on lab: builds a throwaway file-backed pool and walks zdb
# through labels, config, datasets, objects, blocks and JSON output.
# Run as root on a test machine only.  Usage: sh lab.sh [workdir]
set -eu
W=${1:-/tmp/zdblab}; P=zdblab
run() { printf '\n$ %s\n' "$*"; sh -c "$*" 2>&1 || true; }
zpool destroy $P 2>/dev/null || true; rm -rf "$W"; mkdir -p "$W"
run "truncate -s 256m $W/d0 $W/d1"
run "zpool create $P mirror $W/d0 $W/d1"
run "zfs create -o compression=lz4 $P/data"
run "dd if=/dev/random of=/$P/data/rand bs=128k count=8 status=none"
run "printf 'hello zdb\n' > /$P/data/hello.txt"
run "zpool sync $P"
run "zdb -C $P | head -30"
run "zdb -l $W/d0 | head -25"
run "zdb -lu $W/d0 | grep -m4 -E 'Uberblock|^\s+txg'"
run "zdb -d $P"
run "zdb -dd $P/data"
run "obj=\$(ls -i /$P/data/hello.txt | awk '{print \$1}'); zdb -dddd $P/data \$obj | tail -15"
run "zdb -b $P | head -20"
run "zdb -S $P | tail -8"
run "zdb -j -l $W/d0 | jq -c .output_version"
run "zdb -j -C $P | jq -c '.mos_config | {name, txg, vdev_children}'"
run "zpool destroy $P"
