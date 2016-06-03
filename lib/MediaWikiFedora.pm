package MediaWikiFedora;
use Catmandu::Sane;
use Catmandu;
use Catmandu::Util qw(:is xml_escape require_package);
use JSON qw();
use Catmandu::Importer::MediaWiki;
use Catmandu::FedoraCommons;
use Catmandu::Store::FedoraCommons;
use Catmandu::Store::FedoraCommons::DC;
use Catmandu::IdGenerator::UUID;
use URI::Escape qw(uri_escape);
use Text::MediawikiFormat qw(wikiformat);
use File::Temp qw(tempfile);
use RDF::Trine;
use RDF::Trine::Node::Resource;
use RDF::Trine::Node::Literal;
use RDF::Trine::Serializer;
use RDF::Trine::Graph;
use LWP::UserAgent;
use Exporter qw(import);

sub root {
    state $root = do {
        require File::Basename;
        require Cwd;
        my $dir = Cwd::abs_path(File::Basename::dirname(__FILE__));
        my(@p) = split /\//,$dir;
        shift @p;
        my $r;
        while(@p){
            my $d = "/".join("/",@p);
            my $c = "$d/catmandu.yml";
            if(-f $c){
                $r = $d;
                last;
            }
            pop @p;
        }
        $r;
    };
}
sub init_log {
    state $loaded = 0;
    return if $loaded;
    require Log::Any::Adapter;
    require Log::Log4perl;
    #init log
    Log::Log4perl::init(root().'/log4perl.conf');
    Log::Any::Adapter->set('Log::Log4perl');
    $loaded = 1;
}
BEGIN {
    init_log();
}

my @mediawiki = qw(mediawiki mw_find_by_title);
my @fedora = qw(id_generator create_id fedora dc generate_foxml ingest addDatastream modifyDatastream getDatastream getDatastreamDissemination getObjectProfile);
my @rdf = qw(rdf_parser rdf_model rdf_statement rdf_literal rdf_resource rdf_graph rdf_namespaces rdf_serializer rdf_change);
my @utils = qw(json wiki2html to_tmp_file lwp clone_cookies new_cookie_jar md5_file);
our @EXPORT_OK = (@fedora,@rdf,@utils,@mediawiki);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
    fedora => [@fedora],
    mediawiki => [@mediawiki],
    rdf => [@rdf],
    utils => [@utils]
);
sub create_id {
    id_generator()->generate();
}
sub id_generator {
    state $ig = Catmandu::IdGenerator::UUID->new();
}
sub json {
    state $json = JSON->new;
}
sub fedora {
    state $fedora = Catmandu::FedoraCommons->new( @{ Catmandu->config->{fedora} || [] } );
}
sub dc {
    state $dc = Catmandu::Store::FedoraCommons::DC->new( fedora => fedora() );
}

