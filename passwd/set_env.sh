#!/usr/bin/env bash

source ../lib/devstack/common_function.sh

#install keepassx
if is_ubuntu ; then
    sudo apt-get install keepassx
fi