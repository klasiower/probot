package probot::session::manager;

use warnings;
use strict;
use Moose;
# use MooseX::POE;
use namespace::autoclean;
use probot::generic::factory;
use probot::generic::queue;
extends qw(probot::generic::poe);

has 'name'      => (
    isa         => 'Str',
    is          => 'rw',
    default     => sub { __PACKAGE__ }
);

## holds sessions indexed by session_id
has sessions => (
    isa     => 'Maybe[probot::generic::queue]',
    is      => 'rw',
    builder => 'build_sessions',
    lazy    => 1,
);
sub build_sessions {
    my ($self) = @_;
    $self->sessions(probot::generic::queue->new({
        name    => $self->alias . '/sessions',
        prefix  => 'session-',
    }));
}

has 'factory'   => (
    isa         => 'probot::generic::factory',
    is          => 'ro',
    lazy        => 1,
    builder     => 'build_factory'
);
sub build_factory {
    my ($self) = @_;
    return probot::generic::factory->new({
        name        => $self->name . '/factory',
        base_class  => 'probot::session',
    });
}

sub add {
    my ($self, $args) = @_;
    unless (defined $args)          { $self->error('[add] args undefined');       return undef; }
    unless (defined $args->{type})  { $self->error('[add] args->type undefined'); return undef; }
    my $session_id = $self->sessions->add();

    my $session;
    eval {
        $session = $self->factory->create(
            $args->{type}, {
                %{$args->{prototype} // {}}, (
                    name => $session_id,
                    type => $args->{type}
                )
            });
    };  if ($@) {
        my $e = $@;  chomp $e;
        $self->error(sprintf('[add] error creating session id:%s type:%s (%s)', $session_id, $args->{type}, $e));
        $self->sessions->del($session_id);
        return undef;
    }

    $self->sessions->set($session_id, { session => $session });
    return $session_id;
}

sub del {
    my ($self, $session_id) = @_;
    POE::Kernel->call($session_id, 'ev_shutdown');
    $self->sessions->del($session_id);
}

sub set {
    my ($self, $id, $args) = @_;
    $self->sessions->set($id, $args);
}

sub get {
    my ($self, $id) = @_;
    return $self->sessions->get($id);
}


sub shutdown {
    my ($self) = @_;
    $self->verbose(sprintf('[ev_shutdown] closing %i sessions', scalar keys %{$self->sessions->items()}));
    foreach my $id (keys %{$self->sessions->items()}) {
        $self->sessions->del($id);
    }
} 

# before ev_shutdown => sub {
#     my ($self, $kernel) = @_[OBJECT, KERNEL];
#     $self->shutdown();
# };

sub dump {
    my ($self) = @_;
    return $self->sessions->dump();
}

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
