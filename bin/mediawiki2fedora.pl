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
use RDF::Trine::Serializer;

my $force = 0;

GetOptions(
    "force" => \$force
);

my $namespace_page = Catmandu->config->{namespace_page} // "mediawiki";
my $namespace_revision = Catmandu->config->{namespace_revision} // "mediawikirevision";
my $namespace_file = Catmandu->config->{namespace_file} // "mediawikifile";
my $ownerId = Catmandu->config->{ownerId} // "mediawiki";
my $fedora = fedora();

my $namespaces = {
    dc => "http://purl.org/dc/elements/1.1/",
    "fedora-model" => "info:fedora/fedora-system:def/model#",
    foxml => "info:fedora/fedora-system:def/foxml#",
    xsi => "http://www.w3.org/2001/XMLSchema-instance",
    rel => "info:fedora/fedora-system:def/relations-external#"
};

my $rdf_serializer = RDF::Trine::Serializer->new('rdfxml',namespaces => $namespaces );

Catmandu->importer('mediawiki')->each(sub{
    my $r = shift;

    #1. add/update page
    {
        #1.1 get page
        my $pid = "${namespace_page}:".$r->{pageid};
        my $page_object_profile;
        {
            my $res = getObjectProfile(pid => $pid);
            if( $res->is_ok ) {
                $page_object_profile = $res->parse_content();
            }
        }
        #1.2 new page with empty datastream DC
        if(!defined($page_object_profile)){
            say "object $pid: ingest";
            my $foxml = generate_foxml({ label => $r->{title}, ownerId => ${ownerId} });

            my $res = ingest( pid => $pid , xml => $foxml , format => 'info:fedora/fedora-system:FOXML-1.1' );
            die($res->raw()) unless $res->is_ok();
        }
        #1.3 update datastream DC
        {
            my $res = getDatastream(pid => $pid, dsID => "DC");
            if( !$res->is_ok() || $force ) {
                say "object $pid: modify datastream DC";
                my $ds_dc = { _id => $pid, title => [$r->{title}], identifier => [$r->{pageid}] };
                dc->update($ds_dc);
            }
        }
        #1.4 update RELS-EXT
        {
            my $rdf_xml;
            my $old_rdf = rdf_model();
            my $new_rdf = rdf_model();
            my $res = getDatastreamDissemination( pid => $pid, dsID => "RELS-EXT" );
            my $is_new = 1;
            if( $res->is_ok ){

                say "object $pid: RELS-EXT found";
                $is_new = 0;

                $rdf_xml = $res->raw();
                my $parser = rdf_parser();
                $parser->parse_into_model(undef,$rdf_xml,$old_rdf);

            }else{

                say "object $pid: RELS-EXT not found";

            }
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}"),
                    rdf_resource($namespaces->{rel}."isCollection"),
                    rdf_literal("true")
                )
            );
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}"),
                    rdf_resource($namespaces->{'fedora-model'}."hasModel"),
                    rdf_resource("info:fedora/mediawiki:pageCModel")
                )
            );

            my $old_graph = rdf_graph( $old_rdf );
            my $new_graph = rdf_graph( $new_rdf );

            unless( $old_graph->equals($new_graph) ){

                say "object $pid: RELS-EXT has changed";

                my $rdf_data = $rdf_serializer->serialize_model_to_string( $new_rdf );

                #write content to tempfile
                my $file = to_tmp_file($rdf_data);

                my %args = (
                    pid => $pid,
                    dsID => "RELS-EXT",
                    file => $file,
                    versionable => "true",
                    dsLabel => "Fedora Object to Object Relationship Metadata.",
                    mimeType => "application/rdf+xml"
                );

                my $r;
                if($is_new){

                    $r = addDatastream(%args);

                }else{

                    $r = modifyDatastream(%args);

                }

                die($r->raw()) unless $r->is_ok();

                if($is_new){

                    say "object $pid: datastream RELS-EXT added";

                }else{

                    say "object $pid: datastream RELS-EXT updated";

                }
            }
        }

    }

    #2. add revisions as separate objects
    for my $revision(@{ $r->{revisions} }) {

        my $pid = "${namespace_revision}:".$revision->{revid};

        #2.1 get revision
        my $rev_object_profile;
        {
            my $res = getObjectProfile(pid => $pid);
            if( $res->is_ok ) {
                $rev_object_profile = $res->parse_content();
            }
        }
        #2.2 new revision with empty datastream DC
        if(!defined($rev_object_profile)){
            say "object $pid: ingest";
            my $foxml = generate_foxml({ label => $r->{title}, ownerId => ${ownerId} });

            my $res = ingest( pid => $pid , xml => $foxml , format => 'info:fedora/fedora-system:FOXML-1.1' );
            die($res->raw()) unless $res->is_ok();
        }
        #2.3 update datastream DC
        {
            my $res = $fedora->getDatastream(pid => $pid, dsID => "DC");
            if( !$res->is_ok() || $force ) {
                say "object $pid: modify datastream DC";
                my $ds_dc = { _id => $pid, title => [$r->{title}], identifier => [$r->{pageid}] };
                dc->update($ds_dc);
            }
        }
        #2.4 update RELS-EXT
        {
            my $rdf_xml;
            my $old_rdf = rdf_model();
            my $new_rdf = rdf_model();
            my $res = getDatastreamDissemination( pid => $pid, dsID => "RELS-EXT" );
            my $is_new = 1;
            if( $res->is_ok ){

                say "object $pid: RELS-EXT found";
                $is_new = 0;

                $rdf_xml = $res->raw();
                my $parser = rdf_parser();
                $parser->parse_into_model(undef,$rdf_xml,$old_rdf);

            }else{

                say "object $pid: RELS-EXT not found";

            }
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}"),
                    rdf_resource($namespaces->{rel}."isMemberOf"),
                    rdf_resource("info:fedora/${namespace_page}:".$r->{pageid})
                )
            );
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}"),
                    rdf_resource($namespaces->{'fedora-model'}."hasModel"),
                    rdf_resource("info:fedora/mediawiki:revisionCModel")
                )
            );

            my $old_graph = rdf_graph( $old_rdf );
            my $new_graph = rdf_graph( $new_rdf );

            unless( $old_graph->equals($new_graph) ){

                say "object $pid: RELS-EXT has changed";

                my $rdf_data = $rdf_serializer->serialize_model_to_string( $new_rdf );

                #write content to tempfile
                my $file = to_tmp_file($rdf_data);

                my %args = (
                    pid => $pid,
                    dsID => "RELS-EXT",
                    file => $file,
                    versionable => "true",
                    dsLabel => "Fedora Object to Object Relationship Metadata.",
                    mimeType => "application/rdf+xml"
                );

                my $r;
                if($is_new){

                    $r = addDatastream(%args);

                }else{

                    $r = modifyDatastream(%args);

                }

                die($r->raw()) unless $r->is_ok();

                if($is_new){

                    say "object $pid: datastream RELS-EXT added";

                }else{

                    say "object $pid: datastream RELS-EXT updated";

                }
            }

        }
        #add SRC
        {
            my $dsID = "SRC";
            my $datastream;
            {
                my $res = getDatastream(pid => $pid, dsID => $dsID);
                if ( $res->is_ok() ) {
                    $datastream = $res->parse_content();
                }

            }

            my $file;
            my %args;

            if ( !$datastream || $force ) {

                #write content to tempfile
                $file = to_tmp_file(json->encode($revision));

                %args = (
                    pid => $pid,
                    dsID => $dsID,
                    file => $file,
                    versionable => "false",
                    dsLabel => "source for datastream HTML",
                    mimeType => "application/json; charset=utf-8"
                );
            }

            if( $datastream ) {
                if ( $force ) {
                    say "object $pid: modify datastream $dsID";
                    my $res = modifyDatastream(%args);
                    die($res->raw()) unless $res->is_ok();
                }
            }
            else{
                say "adding datastream $dsID to object $pid";

                my $res = addDatastream(%args);
                die($res->raw()) unless $res->is_ok();

            }

            unlink $file if is_string($file) && -f $file;
        }
        #add mediawiki text
        {
            my $dsID = "TXT";
            my $datastream;
            {
                my $res = getDatastream(pid => $pid, dsID => $dsID);
                if ( $res->is_ok() ) {
                    $datastream = $res->parse_content();
                }
            }

            my $file;
            my %args;
            if ( !$datastream || $force ) {
                #write content to tempfile
                $file = to_tmp_file($revision->{'*'});

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
                    my $res = modifyDatastream(%args);
                    die($res->raw()) unless $res->is_ok();
                }
            }
            else{
                say "adding datastream $dsID to object $pid";

                my $res = addDatastream(%args);
                die($res->raw()) unless $res->is_ok();
            }

            unlink $file if is_string($file) && -f $file;
        }
        #add datastream HTML
        {
            my $dsID = "HTML";
            my $datastream;
            {
                my $res = getDatastream(pid => $pid, dsID => $dsID);
                if ( $res->is_ok() ) {
                    $datastream = $res->parse_content();
                }
            }

            my $file;
            my %args;
            if ( !$datastream || $force ) {

                my $content = $revision->{'*'};

                my $html = wiki2html( $content );
                #write content to tempfile
                $file = to_tmp_file($html);

                #dsLabel has a maximum of 255 characters
                my $dsLabel = "HTML version of datastream TXT";
                utf8::encode($dsLabel);

                %args = (
                    pid => $pid,
                    dsID => $dsID,
                    file => $file,
                    versionable => "false",
                    dsLabel => $dsLabel,
                    mimeType => "text/html; charset=utf-8",
                    #TODO
                    #checksumType => "SHA-1",
                    #checksum => $revision->{sha1}
                );
            }
            if( $datastream ) {
                if ( $force ) {
                    say "object $pid: modify datastream $dsID";
                    my $res = modifyDatastream(%args);
                    die($res->raw()) unless $res->is_ok();
                }
            }
            else{
                say "adding datastream $dsID to object $pid";

                my $res = addDatastream(%args);
                die($res->raw()) unless $res->is_ok();

            }

            unlink $file if is_string($file) && -f $file;
        }
    }
});
