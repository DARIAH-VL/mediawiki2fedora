package RevisionProcessor::HTML;
use Catmandu::Sane;
use Catmandu;
use Moo;
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(to_tmp_file json wiki2html md5_file);

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

    if ( !$datastream || $self->force ) {

        my $html = wiki2html( $revision->{'*'} );
        $self->files([
            to_tmp_file($html)
        ]);

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
    my $dsLabel = "HTML version of datastream TXT";
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
