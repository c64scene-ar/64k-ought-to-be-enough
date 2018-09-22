# 64k RAM ought to be enough

A demo for the IBM PCjr by [Pungas de Villa Martelli](http://pungas.space)


## Requirements

An IBM PCjr with at least 64k RAM.


## Compile et al.

Prerequisites:

* Install [nasm](https://www.nasm.us/)
* Install [lz4](https://www.dropbox.com/sh/mwa5geyxgl9m24k/AACtCCyO5W1_3-1bI8YxPHLca)
* Install [Alinker](https://gitlab.com/ricardoquesada/alink)
* Optional Install [DosBox-x](http://dosbox-x.com/)

```
# compile the resources
make res

# test the disk image
make boot

# test the disk
make test_boot

# from dosbox-x console run:
c:> boot -l a
```

