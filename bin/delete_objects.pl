#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(:all);

my $fedora = fedora();

while( my $pid = <STDIN> ){
    chomp $pid;
    my $res = $fedora->purgeObject(pid => $pid, logMessage => "object $pid removed from fedora");
    if ( $res->is_ok ) {
        Catmandu->log->info("object $pid removed from fedora");
    }else{
        Catmandu->log->error("object $pid could not be removed from fedora: ".$res->raw);
    }
}