sub generate_foxml {
    my $obj = $_[0];

    my @foxml =  (
        '<foxml:digitalObject VERSION="1.1" xmlns:foxml="info:fedora/fedora-system:def/foxml#" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd">',
            '<foxml:objectProperties>',
                '<foxml:property NAME="info:fedora/fedora-system:def/model#state" VALUE="Active"/>'
    );

    if( is_string( $obj->{label} ) ) {
        push @foxml,"<foxml:property NAME=\"info:fedora/fedora-system:def/model#label\" VALUE=\"";
        push @foxml,xml_escape($obj->{label});
        push @foxml,"\"/>";
    }
    if( is_string( $obj->{ownerId} ) ) {
        push @foxml,"<foxml:property NAME=\"info:fedora/fedora-system:def/model#ownerId\" VALUE=\"";
        push @foxml,xml_escape($obj->{ownerId});
        push @foxml,"\"/>";
    }
    push @foxml,
            '</foxml:objectProperties>';

    #add datastream DC (empty)
    push @foxml,
            '<foxml:datastream CONTROL_GROUP="X" ID="DC" STATE="A" VERSIONABLE="false">',
                '<foxml:datastreamVersion FORMAT_URI="http://www.openarchives.org/OAI/2.0/oai_dc/" ID="DC1.0" LABEL="Dublin Core Record for this object" MIMETYPE="text/xml">',
                    '<foxml:xmlContent>',
                        '<oai_dc:dc xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/">',
                        '</oai_dc:dc>',
                    '</foxml:xmlContent>',
                '</foxml:datastreamVersion>',
            '</foxml:datastream>';

    #add datastream RELS-INT

    push @foxml,
        '</foxml:digitalObject>';

    join("",@foxml);

}
sub wiki2html {
    wikiformat(@_);
}
sub rdf_resource {
    RDF::Trine::Node::Resource->new($_[0]);
}
sub rdf_literal {
    RDF::Trine::Node::Literal->new($_[0]);
}
sub rdf_statement {
    RDF::Trine::Statement->new(@_);
}
sub rdf_graph {
    RDF::Trine::Graph->new(@_);
}
sub rdf_model {
    RDF::Trine::Model->temporary_model;
}
sub rdf_parser {
    state $p = RDF::Trine::Parser->new('rdfxml');
}
sub rdf_namespaces {
    state $n = {
        dc => "http://purl.org/dc/elements/1.1/",
        dcterms => "http://purl.org/dc/terms/",
        "fedora-model" => "info:fedora/fedora-system:def/model#",
        foxml => "info:fedora/fedora-system:def/foxml#",
        xsi => "http://www.w3.org/2001/XMLSchema-instance",
        #cf. http://www.fedora.info/definitions/1/0/fedora-relsext-ontology.rdfs
        rel => "info:fedora/fedora-system:def/relations-external#"
    };
}
sub rdf_serializer {
    RDF::Trine::Serializer->new('rdfxml',namespaces => rdf_namespaces() );
}
sub rdf_change {
    my (%opts) = @_;
    my $pid = delete $opts{pid};
    my $dsId = delete $opts{dsId};
    my $new_rdf = $opts{rdf};
    my $old_rdf = rdf_model();

    my $rdf_serializer = rdf_serializer();
    my $r = getDatastreamDissemination( pid => $pid, dsID => $dsId );
    my $is_new = 1;

    if( $r->is_ok ){

        Catmandu->log->info("object $pid: datastream $dsId found");
        $is_new = 0;

        my $rdf_xml = $r->raw();
        my $parser = rdf_parser();
        $parser->parse_into_model(undef,$rdf_xml,$old_rdf);

    }else{

        Catmandu->log->warn("object $pid: datastream $dsId not found");

    }
    my $old_graph = rdf_graph( $old_rdf );
    my $new_graph = rdf_graph( $new_rdf );

    unless( $old_graph->equals($new_graph) ){

        Catmandu->log->info("object $pid: datastream $dsId has changed");

        my $rdf_data = $rdf_serializer->serialize_model_to_string( $new_rdf );

        #write content to tempfile
        my $file = to_tmp_file($rdf_data);

        my $dsLabel = $dsId eq "RELS-EXT" ? "Fedora Object to Object Relationship Metadata." : $dsId eq "RELS-INT" ? "Fedora internal Relationship Metadata." : "Fedora Relationship Metadata";

        my %args = (
            pid => $pid,
            dsID => $dsId,
            file => $file,
            versionable => "true",
            dsLabel => $dsLabel,
            mimeType => "application/rdf+xml"
        );

        my $r2;
        if($is_new){

            $r2 = addDatastream(%args);

        }else{

            $r2 = modifyDatastream(%args);

        }

        die($r2->raw()) unless $r2->is_ok();

        if($is_new){

            Catmandu->log->info("object $pid: datastream $dsId added");

        }else{

            Catmandu->log->info("object $pid: datastream $dsId updated");

        }

        unlink $file if is_string($file) && -f $file;
    }

}

sub to_tmp_file {
    my($data,$binmode) = @_;
    $binmode ||= ":utf8";
    my($fh,$file) = tempfile(UNLINK => 1,EXLOCK => 0);
    binmode $fh,$binmode;
    print $fh $data;
    close $fh;
    $file;
}
sub getDatastream {
    fedora()->getDatastream(@_);
}
sub getDatastreamDissemination {
    fedora()->getDatastreamDissemination(@_);
}
sub addDatastream {
    fedora->addDatastream(@_);
}
sub modifyDatastream {
    fedora()->modifyDatastream(@_)
}
sub getObjectProfile {
    fedora()->getObjectProfile(@_);
}
sub ingest {
    fedora()->ingest(@_);
}
sub mediawiki {
    state $mw = do {
        require MediaWiki::API;
        my $config = Catmandu->config->{mediawiki};
        my $mw = MediaWiki::API->new( { api_url =>  $config->{url} });
        my($lgname,$lgpassword) = ( $config->{lgname},$config->{lgpassword} );
        if(is_string($lgname) && is_string($lgpassword)){
            $mw->login({ lgname => $lgname, lgpassword => $lgpassword }) or die($mw->{error}->{details});
        }
        $mw;
    };
}
sub mw_find_by_title {
    my $title = $_[0];
    my $mw = mediawiki();
    my $res = $mw->api({ action => "query", titles => $title }) or die($mw->{error}->{details});
    return undef if exists $res->{query}->{pages}->{'-1'};
    my @pageids = keys %{ $res->{query}->{pages} };
    $res->{query}->{pages}->{ $pageids[0] };
}
sub lwp {
    state $lwp = LWP::UserAgent->new(cookie_jar => {});
}
sub new_cookie_jar {
    my ( $type, $file ) = @_;
    require_package($type, "HTTP::Cookies")->new( file => $file );
}
sub clone_cookies {
    my( $from, $to ) = @_;
    $from->scan(sub{
        #do not discard cookies!
        $_[9] = undef;
        $to->set_cookie(@_);
    });
    $to->save();
    $to;
}
sub md5_file {
    my $path = $_[0];
    open my $fh,"<",$path or die($!);
    binmode $fh,":raw";
    my $md5 = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh;
    $md5;
}

1;
