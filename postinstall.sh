#!/bin/bash

#install perl modules
export PATH="/opt/perl-5.22.0-x86_64-linux-thread-multi/bin:${PATH}"
carton="carton"
cpanm="cpanm"

cpanm Carton
carton install

#restart cronjob
touch -h /etc/cron.d/mediawiki2fedora
