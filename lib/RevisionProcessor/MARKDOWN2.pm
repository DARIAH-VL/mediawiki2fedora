package RevisionProcessor::MARKDOWN2;
use Catmandu::Sane;
use Catmandu;
use Moo;
use Catmandu::Util qw(:is);
use IO::CaptureOutput qw(capture_exec);
use File::Temp qw(tempfile);
use MediaWikiFedora qw(to_tmp_file mediawiki);

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

    my $ua = mediawiki()->{ua};

    if ( !$datastream || $self->force ) {
        #write html content to tempfile
        my $url = $revision->{_url}."&action=render";
        my $res = $ua->get($url);
        unless ( $res->is_success() ) {
            die( $res->content() );
        }

        my $source_file = to_tmp_file($res->content(),":raw");

        #convert to markdown
        my($dest_fh,$dest_file) = tempfile(UNLINK => 1,EXLOCK => 0);
        my $command = "pandoc \"${source_file}\" -f html -t markdown -o \"${dest_file}\"";
        my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
        die($stderr) unless $success;

        #prevent error: too many open files
        close $dest_fh;

        $self->files([
            $dest_file,$source_file
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
    my $dsLabel = "MARKDOWN version of datastream HTML";
    utf8::encode($dsLabel);

    my %args = (
        pid => $pid,
        dsID => $dsID,
        file => $file,
        versionable => "true",
        dsLabel => $dsLabel,
        mimeType => "text/plain; charset=utf-8"
    );
    if( $datastream ) {
        if ( $self->force ) {
            Catmandu->log->info("object $pid: modify datastream $dsID");
            my $res = $self->fedora()->modifyDatastream(%args);
            unless( $res->is_ok() ){
                Catmandu->log->error($res->raw());
                die($res->raw());
            }
        }
    }
    else{
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
        if( is_string($file) && -f $file ){
            Catmandu->log->debug("deleting file $file");
            unlink $file;
        }
    }
}

1;
