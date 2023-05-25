#!/bin/bash

# Didn't know if we could use busybox to use echo or needed a standalone binary
# to print 'Hello world', so did both


set -e

# Installing dependencies
echo "Installing dependencies"
echo "Need sudo for dependencies"
sudo apt install qemu build-essential flex bison qemu-system-x86 libelf-dev -y


# Probably should've made variables for the kernel version and busybox versions

# Getting core number to run
CORE_NUM=$(lscpu | grep "CPU(s):" | awk '{print $2}')
CORE_NUM=$((CORE_NUM + 2))
# Create directory where everything will be compiled
mkdir -p src
cd src
echo "Generating hello world executable"
# Generate simple hello world in c and compile it statically
echo '#include <stdio.h>' > helloworld.c
echo 'int main(void) {' >> helloworld.c
echo '	printf("Hello, World! (from precompiled C program)\n");' >> helloworld.c
echo '	return 0;' >> helloworld.c
echo '}' >> helloworld.c
gcc -w -static helloworld.c -o helloworld

echo "Downloading kernel and busybox"
# Get and unpack kernel and busybox
wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.3.tar.xz
wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2

echo "Decompressing"
tar -xf linux-6.3.tar.xz
tar -xf busybox-1.36.1.tar.bz2

echo "Building kernel"
cd linux-6.3
make defconfig ARCH=x86_64
make -j$CORE_NUM ARCH=x86_64
cd ..

echo "Building busybox"

cd busybox-1.36.1
make defconfig ARCH=x86_64
# make it static
sed 's/^.*CONFIG_STATIC[^_].*$/CONFIG_STATIC=y/g' -i .config
make -j$CORE_NUM busybox ARCH=x86_64
cd ../..

echo "Copying built files"

cp src/linux-6.3/arch/x86_64/boot/bzImage ./
cp src/busybox-1.36.1/busybox ./

echo "Making initrd"
# make the initrd
mkdir -p initrd
cd initrd

mkdir -p bin dev proc sys
cd bin
cp ../../src/busybox-1.36.1/busybox ./
cp ../../src/helloworld ./

# though it would be nice to have symlinks for all of the busybox bins
for prog in $(./busybox --list); do
	ln -s /bin/busybox ./$prog
done
cd ..

# Making the init file (mounting, running helloworld)
echo '#!/bin/sh' > init
echo 'mount -t sysfs sysfs /sys' >> init
echo 'mount -t proc proc /proc' >> init
echo 'mount -t devtmpfs udev /dev' >> init
echo 'clear' >> init
echo '/bin/helloworld'>> init
echo 'echo "Hello, World! (by busybox)"' >> init
echo '/bin/sh' >> init
echo 'poweroff -f' >> init
chmod -R 777 .
# Turning initrd into an img
find . | cpio -o -H newc > ../initrd.img
cd ..

qemu-system-x86_64 -kernel bzImage -initrd initrd.img -nographic -append 'console=ttyS0'
