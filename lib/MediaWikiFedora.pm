package MediaWikiFedora;
use Catmandu::Sane;
use Catmandu;
use Catmandu::Util qw(:is xml_escape);
use JSON qw();
use Catmandu::Importer::MediaWiki;
use Catmandu::FedoraCommons;
use Catmandu::Store::FedoraCommons;
use Catmandu::Store::FedoraCommons::DC;
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

my @mediawiki = qw(mediawiki mw_find_by_title);
my @fedora = qw(fedora dc generate_foxml ingest addDatastream modifyDatastream getDatastream getDatastreamDissemination getObjectProfile);
my @rdf = qw(rdf_parser rdf_model rdf_statement rdf_literal rdf_resource rdf_graph);
my @utils = qw(json wiki2html to_tmp_file lwp);
our @EXPORT_OK = (@fedora,@rdf,@utils,@mediawiki);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
    fedora => [@fedora],
    mediawiki => [@mediawiki],
    rdf => [@rdf],
    utils => [@utils]
);

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

1;
