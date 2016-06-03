#!/bin/bash

#install perl modules
export PATH="/opt/perl-5.22.0-x86_64-linux-thread-multi/bin:${PATH}"

cpanm Carton
carton install

#restart cronjob
c="/etc/cron.d/mediawiki2fedora"
if [ -L "$c" ];then
    touch -h $c
elif [ -f "$c" ];then
    touch $c
else
    echo "cronjob $c is neither a file nor symlink"
fi
