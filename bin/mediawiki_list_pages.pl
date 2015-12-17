#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is);
use Catmandu::Exporter::YAML;

my $exporter = Catmandu::Exporter::YAML->new();
Catmandu->importer('mediawiki')->each(sub{
    my $r = shift;

    $exporter->add($r);

});

$exporter->commit();
