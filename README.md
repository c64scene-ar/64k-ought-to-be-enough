# 64k ought to be enough
A demo for the IBM PCjr


## Compile et al.

Pre-requisites:

* Install [nasm](https://www.nasm.us/)
* Install [lz4](https://www.dropbox.com/sh/mwa5geyxgl9m24k/AACtCCyO5W1_3-1bI8YxPHLca)
* Install [Alinker](https://gitlab.com/ricardoquesada/alink)
* Optional Install [DosBox-x](http://dosbox-x.com/)

```
# compile the resources
make res

# make the disk image
make disk_image

# test the disk image
make boot

# test the disk
make test_boot

# from dosbox-x console run:
c:> boot -l a
```


