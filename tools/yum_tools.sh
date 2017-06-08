#!/usr/bin/env bash


#Use yumdownloader. It's in the yum-utils package.
#https://access.redhat.com/solutions/10154
#To get URLs for packages:
get_rpm_url() {
    yumdownloader --urls mariadb-server
}
#To actually download a package and all its dependencies:
download_rpm() {
    yumdownloader --resolve mariadb-server
}


#--------------------------------------------------------------
#https://wiki.centos.org/zh/TipsAndTricks/YumAndRPM

install_changelog_plugin() {
    yum -y install yum-plugin-changelog
}
show_changelog() {
    yum changelog 1 openvswitch | less
}
show_rpmdoc() {
    rpm -qd openvswitch
}
show_rpmdoc2() {
    rpm -qdf /usr/share/doc/openvswitch-2.6.1/COPYING
}



#-------------------------------------
#https://fedoraproject.org/wiki/How_to_create_an_RPM_package/zh-cn#.E5.85.B3.E4.BA.8E.E6.9C.AC.E6.8C.87.E5.8D.97
#TODO 怎么知道那个软件包的config
show_configfile() {

}

#下载编译srpm包
#https://blog.packagecloud.io/eng/2015/04/20/working-with-source-rpms/
download_srpm() {
    yumdownloader --source redis
}