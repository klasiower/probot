package probot;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
extends qw(probot::generic::poe);

use probot::channel::manager;

has channel_manager => (
    isa     => 'probot::channel::manager',
    is      => 'ro',
    builder => 'build_channel_manager',
    lazy    => 1,
);
sub build_channel_manager {
    my ($self) = @_;
    $self->verbose('[build_channel_manager]');
    return probot::channel::manager->new({ name => $self->name .'/channel_manager' });
}

after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_started]');
    $self->channel_manager->add({
        type        => 'socket::listener',
        name        => 'net-in',
        prototype   => {
            port    => 6667,
        },
    });
};

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
