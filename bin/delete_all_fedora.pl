#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu::Store::FedoraCommons;

binmode STDOUT,":utf8";
my $bag_name = shift;

my $store = Catmandu::Store::FedoraCommons->new(
    baseurl => "http://localhost:8080/fedora",
    username => "fedoraAdmin",
    password => "1q0p2w0p3e0p",
    model    => 'Catmandu::Store::FedoraCommons::DC'
);
$store->bag($bag_name)->delete_all();
