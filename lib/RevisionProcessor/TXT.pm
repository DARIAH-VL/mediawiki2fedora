package RevisionProcessor::TXT;
use Catmandu::Sane;
use Catmandu::Util qw(:is);
use Catmandu;
use Moo;
use MediaWikiFedora qw(to_tmp_file json);

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
        #write content to tempfile
        $self->files([
            to_tmp_file($revision->{'*'})
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
    my $dsLabel = substr($revision->{parsedcomment} // "",0,255);
    utf8::encode($dsLabel);

    my %args = (
        pid => $pid,
        dsID => $dsID,
        file => $file,
        versionable => "true",
        dsLabel => $dsLabel,
        mimeType => $revision->{contentformat}."; charset=utf-8",
        checksumType => "SHA-1",
        checksum => $revision->{sha1}
    );
    if( $datastream ) {
        if ( $self->force ) {
            Catmandu->log->info("object $pid: modify datastream $dsID");
            if($revision->{sha1} eq $datastream->{profile}->{dsChecksum}){
                Catmandu->log->info("nothing todo");
            }else{
                my $res = $self->fedora()->modifyDatastream(%args);
                unless( $res->is_ok() ){
                    Catmandu->log->error($res->raw());
                    die($res->raw());
                }
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
