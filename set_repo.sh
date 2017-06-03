#!/usr/bin/env bash

source lib/devstack/common_function.sh


#set screenshot
if is_ubuntu ; then
    sudo add-apt-repository ppa:dhor/myway
    sudo apt-get update
    sudo apt-get install hotshots﻿​
fi

if is_fedora; then
    #更具不同的版本来选择
    sudo wget http://download.opensuse.org/repositories/home:/zhonghuaren/Fedora_${os_RELEASE}/home:zhonghuaren.repo -O /etc/yum.repo.d/
    sudo yum install hotshots
fi
