#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(:all);

my $namespace = Catmandu->config->{namespace} // "mediawiki";
my $fedora = fedora();
my $query = "pid~${namespace}:*";

my $token;
while(1){

    my $objects = [];

    if($token){

        my $r = fedora()->resumeFindObjects(sessionToken => $token);
        my $obj = $r->is_ok ? $r->parse_content : {};
        $objects = $obj->{results} // [];
        $token = $obj->{token};

    }
    else{

        my $r = fedora()->findObjects( query => $query, maxResults => 80 );
        my $obj = $r->is_ok ? $r->parse_content : {};
        $objects = $obj->{results} // [];
        $token = $obj->{token};

    }


    say $_->{pid} foreach @$objects;

    last unless is_string $token;

}
