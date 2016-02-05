package probot::channel::socket::listener;

use warnings;
use strict;
use MooseX::POE;
use IO::Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);

use namespace::autoclean;
extends qw(probot::channel);

has port => (
    isa         => 'Int',
    is          => 'ro',
    required    => 1,
);

has ip => (
    isa         => 'Str',
    is          => 'ro',
    default     => '127.0.0.1',
);
has tcp_server => (
    isa         => 'Maybe[POE::Wheel::SocketFactory]',
    is          => 'rw'
);
has tcp_server_alias  => (
    isa         => 'Str',
    is          => 'ro',
    lazy        => 1,
    builder     => 'build_tcp_server_alias',
);
sub build_tcp_server_alias {
    my ($self) = @_;
    return $self->alias . '/tcp_server',
}
# sockets, indexed by POE wheel ID
has sockets => (
    isa     => 'Maybe[HashRef]',
    default => sub { {} },
    is      => 'ro',
);

after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_started]');

    eval {

        $self->tcp_server(POE::Wheel::SocketFactory->new(
            BindPort        => $self->port,
            # Alias           => $self->tcp_server_alias,
            SuccessEvent    => "ev_connected",
            FailureEvent    => "ev_server_error",
        ));
    };  if ($@) {
        my $e = $@;  chomp $e;
        $self->error(sprintf('[ev_started] error spawning tcp_server on %s:%s (%s)', $self->ip, $self->port, $e));
        return undef;
    }
    $self->debug(sprintf('[ev_started] spawning tcp_server alias:%s on %s:%s', $self->tcp_server_alias, $self->ip, $self->port));
};

event ev_connected => sub {
    my ($self, $kernel, $heap, $socket, $remote_ip_packed, $remote_port) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1, ARG2];
    # For INET sockets, $_[ARG1] and $_[ARG2] hold the socket's remote
    # address and port, respectively.  The address is packed; see
    my $remote_ip = inet_ntoa($remote_ip_packed);
    my $io_wheel = POE::Wheel::ReadWrite->new(
      Handle        => $socket,
      InputEvent    => "ev_client_input",
      ErrorEvent    => "ev_client_error",
    );
    $self->sockets->{$io_wheel->ID} = $io_wheel;
    $self->verbose(sprintf('[ev_connected][%s:%s] id:%s', $remote_ip, $remote_port, $io_wheel->ID));
};

event ev_client_input => sub {
    my ($self, $kernel, $input, $id) = @_[OBJECT, KERNEL, ARG0, ARG1];
    # $self->verbose(sprintf('[ev_got_input][%s:%s] id:%s %s', $heap->{remote_ip}, $heap->{remote_port}, $id, $input));
    $self->verbose(sprintf('[ev_got_input] id:%s %s', $id, $input));

#       on_client_input => sub {
#         # Handle client input.
#         my ($input, $wheel_id) = @_[ARG0, ARG1];
#         $input =~ tr[a-zA-Z][n-za-mN-ZA-M]; # ASCII rot13
#         $_[HEAP]{client}{$wheel_id}->put($input);
#       },
};

event ev_client_error => sub {
    my ($self, $kernel, $operation, $errnum, $errstr, $id) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2, ARG3];
    if ($operation eq 'read' and 0 == $errnum) {
        $self->debug(sprintf('[ev_client_error] id:%s closed connection', $id));
        delete $self->sockets->{$id};
        return;
    }
    $self->error(sprintf('[ev_client_error] id:%s operation:%s errnum:%s errstr:%s', $id, $operation, $errnum, $errstr));
};

event ev_server_error => sub {
    my ($self, $kernel, $operation, $errnum, $errstr) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2];
    $self->error(sprintf('[ev_server_error] operation:%s errnum:%s errstr:%s', $operation, $errnum, $errstr));
    $kernel->yield('ev_shutdown');
},

before ev_shutdown => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose(sprintf('[ev_shutdown] closing %i sockets', scalar keys %{$self->sockets()}));
    # $kernel->alias_resolve($self->tcp_server_alias) && $kernel->call($self->tcp_server_alias, 'shutdown');
    foreach my $id (keys %{$self->sockets()}) {
        # $self->verbose(sprintf('[ev_shutdown] deleting socket id:%s', $id));
        delete $self->sockets->{$id};
    }
    $kernel->alias_resolve($self->tcp_server_alias) && $kernel->alias_remove($self->tcp_server_alias);
    $self->tcp_server(undef);
};

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
