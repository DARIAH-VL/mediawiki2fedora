#!/usr/bin/env perl
use lib qw(/home/njfranck/git/Catmandu-MediaWiki/lib);
use lib qw(/home/njfranck/git/Catmandu-FedoraCommons/lib);
use Catmandu::Sane;
use Catmandu::Importer::MediaWiki;
use Catmandu::Store::FedoraCommons;

my $foxml = <<EOF;
    <foxml:digitalObject VERSION="1.1" xmlns:foxml="info:fedora/fedora-system:def/foxml#" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd">
        <foxml:objectProperties>
            <foxml:property NAME="info:fedora/fedora-system:def/model#state" VALUE="Active"/>
        </foxml:objectProperties>
        <foxml:datastream CONTROL_GROUP="X" ID="DC" STATE="A" VERSIONABLE="false">
            <foxml:datastreamVersion FORMAT_URI="http://www.openarchives.org/OAI/2.0/oai_dc/" ID="DC1.0" LABEL="Dublin Core Record for this object" MIMETYPE="text/xml">
                <foxml:xmlContent>
                    <oai_dc:dc xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/">
                    </oai_dc:dc>
                </foxml:xmlContent>
            </foxml:datastreamVersion>
        </foxml:datastream>
    </foxml:digitalObject>
EOF

binmode STDOUT,":utf8";

my $importer = Catmandu::Importer::MediaWiki->new(
    url => "http://localhost:8000/w/api.php",
    args => { gapfilterredir => undef }
);
my $store = Catmandu::Store::FedoraCommons->new(
    baseurl => "http://localhost:8080/fedora",
    username => "fedoraAdmin",
    password => "1q0p2w0p3e0p",
    model    => 'Catmandu::Store::FedoraCommons::DC'
);
my $fedora = $store->fedora();

$importer->tap(sub{
    #say "adding mediawiki:".$_[0]->{pageid};
})->each(sub{
    my $r = shift;
    $store->bag('mediawiki')->add({
        #_id => "mediawiki:".$r->{pageid},
        title => [$r->{title}],
        identifier => [$r->{pageid}]
    });
});
