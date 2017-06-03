#!/usr/bin/env bash

source lib/devstack/common_function.sh
source env.sh

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

#install natapp
NATAPP_INSTALL_DIR=/usr/local/natapp
if [ ! -d "$NATAPP_INSTALL_DIR" ];then
    mkdir -p $NATAPP_INSTALL_DIR
    wget http://download.natapp.cn/assets/downloads/clients/2_3_4/natapp_linux_amd64_2_3_4.zip -o $NATAPP_INSTALL_DIR/natapp
    chmod a+x ${NATAPP_INSTALL_DIR}/natapp
    wget http://download.natapp.cn/assets/downloads/config.ini -o $NATAPP_INSTALL_DIR/config.ini
    cp ./conf/service/natapp/natapp /etc/init.d/
    chmod 755 /etc/init.d/natapp
    /etc/init.d/natapp enable && echo on
    /etc/init.d/natapp start
fi
