package probot::session::manager;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
use probot::generic::factory;
extends qw(probot::generic::poe);

has 'name'      => (
    isa         => 'Str',
    is          => 'rw',
    default     => sub { __PACKAGE__ }
);

has 'sessions'  => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub { {} },
);

has 'session_nr' => (
    isa         => 'Num',
    is          => 'rw',
    traits  => ['Counter'],
    default => 0,
    handles => {
        'inc_session_nr' => 'inc',
    },
);

has 'factory'   => (
    isa         => 'probot::generic::factory',
    is          => 'ro',
    lazy        => 1,
    builder     => 'build_factory'
);

has 'keys'  => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub {{}},
);

has 'by_key'    => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub {{}},
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
    $self->inc_session_nr();
    my $session_id = $self->session_nr;

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
        return undef;
    }

    $self->sessions->{$session_id} = $session;
    foreach my $k (keys %$args) {
        if (exists $self->keys->{$k}) {
            $self->error(sprintf('[add][by_key][%s] %s = %s', $session_id, $k, $args->{$k}));
            $self->by_key->{$k}{$args->{$k}} = $session_id;
        }
    }
    return $session_id;
}

sub del {
    my ($self, $args) = @_;

    my $session_id;
    if (ref $args eq 'HASH') {
        my ($k, $v) = each %$args;
        $session_id = $self->by_key->{$k}{$v};
        $self->verbose(sprintf('[del][%s][by_key] %s = %s', $session_id, $k, $v));
    } else {
        $session_id = $args;
    }

    $self->verbose(sprintf('[del] deleting session_id:%s', $session_id));
    # $self->sessions->{$session_id}->shutdown();
    foreach my $k (keys %{$self->sessions->{$session_id}}) {
        if (exists $self->keys->{$k}) {
            my $v = $self->sessions->{$session_id}{$k};
            $self->verbose(sprintf('[del][%s][by_key] %s = %s', $session_id, $k, $v));
            delete $self->by_key->{$k}{$v};
        }
    }
    delete $self->sessions->{$session_id};
}

sub set {
    my ($self, $id, $args) = @_;

    foreach my $k (keys %$args) {
        my $v = delete $args->{$k};
        $self->verbose(sprintf('[set][%s] %s = %s', $id, $k, $v));
        $self->sessions->{$id}{$k} = $v;

        if (exists $self->keys->{$k}) {
            $self->verbose(sprintf('[set][%s][by_key] %s = %s', $id, $k, $v));
            $self->by_key->{$k}{$v} = $id;
        }
    }
}

sub get {
    my ($self, $id) = @_;
    return $self->sessions->{$id};
}


sub shutdown {
    my ($self) = @_;
    $self->verbose(sprintf('[ev_shutdown] closing %i sessions', scalar keys %{$self->sessions()}));
    foreach my $id (keys %{$self->sessions()}) {
        $self->del($id);
    }
} 

before ev_shutdown => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->shutdown();
};

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
