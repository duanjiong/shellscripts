#!/usr/bin/env bash

cd /tmp

wget https://releases.hashicorp.com/vagrant/1.9.5/vagrant_1.9.5_x86_64.rpm
rpm -i /tmp/vagrant_1.9.5_x86_64.rpm

yum -y install libvirt-devel
vagrant plugin install vagrant-libvirt
vagrant plugin install vagrant-proxyconf
vagrant plugin install vagrant-cachier

vagrant box add centos/7