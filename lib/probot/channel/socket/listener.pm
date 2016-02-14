package probot::channel::socket::listener;

use warnings;
use strict;
use MooseX::POE;
use IO::Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);

use namespace::autoclean;
extends qw(probot::channel);

# use probot::session::manager;
use probot::generic::queue;

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

# has session_manager => (
#     isa     => 'Maybe[probot::session::manager]',
#     is      => 'rw',
# );

has socket_queue => (
    isa     => 'Maybe[probot::generic::queue]',
    is      => 'rw',
);

has session_timeout => (
    isa     => 'Maybe[Num]',
    is      => 'rw',
    default => 60,
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

#     $self->session_manager(probot::session::manager->new({
#         alias   => $self->alias . '/session_manager',
#         keys        => {
#             wheel_id    => 1,
#         },
#     }));
    $self->socket_queue(probot::generic::queue->new({
        name    => $self->alias . '/socket_queue',
        keys        => {
            wheel_id    => 1,
        },
    }));
    $self->debug(sprintf('[ev_started] spawning tcp_server alias:%s on %s:%s', $self->tcp_server_alias, $self->ip, $self->port));
};

event ev_connected => sub {
    my ($self, $kernel, $heap, $socket, $remote_ip_packed, $remote_port) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1, ARG2];
    # For INET sockets, $_[ARG1] and $_[ARG2] hold the socket's remote
    # address and port, respectively.  The address is packed; see
    my $remote_ip = inet_ntoa($remote_ip_packed);

#     my $session_id = $self->session_manager->add({
#         type        => 'generic',
#     });
#     $self->session_manager->set($session_id, {
#         timeout     => $self->session_timeout,
#         remote_ip   => $remote_ip,
#         remote_port => $remote_port,
#         wheel       => POE::Wheel::ReadWrite->new(
#             Handle        => $socket,
#             InputEvent    => "ev_client_input",
#             ErrorEvent    => "ev_client_error",
#         ),
#     });
    my $session_id = $self->socket_queue->add({
        type        => 'generic',
    });
    $self->socket_queue->set($session_id, {
        timeout     => $self->session_timeout,
        remote_ip   => $remote_ip,
        remote_port => $remote_port,
        wheel       => POE::Wheel::ReadWrite->new(
            Handle        => $socket,
            InputEvent    => "ev_client_input",
            ErrorEvent    => "ev_client_error",
        ),
    });
#     $self->session_manager->set($session_id, { wheel_id => $self->session_manager->get($session_id)->{wheel}->ID });
#     $self->verbose(sprintf('[ev_connected][%s:%s] wheel_id:%s',
#         $remote_ip, $remote_port, $self->session_manager->get($session_id)->{wheel}->ID,
#     ));
    $self->socket_queue->set($session_id, { wheel_id => $self->socket_queue->get($session_id)->{wheel}->ID });
    $self->verbose(sprintf('[ev_connected][%s:%s] wheel_id:%s',
        $remote_ip, $remote_port, $self->socket_queue->get($session_id)->{wheel}->ID,
    ));
};

event ev_client_input => sub {
    my ($self, $kernel, $input, $id) = @_[OBJECT, KERNEL, ARG0, ARG1];
    $self->verbose(sprintf('[ev_client_input] wheel_id:%s %s', $id, $input));
};

event ev_client_error => sub {
    my ($self, $kernel, $operation, $errnum, $errstr, $id) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2, ARG3];
    if ($operation eq 'read' and 0 == $errnum) {
        $self->debug(sprintf('[ev_client_error] wheel_id:%s closed connection', $id));
        # $self->session_manager->del({ wheel_id => $id });
        $self->socket_queue->del({ wheel_id => $id });
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
    # $self->session_manager->shutdown();
    foreach my $s (keys %{$self->socket_queue->items}) { $self->socket_queue->del($s) }
    map { $self->verbose(sprintf('[ev_shutdown][socket_queue] %s', $_)) } split /\n/, $self->socket_queue->dump;
    $kernel->alias_resolve($self->tcp_server_alias) && $kernel->alias_remove($self->tcp_server_alias);
    $self->tcp_server(undef);
};

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
