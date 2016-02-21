#################################################
# package test::generic::poe;
package test_connection_socket_listener;
use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;

extends qw(probot::generic::poe);

use probot::connection::socket::listener;

has ip  => (
    isa     => 'Str',
    is      => 'ro',
    default => sub { '127.0.0.1' },
);

has port => (
    isa     => 'Num',
    is      => 'ro',
    default => sub { 6667 },
);

has listener => (
    isa     => "Maybe[probot::connection::socket::listener]",
    is      => 'rw',
);

has listener_alias => (
    isa     => 'Str',
    is      => 'ro',
    builder => 'build_listener_alias',
    lazy    => 1,
);
sub build_listener_alias {
    my ($self) = @_;
    return $self->alias.'/listener';
}

has 'connection_id' => (
    isa         => 'Num',
    is          => 'rw',
    traits  => ['Counter'],
    default => 0,
    handles => {
        'inc_connection_id' => 'inc',
    },
);

after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_started] moep');
    $self->listener(probot::connection::socket::listener->new({
        ip      => $self->ip,
        port    => $self->port,
        alias   => $self->listener_alias,
        cb_add_connection   => {
            alias   => $self->alias,
            event   => 'ev_add_connection',
        },
        cb_del_connection   => {
            alias   => $self->alias,
            event   => 'ev_del_connection',
        },
        cb_get_input => {
            alias   => $self->alias,
            event   => 'ev_get_input',
        },
    }));
};

event ev_get_input => sub {
    my ($self, $kernel, $context) = @_[OBJECT, KERNEL, ARG0];
    $self->verbose(sprintf('[ev_get_input] connection_id:%s input:(%s)', $context->{connection_id}, $context->{input}));
    $kernel->post($self->listener_alias, 'ev_put_output', {
        connection_id   => $context->{connection_id},
        output          => sprintf('you gave me %s', $context->{input}),
    });
};

event ev_add_connection => sub {
    my ($self, $kernel, $context) = @_[OBJECT, KERNEL, ARG0];
    $self->verbose(sprintf('[ev_add_connection] socket_id:%s', $context->{socket_id}));

    return { connection_id => $self->inc_connection_id() }
};

event ev_del_connection => sub {
    my ($self, $kernel, $socket_id) = @_[OBJECT, KERNEL, ARG0];
    $self->verbose(sprintf('[ev_del_connection] socket_id:%s', $socket_id));
};

1;

__PACKAGE__->meta->make_immutable;
no MooseX::POE;
