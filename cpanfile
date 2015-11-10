requires 'perl','5.12.1';
requires 'Catmandu';
#requires 'Catmandu::MediaWiki';
requires 'MediaWiki::API';
requires 'Catmandu::FedoraCommons';

on 'test', sub {
    requires 'Test::Exception','0';
    requires 'Test::More','0';
};
