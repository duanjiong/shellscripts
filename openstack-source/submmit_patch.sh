#!/bin/bash -x

read project
password="123456"

git remote add upstream-gerrit https://duanjiong:${password}@review.openstack.org/openstack/${project}.git
git commit -a -F /home/duanjiong/openstack/message.txt
git review -r upstream-gerrit