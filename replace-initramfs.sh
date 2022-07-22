#!/bin/bash -exu

replace_snapd_binaries() {
    KERNEL_EFI_ORIG=cache/snap-pc-kernel/kernel.efi
    if [ ! -d initrd ]; then
        objcopy -O binary -j .initrd "$KERNEL_EFI_ORIG" initrd.img
        unmkinitramfs initrd.img initrd
        SYSTEMD_D=initrd/main/usr/lib/systemd/system

        # Mounts in /sysroot/ created by snap-bootstrap now
        rm "$SYSTEMD_D"/sysroot-writable.mount \
           "$SYSTEMD_D"/initrd-fs.target.wants/sysroot-writable.mount
        rm "$SYSTEMD_D"/sysroot.mount \
           "$SYSTEMD_D"/initrd-root-fs.target.wants/sysroot.mount
        # do not call handle-writable-paths or the-modeenv.
        # Change in the service would be:
        # [Install]
        # WantedBy=initrd-root-device.target
        # WantedBy=basic.target
        # and then we would enable from snap-bootstrap in the UC case
        rm "$SYSTEMD_D"/initrd-root-device.target.wants/populate-writable.service \
           "$SYSTEMD_D"/basic.target.wants/populate-writable.service

    fi

    uc_initramfs_deb=ubuntu-core-initramfs_55_amd64.deb
    if [ ! -f "$uc_initramfs_deb" ]; then
        wget -q https://launchpad.net/~snappy-dev/+archive/ubuntu/image/+files/"$uc_initramfs_deb"
        dpkg --fsys-tarfile "$uc_initramfs_deb" |
            tar xf - ./usr/lib/ubuntu-core-initramfs/efi/linuxx64.efi.stub
    fi

    BINPATH=~/go/src/github.com/snapcore/snapd
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

    sleep 1
    sudo umount "$MNT"/* || true
    sleep 1
    sudo kpartx -d "$IMG" || true
}

main() {
    MNT=mnt-replace
    IMG=boot.img
    mkdir -p "$MNT"/ubuntu-boot

    replace_snapd_binaries

    # shellcheck disable=SC2064
    trap "cleanup ./$IMG ./$MNT" EXIT

    sudo kpartx -av "$IMG"
    loop=$(sudo kpartx -l "$IMG" |tr -d " " | cut -f1 -d:|sed 's/..$//'|head -1)
    loop_boot="${loop}"p3
    sudo mount /dev/mapper/"$loop_boot" "$MNT"/ubuntu-boot

    # XXX
    subpath=$(readlink "$MNT"/ubuntu-boot/EFI/ubuntu/kernel.efi)
    cp -a kernel.efi "$MNT"/ubuntu-boot/EFI/ubuntu/"$subpath"
}

main
