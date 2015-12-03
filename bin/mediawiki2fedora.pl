#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(:all);
use File::Temp qw(tempfile);
use Getopt::Long;
use RDF::Trine;
use RDF::Trine::Node::Resource;
use RDF::Trine::Node::Literal;
use RDF::Trine::Serializer;

my $force = 0;

GetOptions(
    "force" => \$force
);

my $namespace = Catmandu->config->{namespace} // "mediawiki";
my $ownerId = Catmandu->config->{ownerId} // "mediawiki";
my $fedora = fedora();
my $rdf_serializer = RDF::Trine::Serializer->new('rdfxml',namespaces => {
    dc => "http://purl.org/dc/elements/1.1/"
});

Catmandu->importer('mediawiki')->each(sub{
    my $r = shift;
    my $pid = "${namespace}:".$r->{pageid};
    my $object_profile;
    {
        my $res = $fedora->getObjectProfile(pid => $pid);
        if( $res->is_ok ) {
            $object_profile = $res->parse_content();
        }
    }
    #1. new object with empty datastream DC
    if(!defined($object_profile)){
        say "object $pid: ingest";
        my $foxml = generate_foxml({ label => $r->{title}, ownerId => ${ownerId} });

        my $res = $fedora->ingest( pid => $pid , xml => $foxml , format => 'info:fedora/fedora-system:FOXML-1.1' );
        die($res->raw()) unless $res->is_ok();
    }
    #2. update datastream DC
    {
        my $res = $fedora->getDatastream(pid => $pid, dsID => "DC");
        if( !$res->is_ok() || $force ) {
            say "object $pid: modify datastream DC";
            my $ds_dc = { _id => $pid, title => [$r->{title}], identifier => [$r->{pageid}] };
            dc->update($ds_dc);
        }
    }
    #3. add revisions as separate datastreams
    for my $revision(@{ $r->{revisions} }) {

        #add source from mediawiki (reference)
        {
            my $dsID = "REV.".$revision->{revid}.".SRC";
            my $datastream;
            {
                my $res = $fedora->getDatastream(pid => $pid, dsID => $dsID);
                if ( $res->is_ok() ) {
                    $datastream = $res->parse_content();
                }

            }

            my($fh,$file);
            my %args;

            if ( !$datastream || $force ) {

                #write content to tempfile
                ($fh,$file) = tempfile(UNLINK => 1,EXLOCK => 0);
                binmode $fh,":raw";
                print $fh json->encode($revision);
                close $fh;

                %args = (
                    pid => $pid,
                    dsID => $dsID,
                    file => $file,
                    versionable => "false",
                    dsLabel => "source for REV.".$revision->{revid},
                    mimeType => "application/json; charset=utf-8"
                );
            }

            if( $datastream ) {
                if ( $force ) {
                    say "object $pid: modify datastream $dsID";
                    my $res = $fedora->modifyDatastream(%args);
                    die($res->raw()) unless $res->is_ok();
                }
            }
            else{
                say "adding datastream $dsID to object $pid";

                my $res = $fedora->addDatastream(%args);
                die($res->raw()) unless $res->is_ok();

            }

            unlink $file if is_string($file) && -f $file;

        }

        #add text separately
        {

            my $dsID = "REV.".$revision->{revid};
            my $datastream;
            {
                my $res = $fedora->getDatastream(pid => $pid, dsID => $dsID);
                if ( $res->is_ok() ) {
                    $datastream = $res->parse_content();
                }
            }

            my($fh,$file);
            my %args;
            if ( !$datastream || $force ) {
                #write content to tempfile
                ($fh,$file) = tempfile(UNLINK => 1,EXLOCK => 0);
                binmode $fh,":utf8";
                print $fh $revision->{'*'};
                close $fh;

                #dsLabel has a maximum of 255 characters
                my $dsLabel = substr($revision->{parsedcomment} // "",0,255);
                utf8::encode($dsLabel);

                %args = (
                    pid => $pid,
                    dsID => $dsID,
                    file => $file,
                    versionable => "false",
                    dsLabel => $dsLabel,
                    mimeType => $revision->{contentformat}."; charset=utf-8",
                    checksumType => "SHA-1",
                    checksum => $revision->{sha1}
                );
            }

            if( $datastream ) {
                if ( $force ) {
                    say "object $pid: modify datastream $dsID";
                    my $res = $fedora->modifyDatastream(%args);
                    die($res->raw()) unless $res->is_ok();
                }
            }
            else{
                say "adding datastream $dsID to object $pid";

                my $res = $fedora->addDatastream(%args);
                die($res->raw()) unless $res->is_ok();

            }

            unlink $file if is_string($file) && -f $file;
        }
    }
    #4. update RELS-INT
    {
        my $dc_ns = "http://purl.org/dc/elements/1.1/";
        my $rdf_xml;
        my $rdf = RDF::Trine::Model->temporary_model;
        my $res = $fedora->getDatastreamDissemination( pid => $pid, dsID => "RELS-INT" );
        my $is_new = 1;
        if( $res->is_ok ){

            say "object $pid: RELS-INT found";
            $is_new = 0;

            $rdf_xml = $res->raw();
            my $parser = RDF::Trine::Parser->new('rdfxml');
            $parser->parse_into_model(undef,$rdf_xml,$rdf);

        }else{

            say "object $pid: RELS-INT not found";

        }

        my $num_changes = 0;

        for my $revision(@{ $r->{revisions} }){
            my $subject = "info:fedora/${pid}/REV.".$revision->{revid};

            my @relations;
            push @relations,{ relation => [ $subject, "${dc_ns}creator", $revision->{user} ], isLiteral => "true" };

            push @relations,{ relation => [ $subject, "${dc_ns}date", $revision->{timestamp} ], isLiteral => "true" };
            if( is_natural($revision->{parentid}) && $revision->{parentid} > 0 ) {

                push @relations,{ relation => [ $subject, "${dc_ns}relation.isBasedOn", "info:fedora/${pid}/REV.".$revision->{parentid} ], isLiteral => "false" };

            }

            for my $relation(@relations){

                my $rel = $relation->{relation};
                my $subject_n =  RDF::Trine::Node::Resource->new($rel->[0]);
                my $predicate_n = RDF::Trine::Node::Resource->new($rel->[1]);
                my $object_n = RDF::Trine::Node::Literal->new($rel->[2]);

                my $count = $rdf->count_statements($subject_n,$predicate_n,$object_n);

                if($count < 1){
                    $num_changes++;
                    say "object $pid: add relationship ( ".join(' - ',@{ $relation->{relation} })." )";
                    $rdf->add_statement( RDF::Trine::Statement->new( $subject_n, $predicate_n, $object_n ) );
                }

            }

        }
        if($num_changes > 0){
            my $rdf_data = $rdf_serializer->serialize_model_to_string( $rdf );

            #write content to tempfile
            my($fh,$file) = tempfile(UNLINK => 1,EXLOCK => 0);
            binmode $fh,":utf8";
            print $fh $rdf_data;
            close $fh;

            my %args = (
                pid => $pid,
                dsID => "RELS-INT",
                file => $file,
                versionable => "true",
                dsLabel => "Fedora Relationship Metadata.",
                mimeType => "application/rdf+xml"
            );

            my $r;
            if($is_new){
                $r = $fedora->addDatastream(%args);
            }else{
                $r = $fedora->modifyDatastream(%args);
            }
            die($r->raw()) unless $r->is_ok();
            if($is_new){
                say "object $pid: datastream RELS-INT added";
            }else{
                say "object $pid: datastream RELS-INT updated";
            }
        }
    }
});
