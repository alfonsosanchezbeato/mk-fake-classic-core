#!/bin/bash -exu

BINPATH=~/go/src/github.com/snapcore/snapd

replace_initramfs_bits() {
    KERNEL_EFI_ORIG=cache/snap-pc-kernel/kernel.efi
    if [ ! -d initrd ]; then
        objcopy -O binary -j .initrd "$KERNEL_EFI_ORIG" initrd.img
        unmkinitramfs initrd.img initrd
        SYSTEMD_D=initrd/main/usr/lib/systemd/system

        # Copy files from https://github.com/snapcore/core-initrd/pull/106
        cp replace-files/* "$SYSTEMD_D"/
    fi

    uc_initramfs_deb=ubuntu-core-initramfs_55_amd64.deb
    if [ ! -f "$uc_initramfs_deb" ]; then
        wget -q https://launchpad.net/~snappy-dev/+archive/ubuntu/image/+files/"$uc_initramfs_deb"
        dpkg --fsys-tarfile "$uc_initramfs_deb" |
            tar xf - ./usr/lib/ubuntu-core-initramfs/efi/linuxx64.efi.stub
    fi

    cp "$BINPATH"/snap-bootstrap initrd/main/usr/lib/snapd/
    cd initrd/main
    find . | cpio --create --quiet --format=newc --owner=0:0 | lz4 -l -7 > ../../initrd.img.new
    cd -

    objcopy -O binary -j .linux "$KERNEL_EFI_ORIG" linux
    objcopy --add-section .linux=linux --change-section-vma .linux=0x2000000 \
            --add-section .initrd=initrd.img.new --change-section-vma .initrd=0x3000000 \
            usr/lib/ubuntu-core-initramfs/efi/linuxx64.efi.stub \
            kernel.efi
}

cleanup() {
    IMG="$(readlink -f "$1")"
    MNT="$(readlink -f "$2")"

    sync
    sleep 1
    sudo umount "$MNT"/* || true
    sleep 1
    sudo kpartx -d "$IMG" || true
}

main() {
    MNT=mnt-replace
    IMG=boot.img
    mkdir -p "$MNT"/ubuntu-boot "$MNT"/data

    replace_initramfs_bits

    # shellcheck disable=SC2064
    trap "cleanup ./$IMG ./$MNT" EXIT

    sudo kpartx -av "$IMG"
    loop=$(sudo kpartx -l "$IMG" |tr -d " " | cut -f1 -d:|sed 's/..$//'|head -1)
    loop_boot="$loop"p3
    sudo mount /dev/mapper/"$loop_boot" "$MNT"/ubuntu-boot

    subpath=$(readlink "$MNT"/ubuntu-boot/EFI/ubuntu/kernel.efi)
    cp -a kernel.efi "$MNT"/ubuntu-boot/EFI/ubuntu/"$subpath"

    # replace snapd in data partition
    data_mnt="$loop"p5
    sudo mount /dev/mapper/"$data_mnt" "$MNT"/data
    sudo cp "$BINPATH"/snapd "$MNT"/data/usr/lib/snapd/
    sudo sed 's/#Nice=-5/Environment=SNAPD_DEBUG=1/' \
         "$MNT"/data/usr/lib/systemd/system/snapd.service
    # XXX service file seems to be restored, use brute force for the moment
    printf 'SNAPD_DEBUG=1\n' | sudo tee -a "$MNT"/data/etc/environment
}

main
