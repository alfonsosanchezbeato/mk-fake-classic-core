#!/bin/bash -exu

kvm -m 1500 \
    -snapshot \
    -netdev user,id=net.0,hostfwd=tcp::8022-:22 \
    -device rtl8139,netdev=net.0 \
    -bios /usr/share/OVMF/OVMF_CODE.fd \
    -drive file="$1",if=virtio \
    -serial stdio
