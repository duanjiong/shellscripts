#!/bin/bash -x

read project
dest_dir=""

git clone http://git.trystack.cn/${project}.git -o $dest_dir


