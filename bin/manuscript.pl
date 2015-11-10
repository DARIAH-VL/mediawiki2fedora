#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use Catmandu::Sane;
use Catmandu::Importer::MediaWiki;
use Catmandu::Exporter::YAML;

binmode STDOUT,":utf8";

my $importer = Catmandu::Importer::MediaWiki->new(
    url => "http://localhost:8000/w/api.php",
    args => { gapfilterredir => undef }
);
my $exporter = Catmandu::Exporter::YAML->new();
$importer->each(sub{
    my $r = shift;
    $exporter->add($r);
});
$exporter->commit();
