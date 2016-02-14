package probot::channel::socket::listener;

use warnings;
use strict;
use MooseX::POE;
use IO::Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);

use namespace::autoclean;
extends qw(probot::channel);

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

## holds tcp sockets indexed by wheel_id or socket_id or session_id
has socket_queue => (
    isa     => 'Maybe[probot::generic::queue]',
    is      => 'rw',
    builder => 'build_socket_queue',
    lazy    => 1,
);
sub build_socket_queue {
    my ($self) = @_;
    $self->socket_queue(probot::generic::queue->new({
        name    => $self->alias . '/socket_queue',
        prefix  => 'socket-',
        keys        => {
            wheel_id    => 1,
            session_id  => 1,
        },
    }));
}
# has session_timeout => (
#     isa     => 'Maybe[Num]',
#     is      => 'rw',
#     default => 60,
# );
# 

## holds sessions indexed by socket_id or session_id
has session_queue => (
    isa     => 'Maybe[probot::generic::queue]',
    is      => 'rw',
    builder => 'build_session_queue',
    lazy    => 1,
);
sub build_session_queue {
    my ($self) = @_;
    $self->session_queue(probot::generic::queue->new({
        name    => $self->alias . '/session_queue',
        prefix  => 'session-',
        keys        => {
            session_id  => 1,
            socket_id   => 1,
        },
    }));
}


#######################################################
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
        $self->error(sprintf('[ev_started] error spawning tcp_server on %s:%s (%s)',
            $self->ip, $self->port, $e
        ));
        return undef;
    }

    $self->debug(sprintf('[ev_started] spawning tcp_server alias:%s on %s:%s',
        $self->tcp_server_alias, $self->ip, $self->port
    ));
};

event ev_connected => sub {
    my ($self, $kernel, $heap, $socket, $remote_ip_packed, $remote_port) = @_[OBJECT, KERNEL, HEAP, ARG0, ARG1, ARG2];
    # For INET sockets, $_[ARG1] and $_[ARG2] hold the socket's remote
    # address and port, respectively.  The address is packed; see
    my $remote_ip = inet_ntoa($remote_ip_packed);

    my $socket_id = $self->add_socket({
        remote_ip   => $remote_ip,
        remote_port => $remote_port,
        socket      => $socket,
    });

    my $session_id = $self->add_session({
        socket_id   => $socket_id,
    });
    $self->socket_queue->set($socket_id, { session_id => $session_id });
    $self->verbose(sprintf('[ev_connected][%s:%s] wheel_id:%s socket_id:%s session_id:%s',
        $remote_ip, $remote_port, $self->socket_queue->get($socket_id)->{wheel}->ID, $socket_id, $session_id
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
        my $session_id = $self->socket_queue->get({ wheel_id => $id })->{session_id};
        $self->socket_queue->del({ wheel_id => $id });
        $self->session_queue->del($session_id);
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

    ## shutdown sessions
    foreach my $s (keys %{$self->session_queue->items}) { $self->session_queue->del($s) }
    map { $self->verbose(sprintf('[ev_shutdown][session_queue] %s', $_)) } split /\n/, $self->session_queue->dump;

    ## shutdown sockets
    foreach my $s (keys %{$self->socket_queue->items}) { $self->socket_queue->del($s) }
    map { $self->verbose(sprintf('[ev_shutdown][socket_queue] %s', $_)) } split /\n/, $self->socket_queue->dump;

    ## shutdown tcp server
    $kernel->alias_resolve($self->tcp_server_alias) && $kernel->alias_remove($self->tcp_server_alias);
    $self->tcp_server(undef);
};

sub add_socket {
    my ($self, $args) = @_;

    my $socket_id = $self->socket_queue->add({
        type        => 'generic',
    });
    eval {
        $self->socket_queue->set($socket_id, {
            remote_ip   => $args->{remote_ip},
            remote_port => $args->{remote_port},
            wheel       => POE::Wheel::ReadWrite->new(
                Handle        => $args->{socket},
                InputEvent    => "ev_client_input",
                ErrorEvent    => "ev_client_error",
            ),
        });
        $self->socket_queue->set($socket_id, { wheel_id => $self->socket_queue->get($socket_id)->{wheel}->ID });
        $self->verbose(sprintf('[add_socket][%s:%s] wheel_id:%s',
            $args->{remote_ip}, $args->{remote_port}, $self->socket_queue->get($socket_id)->{wheel}->ID,
        ));
    };  if ($@) {
        my $e = $@;  chomp $e;
        $self->error(sprintf('[add_socket][%s:%s] can\'t start wheel:(%s)',
            $args->{remote_ip}, $args->{remote_port}, $e
        ));
        $self->socket_queue->del($socket_id);
        return undef;
    }
    return $socket_id;
}

sub add_session {
    my ($self, $args) = @_;

    my $session_id = $self->session_queue->add({
        type        => 'generic',
    });
    eval {
        $self->session_queue->set($session_id, {
            socket_id   => $args->{socket_id},
        });
    };  if ($@) {
        my $e = $@;  chomp $e;
        $self->error(sprintf('[add_session] can\'t start session:(%s)',
            $e
        ));
        $self->session_queue->del($session_id);
        return undef;
    }
    return $session_id;
}


__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
