package RevisionProcessor::IMG;
use Catmandu::Sane;
use Moo;
use Catmandu::Util qw(:is);
use IO::CaptureOutput qw(capture_exec);
use MediaWikiFedora qw(to_tmp_file lwp);

with 'RevisionProcessor';

has imageinfo => (is => 'ro');

has files => (
    is => 'rw',
    lazy => 1,
    default => sub { []; }
);

sub process {
    my $self = $_[0];
    my $revision = $self->revision();
    my $page = $self->page();
    my $imageinfo = $self->imageinfo();
    my $datastream = $self->datastream();

    if ( !$datastream || $self->force ) {

        say "retrieving IMG from ".$imageinfo->{url};
        my $res = lwp->get($imageinfo->{url});
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
    my $imageinfo = $self->imageinfo();

    my %args = (
        pid => $pid,
        dsID => $dsID,
        file => $file,
        versionable => "true",
        dsLabel => "Mediawiki image",
        mimeType => $imageinfo->{mime},
        checksumType => "SHA-1",
        checksum => $imageinfo->{sha1}
    );

    if( $datastream ) {
        if ( $self->force ) {
            say "object $pid: modify datastream $dsID";
            my $res = $self->fedora()->modifyDatastream(%args);
            die($res->raw()) unless $res->is_ok();
        }
    }
    else{
        say "adding datastream $dsID to object $pid";

        my $res = $self->fedora()->addDatastream(%args);
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
