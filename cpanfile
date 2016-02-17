requires 'perl','5.12.1';
requires 'Catmandu';
#requires 'Catmandu::MediaWiki';
requires 'MediaWiki::API';
requires 'Catmandu::FedoraCommons','0';
requires 'Text::MediawikiFormat','0';
requires 'IO::CaptureOutput','0';
requires 'Archive::Zip','0';

on 'test', sub {
    requires 'Test::Exception','0';
    requires 'Test::More','0';
};
