requires 'perl','5.10.1';
requires 'Catmandu','1.00';
requires 'Catmandu::MediaWiki','0.02';
requires 'MediaWiki::API','0';
requires 'Catmandu::FedoraCommons','0.274';
requires 'Text::MediawikiFormat','0';
requires 'IO::CaptureOutput','0';
requires 'Archive::Zip','0';
requires 'Clone','0';
requires 'Log::Log4perl','0';
requires 'Log::Any::Adapter','0';
requires 'Log::Any::Adapter::Log4perl','0';
requires 'HTTP::Cookies::PhantomJS','0';
requires 'LWP::Protocol::https','0';
requires 'Digest::MD5','0';

on 'test', sub {
    requires 'Test::Exception','0';
    requires 'Test::More','0';
};
