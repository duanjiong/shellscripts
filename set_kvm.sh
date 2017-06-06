#!/usr/bin/env bash

set_kvm_nested(){
    cat /sys/module/kvm_intel/parameters/nested
    rmmod kvm-intel
    echo 'options kvm-intel nested=y' >> /etc/modprobe.d/dist.conf
    modprobe kvm-intel
}