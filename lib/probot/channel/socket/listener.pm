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

after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_started]');

    eval {
        POE::Component::Server::TCP->new(
            Port                => $self->port,
            Alias               => $self->tcp_server_alias,
            ClientConnected     => 'ev_connected',
            ClientInput         => 'ev_got_input',
            ClientDisconnected  => 'ev_disconnected',
        );
    };  if ($@) {
        my $e = $@;  chomp $e;
        $self->error(sprintf('[ev_started] error spawning tcp_server on %s:%s (%s)', $self->ip, $self->port, $e));
        return undef;
    }
    $self->debug(sprintf('[ev_started] spawning tcp_server alias:%s on %s:%s', $self->tcp_server_alias, $self->ip, $self->port));
};

event ev_connected => sub {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $self->verbose(sprintf('[ev_connected][%s:%s]', $heap->{remote_ip}, $heap->{remote_port}));
};

event ev_got_input => sub {
    my ($self, $kernel, $heap, $input) = @_[OBJECT, KERNEL, HEAP, ARG0];
    $self->verbose(sprintf('[ev_got_input][%s:%s] %s', $heap->{remote_ip}, $heap->{remote_port}, $input));
    $kernel->call($self->tcp_server_alias, 'shutdown');
};

before ev_shutdown => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_shutdown]');
    $kernel->alias_resolve($self->tcp_server_alias) && $kernel->call($self->tcp_server_alias, 'shutdown');
};

  POE::Session->create(
    inline_states => {
      _start => sub {
        # Start the server.
        $_[HEAP]{server} = POE::Wheel::SocketFactory->new(
          BindPort => 12345,
          SuccessEvent => "on_client_accept",
          FailureEvent => "on_server_error",
        );
      },
      on_client_accept => sub {
        # Begin interacting with the client.
        my $client_socket = $_[ARG0];
        my $io_wheel = POE::Wheel::ReadWrite->new(
          Handle => $client_socket,
          InputEvent => "on_client_input",
          ErrorEvent => "on_client_error",
        );
        $_[HEAP]{client}{ $io_wheel->ID() } = $io_wheel;
      },
      on_server_error => sub {
        # Shut down server.
        my ($operation, $errnum, $errstr) = @_[ARG0, ARG1, ARG2];
        warn "Server $operation error $errnum: $errstr\n";
        delete $_[HEAP]{server};
      },
      on_client_input => sub {
        # Handle client input.
        my ($input, $wheel_id) = @_[ARG0, ARG1];
        $input =~ tr[a-zA-Z][n-za-mN-ZA-M]; # ASCII rot13
        $_[HEAP]{client}{$wheel_id}->put($input);
      },
      on_client_error => sub {
        # Handle client error, including disconnect.
        my $wheel_id = $_[ARG3];
        delete $_[HEAP]{client}{$wheel_id};
      },
    }
  );

  POE::Kernel->run();
  exit;

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
