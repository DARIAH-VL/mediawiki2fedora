package RevisionProcessor::SCREENSHOT_PNG;
use Catmandu::Sane;
use Catmandu::Util qw(:is :array);
use Catmandu;
use Moo;
use MediaWikiFedora qw(to_tmp_file mediawiki :utils);
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

        my $ua = mediawiki()->{ua};
        my $cookie_jar = $ua->cookie_jar();
        my($c_fh,$c_file) = tempfile(UNLINK => 1,EXLOCK => 0);
        my $phantom_cookie_jar = new_cookie_jar("PhantomJS",$c_file);
        clone_cookies($cookie_jar,$phantom_cookie_jar);

        my($a_fh,$a_file) = tempfile(UNLINK => 1,EXLOCK => 0,SUFFIX => ".png");
        my $url = $is_last ? $page->{_url}."?viewertype=js" : $revision->{_url}."&viewertype=js";
        my $command = "./bin/phantomjs --cookies-file=\"${c_file}\" bin/js/url2file.js \"${url}\" \"${a_file}\"";
        my($stdout,$stderr,$success,$exit_code) = capture_exec($command);

        close $c_fh;
        unlink($c_file) if -f $c_file;

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
        dsLabel => "screenshot in png format",
        mimeType => "image/png"
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
        next unless is_string $file;
        if( -f $file ){
            Catmandu->log->debug("deleting file $file");
            unlink $file;
        }
    }
}

1;
