package RevisionProcessor::HTML2;
use Catmandu::Sane;
use Catmandu;
use Moo;
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(to_tmp_file mediawiki md5_file);

with 'RevisionProcessor';

has files => (
    is => 'rw',
    lazy => 1,
    default => sub { []; }
);

sub process {
    my $self = $_[0];
    my $revision = $self->revision();
    my $datastream = $self->datastream();

    #reuse user agent (with cookies!) from mediawiki api
    my $ua = mediawiki()->{ua};

    if ( !$datastream || $self->force ) {

        my $url = $revision->{_url}."&action=render";
        my $res = $ua->get($url);
        if( $res->is_success() ){

            $self->files([ to_tmp_file($res->content(),":raw") ]);

        }

    }

}
sub insert {
    my $self = $_[0];
    my $pid = $self->pid;
    my $dsID = $self->dsID;
    my $file = $self->files->[0];
    my $revision = $self->revision();
    my $datastream = $self->datastream();

    #dsLabel has a maximum of 255 characters
    my $dsLabel = "HTML rendering for datastream TXT";
    utf8::encode($dsLabel);

    my %args = (
        pid => $pid,
        dsID => $dsID,
        file => $file,
        versionable => "true",
        dsLabel => $dsLabel,
        mimeType => "text/html; charset=utf-8"
    );
    if( $datastream ) {
        if ( $self->force ) {

            $args{checksum} = md5_file($file);
            $args{checksumType} = "MD5";

            Catmandu->log->info("object $pid: modify datastream $dsID");
            my $res = $self->fedora()->modifyDatastream(%args);
            unless( $res->is_ok() ){
                Catmandu->log->error( $res->raw() );
                die($res->raw());
            }
        }
    }
    else{

        $args{checksum} = md5_file($file);
        $args{checksumType} = "MD5";

        Catmandu->log->info("adding datastream $dsID to object $pid");

        my $res = $self->fedora()->addDatastream(%args);
        unless( $res->is_ok() ){
            Catmandu->log->error( $res->raw() );
            die($res->raw());
        }

    }

}
sub cleanup {
    my $self = $_[0];
    my $files = $self->files();
    for my $file(@{ $self->files() }){
        if( is_string($file) && -f $file ){
            Catmandu->log->debug("deleting file $file");
            unlink $file;
        }
    }
}

1;
