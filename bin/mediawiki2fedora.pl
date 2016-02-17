#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu -load => ["."];
use Catmandu::Util qw(:is :array);
use MediaWikiFedora qw(:all);
use File::Temp qw(tempfile tempdir);
use Getopt::Long;
use RDF::Trine;
use RDF::Trine::Serializer;
use File::Copy qw(move);
use File::Basename;
use File::Path qw(rmtree);
use IO::CaptureOutput qw(capture_exec);
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

my $force = 0;

GetOptions(
    "force" => \$force
);

my $namespace_page = Catmandu->config->{namespace_page} // "mediawiki";
my $namespace_revision = Catmandu->config->{namespace_revision} // "mediawikirevision";
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
                say  $r->{_url};
                say "object $pid: modify datastream DC";
                my $ds_dc = {
                    _id => $pid,
                    title => [$r->{title}],
                    #already using _id
                    #identifier => [$r->{pageid}],
                    #creator of page is creator of first revision?
                    creator => [$r->{revisions}->[0]->{user}],
                    source => [ $r->{_url} ]
                };
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
            #references last version
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}"),
                    rdf_resource($namespaces->{'dcterms'}."references"),
                    rdf_resource("info:fedora/${namespace_revision}:".$r->{revisions}->[0]->{revid})
                )
            );
            for my $revision(@{ $r->{revisions} }){

                my $pid_rev = "${namespace_revision}:".$revision->{revid};

                #dcterms:hasPart of dcterms:hasVersion => isPartOf wordt al gebruikt!
                $new_rdf->add_statement(
                    rdf_statement(
                        rdf_resource("info:fedora/${pid}"),
                        rdf_resource($namespaces->{'dcterms'}."hasPart"),
                        rdf_resource("info:fedora/${pid_rev}")
                    )
                );
                $new_rdf->add_statement(
                    rdf_statement(
                        rdf_resource("info:fedora/${pid}"),
                        rdf_resource($namespaces->{'dcterms'}."hasVersion"),
                        rdf_resource("info:fedora/${pid_rev}")
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
            }
        }

    }

    #2. add revisions as separate objects
    for(my $i = 0; $i < scalar( @{ $r->{revisions} }); $i++){

        my $revision = $r->{revisions}->[$i];
        my $imageinfo = is_array_ref($r->{imageinfo}) && is_string($r->{imagerepository}) && $r->{imagerepository} eq "local" ? $r->{imageinfo}->[$i] : undef;

        my $state = $i == scalar(@{ $r->{revisions} }) - 1 ? 'A' : 'I';

        my $pid = "${namespace_revision}:".$revision->{revid};

        #previous means: the next revision in the list!
        my $prev_pid;
        my $prev_revision;
        if($i < ( scalar( @{ $r->{revisions} }) - 1 ) ){
            $prev_revision = $r->{revisions}->[$i + 1];
            $prev_pid = "${namespace_revision}:".$prev_revision->{revid};
        }

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
            my $foxml = generate_foxml({ label => $r->{title}, ownerId => ${ownerId} });

            my $res = ingest( pid => $pid , xml => $foxml , format => 'info:fedora/fedora-system:FOXML-1.1' );
            die($res->raw()) unless $res->is_ok();
            say "object $pid: ingested";
        }
        #modify state
        {
            if($rev_object_profile->{objState} ne $state){
                my $res = $fedora->modifyObject( pid => $pid, state => $state, logMessage => "changed state to $state" );
                die($res->raw()) unless $res->is_ok();
                say "object $pid: changed state to $state";
            }
        }

        #2.3 update datastream DC
        {
            my $res = $fedora->getDatastream(pid => $pid, dsID => "DC");
            if( !$res->is_ok() || $force ) {
                #identifier beter niet identifier van de revision??
                my $ds_dc = {
                    _id => $pid,
                    title => [$r->{title}],
                    #already using _id
                    #identifier => [$revision->{revid}],
                    creator => [$revision->{user}],
                    date => [$revision->{timestamp}],
                    #TODO: http://localhost:8000/md/index.php?title=<title>&oldid=<revid>
                    source => [$revision->{_url}]
                };
                dc->update($ds_dc);
                say "object $pid: modified datastream DC";
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
                    rdf_resource($namespaces->{rel}."isPartOf"),
                    rdf_resource("info:fedora/${namespace_page}:".$r->{pageid})
                )
            );
            $new_rdf->add_statement(
                rdf_statement(
                    rdf_resource("info:fedora/${pid}"),
                    rdf_resource($namespaces->{dcterms}."isPartOf"),
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
                    if($revision->{sha1} eq $datastream->{profile}->{dsChecksum}){
                        say "nothing todo";
                    }else{
                        my $res = modifyDatastream(%args);
                        die($res->raw()) unless $res->is_ok();
                    }
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
        #add datastream MARKDOWN
        {
            my $dsID = "MARKDOWN";
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

                #convert to markdown
                my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0);
                my $command = "pandoc \"${file}\" -f mediawiki -t markdown -o \"${a_file}\"";
                my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
                die($stderr) unless $success;

                move($a_file,$file);

                %args = (
                    pid => $pid,
                    dsID => $dsID,
                    file => $file,
                    versionable => "false",
                    dsLabel => "markdown",
                    mimeType => "text/plain; charset=utf-8"
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

        #add datastream IMG (if this the description page of a file)
        if( defined($imageinfo) ){
            my $dsID = "IMG";
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
                say "retrieving IMG from ".$imageinfo->{url};
                my $res = lwp->get($imageinfo->{url});
                if( $res->is_success() ){

                    $file = to_tmp_file($res->content(),":raw");

                    %args = (
                        pid => $pid,
                        dsID => $dsID,
                        file => $file,
                        versionable => "false",
                        dsLabel => "image",
                        mimeType => $imageinfo->{mime},
                        checksumType => "SHA-1",
                        checksum => $imageinfo->{sha1}
                    );
                }
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
        #2.4 add datastream SCREENSHOT_ZIP
        {

            if( is_string( $revision->{_url} ) ) {
                my $dsID = "SCREENSHOT_ZIP";
                my $datastream;
                {
                    my $res = getDatastream(pid => $pid, dsID => $dsID);
                    if ( $res->is_ok() ) {
                        $datastream = $res->parse_content();
                    }
                }

                my $file;
                my $dir;
                my %args;
                if ( !$datastream || $force ) {

                    my $tempdir = tempdir(CLEANUP => 1,EXLOCK => 0);
                    $dir = $tempdir;
                    my $url = $revision->{_url};
                    #ignore robots.txt, otherwise only page requisites for url without parameters are fetched
                    my $command = "wget -e robots=off -U mozilla -nd -nH -P \"${tempdir}\" -q --adjust-extension --convert-links --page-requisites \"${url}\"";
                    my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
                    #exit code 8 happens when one or more page requisites fail (often favicon.ico)
                    $exit_code >>= 8;
                    unless(array_includes([0,8],$exit_code)){
                        die($stderr);
                    }
                    my @html_files = <${tempdir}/*.html>;
                    if(@html_files){
                        my $source = $html_files[0];
                        my $dest = "${tempdir}/index.html";
                        unless ( move( $source, $dest ) ) {
                            die($!);
                        }
                        my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0);
                        $file = $a_file;
                        my $zip = Archive::Zip->new();
                        my @files = <${tempdir}/*>;
                        for my $file(@files){
                            $zip->addFile($file,basename($file));
                        }
                        unless( $zip->writeToFileNamed( $a_file ) == AZ_OK ){
                            die("unable to write to zip file $a_file");
                        }
                        %args = (
                            pid => $pid,
                            dsID => $dsID,
                            file => $file,
                            versionable => "false",
                            dsLabel => "html and prerequisites saved to zip",
                            mimeType => "application/zip"
                        );
                    }

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
                rmtree($dir) if is_string($dir) && -d $dir;
            }

        }
        #2.5 add datastream SCREENSHOT_PDF
        {

            if( is_string( $revision->{_url} ) ) {
                my $dsID = "SCREENSHOT_PDF";
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

                    my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0);
                    $file = $a_file;
                    my $url = $revision->{_url};
                    my $command = "wkhtmltopdf --orientation Landscape \"${url}\" \"${file}\"";
                    my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
                    die($stderr) unless $success;

                    %args = (
                        pid => $pid,
                        dsID => $dsID,
                        file => $file,
                        versionable => "false",
                        dsLabel => "screenshot in pdf format",
                        mimeType => "application/pdf"
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
        #2.6 add datastream SCREENSHOT_JPG
        {

            if( is_string( $revision->{_url} ) ) {
                my $dsID = "SCREENSHOT_JPG";
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

                    my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0);
                    $file = $a_file;
                    my $url = $revision->{_url};
                    my $command = "wkhtmltoimage -q -f jpg \"${url}\" \"${file}\"";
                    my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
                    die($stderr) unless $success;

                    %args = (
                        pid => $pid,
                        dsID => $dsID,
                        file => $file,
                        versionable => "false",
                        dsLabel => "screenshot in jpeg format",
                        mimeType => "image/jpeg"
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

        #2.7 update RELS-INT
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
            }

        }

    }
});
