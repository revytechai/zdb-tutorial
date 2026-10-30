# Hands-on zdb(8): looking inside a ZFS pool

An OpenZFS Hackathon (Oct 30, 2026) tutorial. Every command below was run for
real by [`lab.sh`](lab.sh) on FreeBSD 16.0-CURRENT with OpenZFS master
`1547ff6` (`zfs-2.4.99-1.1424.g1547ff6bc`) plus the `zdb -j` patch (Track #1659).
The complete, unedited transcript is in [`lab-output.txt`](lab-output.txt)
(only the hostname is replaced with `demo-host`).

> zdb is a debugger. It reads on-disk state and never modifies a pool, but run
> the lab on a test machine: it creates and destroys a pool called `zdblab`.

```
# sh lab.sh            # uses /tmp/zdblab for two 256 MB file vdevs
```

## 1. Build a throwaway pool
```
truncate -s 256m /tmp/zdblab/d0 /tmp/zdblab/d1
zpool create zdblab mirror /tmp/zdblab/d0 /tmp/zdblab/d1
zfs create -o compression=lz4 zdblab/data
dd if=/dev/random of=/zdblab/data/rand bs=128k count=8 status=none
printf 'hello zdb\n' > /zdblab/data/hello.txt
zpool sync zdblab
```
`zpool sync` matters: zdb reads what is on disk, not what is still in memory.

**Lesson learned the hard way:** zdb finds pools through the cache file
(`/etc/zfs/zpool.cache`). Our first run created the pool with
`-o cachefile=none`, and every pool-name command failed with
`failed to find config for pool 'zdblab': no matching pools`.
For such pools use `zdb -e -p /tmp/zdblab zdblab`.

## 2. The pool configuration: `-C`
```
$ zdb -C zdblab | head -30

MOS Configuration:
        version: 5000
        name: 'zdblab'
        state: 0
        txg: 4
        pool_guid: 17906567657279078184
        errata: 0
        min_alloc: 512
        max_alloc: 512
        hostid: 2404258965
        hostname: 'demo-host'
        com.delphix:has_per_vdev_zaps
        vdev_children: 1
        vdev_tree:
            type: 'root'
            id: 0
            guid: 17906567657279078184
            create_txg: 4
            com.klarasystems:vdev_zap_root: 129
            children[0]:
                type: 'mirror'
                id: 0
                guid: 2078675642290944585
                top_guid: 2078675642290944585
                metaslab_array: 256
                metaslab_shift: 24
                ashift: 9
                asize: 263716864
                min_alloc: 512
```

The MOS copy of the config: the vdev tree (root, mirror, two file children),
guids, `ashift` and the `txg` of the last config change.

## 3. Vdev labels (`-l`) and uberblocks (`-u`)
```
$ zdb -l /tmp/zdblab/d0 | head -25
------------------------------------
LABEL 0 
------------------------------------
    version: 5000
    name: 'zdblab'
    state: 0
    txg: 4
    pool_guid: 17906567657279078184
    errata: 0
    min_alloc: 512
    max_alloc: 512
    hostid: 2404258965
    hostname: 'demo-host'
    top_guid: 2078675642290944585
    guid: 15181124548932803639
    vdev_children: 1
    vdev_tree:
        type: 'mirror'
        id: 0
        guid: 2078675642290944585
        top_guid: 2078675642290944585
        metaslab_array: 256
        metaslab_shift: 24
        ashift: 9
        asize: 263716864
```

Each vdev keeps four 256 KB labels (two at the front, two at the end), each with
a copy of the config, so the pool can be found without a cache file.
```
$ zdb -lu /tmp/zdblab/d0 | grep -m4 -E 'Uberblock|^\s+txg'
    txg: 4
    Uberblock[4]
	txg = 4
    Uberblock[5]
```

The uberblock ring: the valid uberblock with the highest `txg` is the pool's root.

## 4. Datasets and objects: `-d`, `-dd`, `-dddd`
```
$ zdb -d zdblab
Dataset mos [META], ID 0, cr_txg 4, 120K, 60 objects, rootbp DVA[0]=<0:3115e00:200> DVA[1]=<0:4015000:200> DVA[2]=<0:5015400:200> [L0 DMU objset] fletcher4 lz4 unencrypted LE contiguous unique triple size=1000L/200P birth=10L/10P fill=60 cksum=0000000c9352ca96:0000051de7723cad:00010efecd416ac7:0026034f225ca3ef
Dataset zdblab/data [ZPL], ID 515, cr_txg 8, 1.03M, 9 objects, rootbp DVA[0]=<0:e000:200> DVA[1]=<0:200d400:200> [L0 DMU objset] fletcher4 lz4 unencrypted LE contiguous unique double size=1000L/200P birth=10L/10P fill=9 cksum=00000010ea7561ac:00000620eb1214df:000129353f29df70:00272634340f01e3
Dataset zdblab [ZPL], ID 54, cr_txg 1, 24K, 8 objects, rootbp DVA[0]=<0:de00:200> DVA[1]=<0:200d200:200> [L0 DMU objset] fletcher4 lz4 unencrypted LE contiguous unique double size=1000L/200P birth=10L/10P fill=8 cksum=000000112beeed15:0000063ad175b2d0:00012e6a10957651:0027dc479511e898
Verified large_blocks feature refcount of 0 is correct
Verified large_dnode feature refcount of 0 is correct
Verified sha512 feature refcount of 0 is correct
Verified skein feature refcount of 0 is correct
Verified edonr feature refcount of 0 is correct
Verified userobj_accounting feature refcount of 2 is correct
Verified encryption feature refcount of 0 is correct
Verified project_quota feature refcount of 2 is correct
Verified redaction_bookmarks feature refcount of 0 is correct
Verified redacted_datasets feature refcount of 0 is correct
Verified bookmark_written feature refcount of 0 is correct
Verified livelist feature refcount of 0 is correct
Verified zstd_compress feature refcount of 0 is correct
Verified zilsaxattr feature refcount of 0 is correct
Verified blake3 feature refcount of 0 is correct
Verified redaction_list_spill feature refcount of 0 is correct
Verified longname feature refcount of 0 is correct
Verified large_microzap feature refcount of 0 is correct
Verified physical_rewrite feature refcount of 0 is correct
Verified device_removal feature refcount of 0 is correct
Verified indirect_refcount feature refcount of 0 is correct
```

```
$ zdb -dd zdblab/data
Dataset zdblab/data [ZPL], ID 515, cr_txg 8, 1.03M, 9 objects, rootbp DVA[0]=<0:e000:200> DVA[1]=<0:200d400:200> [L0 DMU objset] fletcher4 lz4 unencrypted LE contiguous unique double size=1000L/200P birth=10L/10P fill=9 cksum=00000010ea7561ac:00000620eb1214df:000129353f29df70:00272634340f01e3

    Object  lvl   iblk   dblk  dsize  dnsize  lsize   %full  type
         0    6   128K    16K    14K     512    80K    5.62  DMU dnode
        -1    1   128K    512      0     512    512  100.00  ZFS user/group/project used
        -2    1   128K    512      0     512    512  100.00  ZFS user/group/project used
        -3    1   128K    512      0     512    512  100.00  ZFS user/group/project used
         1    1   128K     1K     1K     512     1K  100.00  ZFS master node
         2    2   128K   128K  1.00M     512     1M  100.00  ZFS plain file
        32    1   128K    512      0     512    512  100.00  SA master node
        33    1   128K    512      0     512    512  100.00  ZFS delete queue
        34    1   128K    512      0     512    512  100.00  ZFS directory
        35    1   128K  1.50K     1K     512  1.50K  100.00  SA attr registration
        36    1   128K    16K     8K     512    32K  100.00  SA attr layouts
        37    1   128K    512      0     512    512  100.00  ZFS directory
       128    1   128K    512      0     512    512  100.00  ZFS plain file

    Dnode slots:
	Total used:             9
	Max used:             128
	Percent empty:  92.968750
```

Object 2 is the 1 MB `rand` file (lz4 cannot compress random data); 128 is
`hello.txt`. Use the inode number from `ls -i` as the object id:
```
$ obj=$(ls -i /zdblab/data/hello.txt | awk '{print $1}'); zdb -dddd zdblab/data $obj | tail -15
	dnode flags: USED_BYTES USERUSED_ACCOUNTED USEROBJUSED_ACCOUNTED 
	dnode maxblkid: 0
	uid     0
	gid     0
	atime	Fri Oct 30 21:28:07 2026
	mtime	Fri Oct 30 21:28:07 2026
	ctime	Fri Oct 30 21:28:07 2026
	crtime	Fri Oct 30 21:28:07 2026
	gen	10
	mode	100644
	size	10
	parent	34
	links	1
	pflags	840800000004
	projid	0
```


## 5. Block accounting (`-b`) and dedup simulation (`-S`)
```
$ zdb -b zdblab | head -20

loading concrete vdev 0, metaslab 0 of 15 ...
loading concrete vdev 0, metaslab 1 of 15 ...
loading concrete vdev 0, metaslab 2 of 15 ...
loading concrete vdev 0, metaslab 3 of 15 ...
loading concrete vdev 0, metaslab 4 of 15 ...
loading concrete vdev 0, metaslab 5 of 15 ...
loading concrete vdev 0, metaslab 6 of 15 ...
loading concrete vdev 0, metaslab 7 of 15 ...
loading concrete vdev 0, metaslab 8 of 15 ...
loading concrete vdev 0, metaslab 9 of 15 ...
loading concrete vdev 0, metaslab 10 of 15 ...
loading concrete vdev 0, metaslab 11 of 15 ...
loading concrete vdev 0, metaslab 12 of 15 ...
loading concrete vdev 0, metaslab 13 of 15 ...
loading concrete vdev 0, metaslab 14 of 15 ...

Traversing all blocks to verify nothing leaked ...


	No leaks (block sum matches space maps exactly)

	bp count:                   108
	ganged count:                 0
	bp logical:             4716032      avg:  43666
	bp physical:            1115648      avg:  10330     compression:   4.23
	bp allocated:           1223680      avg:  11330     compression:   3.85
	bp deduped:                   0    ref>1:      0   deduplication:   1.00
	bp cloned:                    0    count:      0
	Normal class:            118272     used:  0.05%
	Embedded log class              0     used:   nan%

	additional, non-pointer bps of type 0:         44
	Dittoed blocks on same vdev: 56
```

`No leaks` means every allocated block is referenced. `Dittoed blocks`
are the extra copies ZFS keeps of metadata.
```
$ zdb -S zdblab | tail -8
______   ______________________________   ______________________________
refcnt   blocks   LSIZE   PSIZE   DSIZE   blocks   LSIZE   PSIZE   DSIZE
------   ------   -----   -----   -----   ------   -----   -----   -----
     1        8      1M      1M      1M        8      1M      1M      1M
 Total        8      1M      1M      1M        8      1M      1M      1M

dedup = 1.00, compress = 1.00, copies = 1.00, dedup * compress / copies = 1.00
```


## 6. New: JSON output, `-j`
```
$ zdb -j -l /tmp/zdblab/d0 | jq -c .output_version
{"command":"zdb","vers_major":0,"vers_minor":1}
```

```
$ zdb -j -C zdblab | jq -c '.mos_config | {name, txg, vdev_children}'
{"name":"zdblab","txg":4,"vdev_children":1}
```

`-j` works with `-l` (with `-u`, `-q`) and `-C`, in the same style as
`zpool status -j`, so scripts can use `jq` instead of scraping text.

## Licence
Prose: [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) (see LICENSE-CC-BY-4.0).
`lab.sh`: BSD-2-Clause (see LICENSE). Copyright (c) 2026 REVYTECH, Inc.
