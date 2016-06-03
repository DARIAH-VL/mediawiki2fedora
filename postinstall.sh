#!/bin/bash

#install perl modules
export PATH="/opt/perl-5.22.0-x86_64-linux-thread-multi/bin:${PATH}"

cpanm Carton
carton install

#restart cronjob
touch -h /etc/cron.d/mediawiki2fedora
