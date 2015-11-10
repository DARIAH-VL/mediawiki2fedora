#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu::Store::FedoraCommons;
use Data::Dumper;

binmode STDOUT,":utf8";

my $store = Catmandu::Store::FedoraCommons->new(
    baseurl => "http://localhost:8080/fedora",
    username => "fedoraAdmin",
    password => "1q0p2w0p3e0p",
    model    => 'Catmandu::Store::FedoraCommons::DC'
);

print Dumper(
    $store->bag('demo')->delete('mediawiki:2')
);
print Dumper(
    $store->bag('mediawiki')->delete('demo:1')
);
