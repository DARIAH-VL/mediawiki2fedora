package RevisionProcessor;
use Catmandu::Sane;
use Moo::Role;

has page => (is => 'ro');
has revision => (is => 'ro');
has fedora => (is => 'ro');

has force => (is => 'ro');
has datastream => (
    is => 'ro',
    lazy => 1,
    builder => '_build_datastream'
);
has pid => (is => 'ro');
has dsID => (is => 'ro');

sub _build_datastream {
    my $self = $_[0];
    my $res = $self->fedora()->getDatastream(pid => $self->pid, dsID => $self->dsID);
    my $datastream;
    if ( $res->is_ok() ) {
        $datastream = $res->parse_content();
    }
    $datastream;
}

requires 'process';
requires 'insert';
requires 'cleanup';

1;
