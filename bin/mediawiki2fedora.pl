#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu::Util qw(:is xml_escape);
use Catmandu::Importer::MediaWiki;
use Catmandu::Store::FedoraCommons;
use Catmandu::Store::FedoraCommons::DC;
use File::Temp qw(tempfile);
use URI::Escape qw(uri_escape);
use Getopt::Long;
use Data::Dumper;

my $force = 0;

GetOptions(
    "force" => \$force
);

sub fedora {
    state $fedora = Catmandu::FedoraCommons->new(
        "http://localhost:8080/fedora",
        "fedoraAdmin",
        "1q0p2w0p3e0p"
    );
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


my $importer = Catmandu::Importer::MediaWiki->new(
    url => "http://localhost:8000/w/api.php",
    args => { gapfilterredir => undef }
);

$importer->each(sub{
    my $r = shift;
    my $pid = "mediawiki:".$r->{pageid};
    my $object_profile;
    {
        my $res = fedora->getObjectProfile(pid => $pid);
        if( $res->is_ok ) {
            $object_profile = $res->parse_content();
        }
    }
    #1. new object with empty datastream DC
    if(!defined($object_profile)){
        say "object $pid: ingest";
        my $foxml = generate_foxml({ label => $r->{title}, ownerId => "mediawiki" });

        my $res = fedora->ingest( pid => $pid , xml => $foxml , format => 'info:fedora/fedora-system:FOXML-1.1' );
        die($res->raw()) unless $res->is_ok();
    }
    #2. update datastream DC
    {
        my $res = fedora()->getDatastream(pid => $pid, dsID => "DC");
        if( !$res->is_ok() || $force ) {
            say "object $pid: modify datastream DC";
            my $ds_dc = { _id => $pid, title => [$r->{title}], identifier => [$r->{pageid}] };
            dc->update($ds_dc);
        }
    }
    #3. add revisions as separate datastreams
    for my $revision(@{ $r->{revisions} }) {

        my $dsID = "REV.".$revision->{revid};
        my $datastream;
        {
            my $res = fedora()->getDatastream(pid => $pid, dsID => $dsID);
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

            my $dsLabel = $revision->{parsedcomment};
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
                my $res = fedora()->modifyDatastream(%args);
                die($res->raw()) unless $res->is_ok();
            }
        }
        else{
            say "adding datastream $dsID to object $pid";

            my $res = fedora()->addDatastream(%args);
            die($res->raw()) unless $res->is_ok();

        }

        unlink $file if is_string($file) && -f $file;
    }
    #4. updated relationships
    {
        for my $revision(@{ $r->{revisions} }){

            my $dc_ns = "http://purl.org/dc/elements/1.1/";
            my $subject = "info:fedora/${pid}/REV.".$revision->{revid};
            fedora()->addRelationship(
                pid => $pid, relation => [ $subject, "${dc_ns}creator", $revision->{user} ], isLiteral => "true"
            );
            fedora()->addRelationship(
                pid => $pid, relation => [ $subject, "${dc_ns}date", $revision->{timestamp} ], isLiteral => "true"
            );
            if( is_natural($revision->{parentid}) && $revision->{parentid} > 0 ) {

                fedora()->addRelationship(
                    pid => $pid, relation => [ $subject, "${dc_ns}relation.isBasedOn", "info:fedora/${pid}/REV.".$revision->{parentid} ], isLiteral => "false"
                );

            }
        }
    }
});
