package RevisionProcessor::SRC;
use Catmandu::Sane;
use Moo;
use Catmandu::Util qw(:is);
use Clone qw();
use MediaWikiFedora qw(to_tmp_file json);

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
            say "object $pid: modify datastream $dsID";
            my $res = $self->fedora->modifyDatastream(%args);
            die($res->raw()) unless $res->is_ok();
        }
    }
    else{
        say "adding datastream $dsID to object $pid";

        my $res = $self->fedora->addDatastream(%args);
        die($res->raw()) unless $res->is_ok();

    }

}
sub cleanup {
    my $self = $_[0];
    my $files = $self->files();
    for my $file(@{ $self->files() }){
        say "deleting file $file";
        unlink $file if is_string($file) && -f $file;
    }
}

1;
