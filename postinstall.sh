#!/bin/bash

#install perl modules
export PATH="/opt/perl-5.22.0-x86_64-linux-thread-multi/bin:${PATH}"
carton="/usr/local/bin/carton"
cpanm="/usr/local/bin/cpanm"

if [ -f $carton ];then
    $carton install
else
    $cpanm Carton
    $carton install
fi

#restart cronjob
touch -h /etc/cron.d/mediawiki2fedora
