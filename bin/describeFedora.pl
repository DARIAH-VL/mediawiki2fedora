#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu::FedoraCommons;
use JSON;
use Data::Dumper;

binmode STDOUT,":utf8";

my $fedora = Catmandu::FedoraCommons->new(
    "http://localhost:8080/fedora",
    "fedoraAdmin",
    "1q0p2w0p3e0p"
);
my $res = $fedora->describeRepository();
print JSON->new->utf8(1)->pretty(1)->encode( $res->parse_content() );
