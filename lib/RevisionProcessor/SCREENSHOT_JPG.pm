package RevisionProcessor::SCREENSHOT_JPG;
use Catmandu::Sane;
use Moo;
use Catmandu::Util qw(:is :array);
use MediaWikiFedora qw(to_tmp_file);
use IO::CaptureOutput qw(capture_exec);
use File::Temp qw(tempfile);

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

        my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0);
        my $url = $revision->{_url};
        my $command = "wkhtmltoimage -q -f jpg \"${url}\" \"${a_file}\"";
        my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
        die($stderr) unless $success;

        $self->files([ $a_file ]);

    }

}
sub insert {
    my $self = $_[0];
    my $pid = $self->pid;
    my $dsID = $self->dsID;
    my $file = $self->files->[0];
    my $datastream = $self->datastream();

    my %args = (
        pid => $pid,
        dsID => $dsID,
        file => $file,
        versionable => "false",
        dsLabel => "screenshot in jpeg format",
        mimeType => "image/jpeg"
    );

    if( $datastream ) {
        if ( $self->force ) {
            say "modifying datastream $dsID of object $pid";
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
        if( -f $file ){
            say "deleting file $file";
            unlink $file;
        }
    }
}

1;
