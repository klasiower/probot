package probot;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
extends qw(probot::generic::poe);

use probot::connection::manager;
use probot::session::manager;

has connection_manager => (
    isa     => 'probot::connection::manager',
    is      => 'ro',
    builder => 'build_connection_manager',
    lazy    => 1,
);
sub build_connection_manager {
    my ($self) = @_;
    $self->verbose('[build_connection_manager]');
    return probot::connection::manager->new({ name => $self->name .'/connection_manager' });
}

has session_manager => (
    isa     => 'probot::session::manager',
    is      => 'ro',
    builder => 'build_session_manager',
    lazy    => 1,
);
sub build_session_manager {
    my ($self) = @_;
    $self->verbose('[build_session_manager]');
    return probot::session::manager->new({ name => $self->name .'/session_manager' });
}

after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_started]');
    $self->connection_manager->add({
        type        => 'socket::listener',
        name        => 'net-in',
        prototype   => {
            port    => 6667,
        },
        cb_new_connection => {
            alias   => $self->alias,
            event   => 'ev_new_connection',
        },
    });
};

event ev_new_connection => sub {
    my ($self, $kernel, $id) = @_[OBJECT, KERNEL, ARG0];
    $self->verbose(sprintf('[ev_new_connection] id:%s', $id));
};

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
