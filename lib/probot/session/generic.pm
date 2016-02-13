package probot::session::generic;

use warnings;
use strict;
use MooseX::POE;
use IO::Socket;
use POE::Wheel::ReadWrite;

use namespace::autoclean;
extends qw(probot::generic::poe);

has socket => (
    # isa         => 'IO::Socket',
    isa         => 'Maybe[GlobRef]',
    is          => 'rw',
    required    => 1,
);

has wheel => (
    isa     => 'Maybe[POE::Wheel::ReadWrite]',
    is      => 'rw',
);

has remote_ip => (
    isa         => 'Str',
    is          => 'ro',
    required    => 1,
);

has remote_port => (
    isa         => 'Num',
    is          => 'ro',
    required    => 1,
);

after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];

    $self->wheel(POE::Wheel::ReadWrite->new(
      Handle        => $self->socket,
      InputEvent    => "ev_client_input",
      ErrorEvent    => "ev_client_error",
    ));
    $self->verbose(sprintf('[ev_connected][%s:%s] wheel_id:%s',
        $self->remote_ip, $self->remote_port, $self->wheel->ID,
    ));
};

event ev_client_input => sub {
    my ($self, $kernel, $input, $id) = @_[OBJECT, KERNEL, ARG0, ARG1];
    $self->verbose(sprintf('[ev_got_input] wheel_id:%s %s', $id, $input));
};

event ev_client_error => sub {
    my ($self, $kernel, $operation, $errnum, $errstr, $id) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2, ARG3];
    if ($operation eq 'read' and 0 == $errnum) {
        $self->debug(sprintf('[ev_client_error] wheel_id:%s closed connection', $id));
        $self->shutdown();
        return;
    }
    $self->error(sprintf('[ev_client_error] id:%s operation:%s errnum:%s errstr:%s', $id, $operation, $errnum, $errstr));
};

sub shutdown {
    my ($self) = @_;
    my $wheel_id;  if (defined $self->wheel) { $wheel_id = $self->wheel->ID }
    $self->verbose(sprintf('[shutdown][%s:%s] wheel_id:%s',
        $self->remote_ip, $self->remote_port, ($wheel_id // ''),
    ));
    $self->socket(undef);
    $self->wheel(undef);
}

before ev_shutdown => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->shutdown();
};


__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
