#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use Catmandu::Sane;
use Catmandu::Importer::MediaWiki;
use Try::Tiny;

binmode STDOUT,":utf8";

my $importer = Catmandu::Importer::MediaWiki->new(
    url => "http://localhost:8000/w/api.php",
    lgname => "admin",
    lgpassword => "root",
    args => { gapfilterredir => undef }
);
$importer->each(sub{
    my $r = shift;
    say $r->{pageid};
});
