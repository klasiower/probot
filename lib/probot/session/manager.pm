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
    # { type, name, prototype }
#     for (qw(type name)) {
#         unless (defined $args->{$_}) {
#             $self->error(sprintf('[add] config error, attribute %s missing', $_));
#             return undef;
#         }
#     }
# 
#     if (exists $self->sessions->{$args->{name}}) {
#         $self->warn(sprintf('[add] overwriting session name:%s type:%s', $args->{name}, $args->{type}));
#     }

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
    return $session_id;
}

sub del {
    my ($self, $session_id) = @_;

    $self->verbose(sprintf('[del] deleting session_id:%s', $session_id));
    $self->sessions->{$session_id}->shutdown();
    delete $self->sessions->{$session_id};
}

sub shutdown {
    my ($self) = @_;
    foreach my $session_id (%{$self->sessions()}) {
        $self->sessions->{$session_id}->shutdown();
    }
} 

before ev_shutdown => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose(sprintf('[ev_shutdown] closing %i sessions', scalar keys %{$self->sessions()}));
    foreach my $id (keys %{$self->sessions()}) {
        $self->del($id);
    }
};

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;


