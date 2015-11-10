#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use Catmandu::Sane;
use Catmandu::Importer::MediaWiki;
use Data::Dumper;

binmode STDOUT,":utf8";

my $importer = Catmandu::Importer::MediaWiki->new(
    url => "http://en.wikipedia.org/w/api.php",
    generate => "allusers",
    args => {
        gaulimit => 100
    }
);
$importer->each(sub{
    print Dumper(shift);
});
