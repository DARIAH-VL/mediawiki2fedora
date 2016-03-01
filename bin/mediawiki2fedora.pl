#!/usr/bin/env perl
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is :array);
use MediaWikiFedora qw(:all);
use File::Temp qw(tempfile tempdir);
use Getopt::Long;
use RDF::Trine;
use RDF::Trine::Serializer;
use File::Basename;
use RevisionProcessor::SRC;
use RevisionProcessor::TXT;
use RevisionProcessor::HTML2;
use RevisionProcessor::MARKDOWN2;
use RevisionProcessor::IMG;
use RevisionProcessor::SCREENSHOT_PDF2;
use RevisionProcessor::SCREENSHOT_PNG;

my $force = 0;
my $delete = 0;

GetOptions(
    "force" => \$force,
    "delete" => \$delete
);

my $namespace_page = Catmandu->config->{namespace_page} // "mediawiki";
my $ownerId = Catmandu->config->{ownerId} // "mediawiki";
my $fedora = fedora();
my $mediawiki_importer = Catmandu->config->{mediawiki_importer} || "mediawiki";

my $namespaces = {
    dc => "http://purl.org/dc/elements/1.1/",
    dcterms => "http://purl.org/dc/terms/",
    "fedora-model" => "info:fedora/fedora-system:def/model#",
    foxml => "info:fedora/fedora-system:def/foxml#",
    xsi => "http://www.w3.org/2001/XMLSchema-instance",
    #cf. http://www.fedora.info/definitions/1/0/fedora-relsext-ontology.rdfs
    rel => "info:fedora/fedora-system:def/relations-external#"
};

my $rdf_serializer = RDF::Trine::Serializer->new('rdfxml',namespaces => $namespaces );

