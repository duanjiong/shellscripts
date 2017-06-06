#!/usr/bin/env bash

query_kvm(){
    egrep '(vmx|svm)' /proc/cpuinfo
}

query_iommu(){
    dmesg | grep -e DMAR -e IOMMU
    cat /proc/cmdline | grep iommu=pt
    cat /proc/cmdline | grep intel_iommu=on
}
