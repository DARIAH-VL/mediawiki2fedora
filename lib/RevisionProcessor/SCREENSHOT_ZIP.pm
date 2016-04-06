package RevisionProcessor::SCREENSHOT_ZIP;
use Catmandu::Sane;
use Catmandu::Util qw(:is :array);
use Catmandu;
use Moo;
use MediaWikiFedora qw(to_tmp_file json);
use File::Basename;
use File::Path qw(rmtree);
use IO::CaptureOutput qw(capture_exec);
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Temp qw(tempfile tempdir);
use File::Copy qw(move);

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

        my $tempdir = tempdir(CLEANUP => 1,EXLOCK => 0);
        my $url = $is_last ? $page->{_url} : $revision->{_url};
        #ignore robots.txt, otherwise only page requisites for url without parameters are fetched
        my $command = "wget -e robots=off -U mozilla -nd -nH -P \"${tempdir}\" -q --adjust-extension --convert-links --page-requisites \"${url}\"";
        my($stdout,$stderr,$success,$exit_code) = capture_exec($command);
        #exit code 8 happens when one or more page requisites fail (often favicon.ico)
        $exit_code >>= 8;
        unless(array_includes([0,8],$exit_code)){
            Catmandu->log->error($stderr);
            die($stderr);
        }
        my @html_files = <${tempdir}/*.html>;
        if(@html_files){
            my $source = $html_files[0];
            my $dest = "${tempdir}/index.html";
            unless ( move( $source, $dest ) ) {
                Catmandu->log->error($!);
                die($!);
            }
            my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0);
            my $zip = Archive::Zip->new();
            my @files = <${tempdir}/*>;
            for my $file(@files){
                $zip->addFile($file,basename($file));
            }
            unless( $zip->writeToFileNamed( $a_file ) == AZ_OK ){
                Catmandu->log->error("unable to write to zip file $a_file");
                die("unable to write to zip file $a_file");
            }

            close $a_fh;

            $self->files([
                $a_file, $tempdir
            ]);
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

    my %args = (
        pid => $pid,
        dsID => $dsID,
        file => $file,
        versionable => "true",
        dsLabel => "html and prerequisites saved to zip",
        mimeType => "application/zip"
    );
    if( $datastream ) {
        if ( $self->force ) {
            Catmandu->log->info("modifying datastream $dsID of object $pid");
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
        next unless is_string $file;
        if( -f $file ){
            Catmandu->log->debug("deleting file $file");
            unlink $file;
        }
        elsif( -d $file ){
            Catmandu->log->debug("deleting directory $file");
            rmtree($file);
        }
    }
}

1;
