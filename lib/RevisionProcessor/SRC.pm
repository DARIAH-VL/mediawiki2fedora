package RevisionProcessor::SRC;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Catmandu;
use Moo;
use Clone qw();
use MediaWikiFedora qw(to_tmp_file json md5_file);

with 'RevisionProcessor';

has files => (
    is => 'rw',
    lazy => 1,
    default => sub { []; }
);

sub process {
    my $self = $_[0];

    my $datastream = $self->datastream();

    if ( !$datastream || $self->force ) {

        #write content to tempfile
        my $rev = Clone::clone($self->revision);
        delete $rev->{_url};
        my $file = to_tmp_file(json->encode($rev));

        $self->files([$file]);

    }


}
sub insert {
    my $self = $_[0];
    my $pid = $self->pid;
    my $dsID = $self->dsID;
    my $file = $self->files->[0];

    my %args = (
        pid => $pid,
        dsID => $dsID,
        file => $file,
        versionable => "true",
        dsLabel => "source for datastream HTML",
        mimeType => "application/json; charset=utf-8"
    );

    if( $self->datastream ) {
        if ( $self->force ) {

            $args{checksum} = md5_file($file);
            $args{checksumType} = "MD5";

            Catmandu->log->info("object $pid: modify datastream $dsID");
            my $res = $self->fedora->modifyDatastream(%args);
            unless( $res->is_ok() ){
                Catmandu->log->error($res->raw());
                die($res->raw());
            }
        }
    }
    else{

        $args{checksum} = md5_file($file);
        $args{checksumType} = "MD5";

        Catmandu->log->info("adding datastream $dsID to object $pid");

        my $res = $self->fedora->addDatastream(%args);
        unless( $res->is_ok() ){
            Catmandu->log->error($res->raw());
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
