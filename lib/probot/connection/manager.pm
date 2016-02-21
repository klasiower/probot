package probot::connection::manager;

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

has 'connections'  => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub { {} },
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
        base_class  => 'probot::connection',
    });
}

has 'cb_new_connection' => (
    isa         => 'HashRef',
    is          => 'ro',
    required    => 1,
);

sub add {
    my ($self, $args) = @_;
    # { type, name, prototype }
    for (qw(type name)) {
        unless (defined $args->{$_}) {
            $self->error(sprintf('[add] config error, attribute %s missing', $_));
            return undef;
        }
    }

    if (exists $self->connections->{$args->{name}}) {
        $self->warn(sprintf('[add] overwriting connection name:%s type:%s', $args->{name}, $args->{type}));
    }

    my $connection;
    eval {
        $connection = $self->factory->create(
            $args->{type}, {
                %{$args->{prototype} // {}}, (
                    name => $args->{name},
                    type => $args->{type},
                    cb_new_connection   => {
                        alias   => $self->alias,
                        event   => 'ev_new_connection',
                    },
                )
            });
    };  if ($@) {
        my $e = $@;  chomp $e;
        $self->error(sprintf('[add] error creating connection name:%s type:%s (%s)', $args->{name}, $args->{type}, $e));
        return undef;
    }

    $self->connections->{$args->{name}} = $connection;
    return $connection;
};

event ev_new_connection => sub {
    my ($self, $kernel, $id) = @_[OBJECT, KERNEL, ARG0];
    $self->verbose(sprintf('[ev_new_connection] id:%s', $id));
    $kernel->post($self->cb_new_connection->alias, $self->cb_new_connection->event, $id);
};

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;


