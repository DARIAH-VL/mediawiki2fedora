#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(:all);
use File::Basename;
use File::Spec;


my $data_dir = File::Spec->rel2abs( File::Spec->catdir( dirname(__FILE__), "..", "data" ) );
my @models = qw(pageCModel);

my $namespace = Catmandu->config->{namespace} // "mediawiki";
my $fedora = fedora();

for my $model( @models ){

    my $pid = "${namespace}:$model";
    my $xml_file = File::Spec->catfile($data_dir,"${model}.xml");
    my $object_profile;
    {
        my $res = $fedora->getObjectProfile(pid => $pid);
        if( $res->is_ok ) {
            $object_profile = $res->parse_content();
        }
    }
    unless($object_profile){
        say "object $pid: ingest";
        my $res = $fedora->ingest( pid => $pid , file => $xml_file , format => 'info:fedora/fedora-system:FOXML-1.1' );
        die($res->raw()) unless $res->is_ok();
    }
}