Catmandu->importer($mediawiki_importer)->each(sub{
    my $page = shift;

    for(my $i = 0; $i < scalar( @{ $page->{revisions} }); $i++){

        my $revision = $page->{revisions}->[$i];

        #TODO:please delete _url (not part of the rest api)
        #for the moment the RevisionProcessors need this!
        my $url = $revision->{_url};

        my $imageinfo = is_array_ref($page->{imageinfo}) && is_string($page->{imagerepository}) && $page->{imagerepository} eq "local" ? $page->{imageinfo}->[$i] : undef;

        #TODO: laatste rev is toch de eerste in de rij??????????
        my $state = $i == 0 ? 'A' : 'I';
        my $pid = "${namespace_page}:".$page->{pageid}."_".$revision->{revid};

        #previous means: the next revision in the list!
        my $prev_pid;
        my $prev_revision;
        if($i < ( scalar( @{ $page->{revisions} }) - 1 ) ){
            $prev_revision = $page->{revisions}->[$i + 1];
            $prev_pid = "${namespace_page}:".$page->{pageid}."_".$prev_revision->{revid};
        }

        #get page
        my $object_profile;
        {
            my $res = getObjectProfile(pid => $pid);
            if( $res->is_ok ) {
                $object_profile = $res->parse_content();

                if ( $delete ) {

                    $fedora->purgeObject(pid => $pid);
                    say "object $pid: purged";
                    $object_profile = undef;

                }
            }
        }
        #empty datastream DC
        unless( defined( $object_profile ) ){
            my $foxml = generate_foxml({ label => $page->{title}, ownerId => ${ownerId} });

            my $res = ingest( pid => $pid , xml => $foxml , format => 'info:fedora/fedora-system:FOXML-1.1' );
            die($res->raw()) unless $res->is_ok();
            say "object $pid: ingested";
        }
        #modify state => TODO: first time not set???
        {
            if( defined( $object_profile ) && $object_profile->{objState} ne $state){
                my $res = $fedora->modifyObject( pid => $pid, state => $state, logMessage => "changed state to $state" );
                die($res->raw()) unless $res->is_ok();
                say "object $pid: changed state to $state";
            }
        }
        #update datastream DC
        {
            my $res = $fedora->getDatastream(pid => $pid, dsID => "DC");
            if( !defined($object_profile) || !$res->is_ok() || $force ) {
                #identifier beter niet identifier van de revision??
                my $ds_dc = {
                    _id => $pid,
                    title => [$page->{title}],
                    #already using _id
                    #identifier => [$revision->{revid}],
                    creator => [$revision->{user}],
                    date => [$revision->{timestamp}],
                    #TODO: http://localhost:8000/md/index.php?title=<title>&oldid=<revid>
                    source => [$url]
                };
                dc->update($ds_dc);
                say "object $pid: modified datastream DC";
            }
        }
        #RELS-EXT
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
                    rdf_resource($namespaces->{'fedora-model'}."hasModel"),
                    rdf_resource("info:fedora/mediawiki:pageCModel")
                )
            );
            if($prev_revision){

                $new_rdf->add_statement(
                    rdf_statement(
                        rdf_resource("info:fedora/${pid}"),
                        rdf_resource($namespaces->{'dcterms'}."replaces"),
                        rdf_resource("info:fedora/${prev_pid}")
                    )
                );

            }

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

                unlink $file if is_string($file) && -f $file;
            }

        }
        #add datastream SRC
        {
            my $p = RevisionProcessor::SRC->new(
                fedora => $fedora,
                page => $page,
                revision => $revision,
                pid => $pid,
                dsID => "SRC",
                force => $force
            );
            $p->process();
            $p->insert();
            $p->cleanup();
        }
        #add datastream TXT
        {
            my $p = RevisionProcessor::TXT->new(
                fedora => $fedora,
                page => $page,
                revision => $revision,
                pid => $pid,
                dsID => "TXT",
                force => $force
            );
            $p->process();
            $p->insert();
            $p->cleanup();
        }
        #add datastream HTML
        {
            my $p = RevisionProcessor::HTML2->new(
                fedora => $fedora,
                page => $page,
                revision => $revision,
                pid => $pid,
                dsID => "HTML",
                force => $force
            );
            $p->process();
            $p->insert();
            $p->cleanup();
        }
        #add datastream MARKDOWN
        {
            my $p = RevisionProcessor::MARKDOWN2->new(
                fedora => $fedora,
                page => $page,
                revision => $revision,
                pid => $pid,
                dsID => "MARKDOWN",
                force => $force
            );
            $p->process();
            $p->insert();
            $p->cleanup();

        }

        #add datastream IMG (if this the description page of a file)
        if( defined($imageinfo) ){
            my $p = RevisionProcessor::IMG->new(
                fedora => $fedora,
                page => $page,
                revision => $revision,
                imageinfo => $imageinfo,
                pid => $pid,
                dsID => "IMG",
                force => $force
            );
            $p->process();
            $p->insert();
            $p->cleanup();
        }
        #add datastream SCREENSHOT_PDF2
        {

            if( is_string( $url ) ) {
                my $p = RevisionProcessor::SCREENSHOT_PDF2->new(
                    fedora => $fedora,
                    page => $page,
                    revision => $revision,
                    pid => $pid,
                    dsID => "SCREENSHOT_PDF",
                    force => $force
                );
                $p->process();
                $p->insert();
                $p->cleanup();

            }

        }

        #add datastream SCREENSHOT_PNG
        {

            if( is_string( $url ) ) {
                my $p = RevisionProcessor::SCREENSHOT_PNG->new(
                    fedora => $fedora,
                    page => $page,
                    revision => $revision,
                    pid => $pid,
                    dsID => "SCREENSHOT_PNG",
                    force => $force
                );
                $p->process();
                $p->insert();
                $p->cleanup();

            }

        }
        #update RELS-INT
        {
            my $rdf_xml;
            my $old_rdf = rdf_model();
            my $new_rdf = rdf_model();
            my $res = getDatastreamDissemination( pid => $pid, dsID => "RELS-INT" );
            my $is_new = 1;
            if( $res->is_ok ){

                say "object $pid: RELS-INT found";
                $is_new = 0;

                $rdf_xml = $res->raw();
                my $parser = rdf_parser();
                $parser->parse_into_model(undef,$rdf_xml,$old_rdf);

            }else{

                say "object $pid: RELS-INT not found";

            }
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}/HTML"),
                    rdf_resource($namespaces->{rel}."isDerivationOf"),
                    rdf_resource("info:fedora/${pid}/TXT")
                )
            );
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}/MARKDOWN"),
                    rdf_resource($namespaces->{rel}."isDerivationOf"),
                    rdf_resource("info:fedora/${pid}/HTML")
                )
            );

            my $old_graph = rdf_graph( $old_rdf );
            my $new_graph = rdf_graph( $new_rdf );

            unless( $old_graph->equals($new_graph) ){

                say "object $pid: RELS-INT has changed";

                my $rdf_data = $rdf_serializer->serialize_model_to_string( $new_rdf );

                #write content to tempfile
                my $file = to_tmp_file($rdf_data);

                my %args = (
                    pid => $pid,
                    dsID => "RELS-INT",
                    file => $file,
                    versionable => "true",
                    dsLabel => "Fedora internal Relationship Metadata.",
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

                    say "object $pid: datastream RELS-INT added";

                }else{

                    say "object $pid: datastream RELS-INT updated";

                }

                unlink $file if is_string($file) && -f $file;
            }

        }


    }

});
