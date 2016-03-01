#!/usr/bin/env perl
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
