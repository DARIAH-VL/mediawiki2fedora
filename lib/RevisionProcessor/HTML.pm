package RevisionProcessor::HTML;
use Catmandu::Sane;
use Moo;
use Catmandu::Util qw(:is);
use MediaWikiFedora qw(to_tmp_file json wiki2html);

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
