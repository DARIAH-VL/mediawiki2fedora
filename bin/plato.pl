#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use Catmandu::Sane;
use Catmandu::Importer::MediaWiki;

binmode STDOUT,":utf8";

my $importer = Catmandu::Importer::MediaWiki->new(
    url => "http://en.wikipedia.org/w/api.php",
    generate => "allpages",
    args => {
        prop => "revisions",
        rvprop => "ids|flags|timestamp",
        gaplimit => 100,
        gapprefix => "plato",
        gapfilterredir => "nonredirects"
    }
);
$importer->each(sub{
    my $r = shift;
    my $content = $r->{revisions}->[0]->{"*"};
    say $r->{title};
});
