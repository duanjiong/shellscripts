#!/usr/bin/env bash


#for ubuntu
apt-get -y install privoxy
pip install shadowsocks

read password
read ip
sslocal -s $ip -p 8989 -b 127.0.0.1 -l 1082 -k $password -m aes-256-cfb -d start


apt-get -y install squid