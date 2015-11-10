#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use Catmandu::Sane;
use Catmandu::Importer::MediaWiki;

binmode STDOUT,":utf8";

my $importer = Catmandu::Importer::MediaWiki->new( url => "http://en.wikipedia.org/w/api.php");
$importer->each(sub{
    my $r = shift;
    say $r->{title};
});
