#!/bin/bash

#install perl modules
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
