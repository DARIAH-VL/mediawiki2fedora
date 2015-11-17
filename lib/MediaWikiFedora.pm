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

use Exporter qw(import);

our @EXPORT_OK = qw(generate_foxml json fedora dc);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK]
);

sub json {
    state $json = JSON->new->utf8(1);
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

1;
