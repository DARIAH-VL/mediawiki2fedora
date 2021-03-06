package RevisionProcessor::SCREENSHOT_JPG;
use Catmandu::Sane;
use Catmandu;
use Catmandu::Util qw(:is :array);
use Moo;
use MediaWikiFedora qw(to_tmp_file md5_file);
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
    my $page = $self->page();

    my $is_last;
    {
        my $i = 0;
        for($i = 0;$i < scalar(@{ $page->{revisions} });$i++){
            last if $page->{revisions}->[$i]->{revid} eq $revision->{revid};
        }
        $is_last = $i == 0 ? 1 : 0;
    }

    my $datastream = $self->datastream();

    if ( !$datastream || $self->force ) {

        my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0);
        my $url = $is_last ? $page->{_url} : $revision->{_url};
        #TODO: use cookies to retrieve URL (not possible in wkhtmltoimage)
        my $command = "wkhtmltoimage -q -f jpg \"${url}\" \"${a_file}\"";
        my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
        unless($success){
            Catmandu->log->error($stderr);
            die($stderr);
        }

        close $a_fh;

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
        versionable => "true",
        dsLabel => "screenshot in jpeg format",
        mimeType => "image/jpeg"
    );

    if( $datastream ) {
        if ( $self->force ) {

            $args{checksum} = md5_file($file);
            $args{checksumType} = "MD5";

            Catmandu->log->info("modifying datastream $dsID of object $pid");
            my $res = $self->fedora()->modifyDatastream(%args);
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

        my $res = $self->fedora()->addDatastream(%args);
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
        if(is_string($file) && -f $file ){
            Catmandu->log->debug("deleting file $file");
            unlink $file;
        }
    }
}

1;
