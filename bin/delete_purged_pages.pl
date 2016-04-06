#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(:all);

my $namespace = Catmandu->config->{namespace} // "mediawiki";
my $fedora = fedora();
my $query = "pid~${namespace}:*";
my $importer = Catmandu->importer('mediawiki');
my $mw = $importer->_build_mw();

if(is_string($importer->lgname) && is_string($importer->lgpassword)){
    $mw->login({ lgname => $importer->lgname, lgpassword => $importer->lgpassword }) or die($mw->{error}->{details});
}

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

        my $r = fedora()->findObjects( query => $query, maxResults => 50 );
        my $obj = $r->is_ok ? $r->parse_content : {};
        $objects = $obj->{results} // [];
        $token = $obj->{token};

    }

    my $pageids = [];


    for my $object(@$objects){
        my $pid = $object->{pid};
        my($ns,$pageid) = split ':',$pid;
        push @$pageids,$pageid;
    }

    {
        my $r = $mw->api({ action => "query", "pageids" => join('|',@$pageids), format => "json" }) or die($mw->{error}->{details});

        for my $pageid(sort keys %{ $r->{'query'}->{'pages'} }){

            if(exists( $r->{'query'}->{'pages'}->{$pageid}->{missing})){
                Catmandu->log->warn("page $pageid is removed from mediawiki");
                fedora()->modifyObject(pid => "${namespace}:${pageid}", state => "D", logMessage => "page $pageid deleted from mediawiki");
            }
            else{
                Catmandu->log->debug("page $pageid exists in mediawiki");
            }

        }

    }

    last unless is_string $token;

}
