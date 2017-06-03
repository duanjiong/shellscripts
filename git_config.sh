#!/usr/bin/env bash

#pycharm git submodule support
#https://intellij-support.jetbrains.com/hc/en-us/community/posts/207069875-Git-submodule-support-
#https://youtrack.jetbrains.com/issue/IDEA-64024

git config fetch.recurseSubmodules yes
git config --global core.editor vi

#https://git-scm.com/book/zh/v1/%E8%B5%B7%E6%AD%A5-%E5%88%9D%E6%AC%A1%E8%BF%90%E8%A1%8C-Git-%E5%89%8D%E7%9A%84%E9%85%8D%E7%BD%AE
echo global?
read scope

if [ $scope = "global" ];then
    git config --global user.name "Duan Jiong"
    git config --global user.email 380657134@qq.com
elif
    git config  user.name "Duan Jiong"
    git config  user.email 380657134@qq.com
fi