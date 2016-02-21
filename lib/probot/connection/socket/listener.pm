package probot::connection::socket::listener;

use warnings;
use strict;
use MooseX::POE;
use IO::Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);

use namespace::autoclean;
extends qw(probot::connection);

use probot::generic::queue;
# use probot::connection::manager;

has port => (
    isa         => 'Num',
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

## holds tcp sockets indexed by wheel_id or socket_id or connection_id
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
            wheel_id        => 1,
            connection_id   => 1,
            socket_id       => 1, # redundant, thats also the main index
        },
    }));
}

# communication with upstream session
has cb_add_connection => (
    isa         => 'HashRef',
    is          => 'ro',
    required    => 1,
);

has cb_del_connection => (
    isa         => 'HashRef',
    is          => 'ro',
    required    => 1,
);

has cb_get_input => (
    isa         => 'HashRef',
    is          => 'ro',
    required    => 1,
);

#######################################################
after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_started]');

    # try to start TCP listener
    # FIXME implement retry / restart mechanism
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
    my $remote_ip = inet_ntoa($remote_ip_packed);

    # allocate socket
    my $socket_id = $self->add_socket({
        remote_ip   => $remote_ip,
        remote_port => $remote_port,
        socket      => $socket,
    });

    # inform parent connection manager and get connection_id
    my $connection_id = $self->add_connection({
        socket_id   => $socket_id
    });

    $self->verbose(sprintf('[ev_connected][%s:%s] wheel_id:%s socket_id:%s connection_id:%s',
        $remote_ip, $remote_port, $self->socket_queue->get($socket_id)->{wheel}->ID, $socket_id, $connection_id
    ));
};

event ev_client_input => sub {
    my ($self, $kernel, $input, $id) = @_[OBJECT, KERNEL, ARG0, ARG1];
    my $connection_id = $self->socket_queue->get({ wheel_id => $id })->{connection_id};
    $self->verbose(sprintf('[ev_client_input] wheel_id:%s connection_id:%s %s', $id, $connection_id, $input));
    $kernel->post($self->cb_get_input->{alias}, $self->cb_get_input->{event}, {
        connection_id => $connection_id, input => $input
    });
};

event ev_put_output => sub {
    my ($self, $kernel, $context) = @_[OBJECT, KERNEL, ARG0];
    my $socket = $self->socket_queue->get({ connection_id => $context->{connection_id} });
    unless (defined $socket) {
        $self->error(sprintf('[ev_put_output] connection_id:%s doesn\'t exist', $context->{connection_id}));
        return undef;
    }
    $self->verbose(sprintf('[ev_put_output][%s:%s] connection_id:%s %s',
        $socket->{remote_ip}, $socket->{remote_port}, $context->{connection_id}, $context->{output}
    ));
    $socket->{wheel}->put($context->{output});
};

event ev_client_error => sub {
    my ($self, $kernel, $operation, $errnum, $errstr, $id) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2, ARG3];
    if ($operation eq 'read' and 0 == $errnum) {
        # unbind socket <-> connection
        # and delete allocated queue items
        my $connection_id = $self->socket_queue->get({ wheel_id => $id })->{connection_id};
        my $socket_id     = $self->socket_queue->get({ wheel_id => $id })->{socket_id};
        $kernel->call($self->cb_del_connection->{alias}, $self->cb_del_connection->{event}, $connection_id);

        $self->socket_queue->del({ wheel_id => $id });

        $self->debug(sprintf('[ev_client_error] wheel_id:%s socket_id:%s connection_id:%s closed connection',
            $id, $socket_id, $connection_id
        ));
        return;
    }
    $self->error(sprintf('[ev_client_error] id:%s operation:%s errnum:%s errstr:%s', $id, $operation, $errnum, $errstr));
};


event ev_server_error => sub {
    my ($self, $kernel, $operation, $errnum, $errstr) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2];
    $self->error(sprintf('[ev_server_error] operation:%s errnum:%s errstr:%s', $operation, $errnum, $errstr));
    $kernel->yield('ev_shutdown');
};

before ev_shutdown => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];

    ## shutdown sockets
    foreach my $s (keys %{$self->socket_queue->items}) {
        my $connection_id = $self->socket_queue->get($s)->{connection_id};
        $kernel->call($self->cb_del_connection->{alias}, $self->cb_del_connection->{event}, $connection_id);
        $self->socket_queue->del($s)
    }
    # show leaks
    map { $self->verbose(sprintf('[ev_shutdown][socket_queue] %s', $_)) } split /\n/, $self->socket_queue->dump;

    ## shutdown tcp server
    $kernel->alias_resolve($self->tcp_server_alias) && $kernel->alias_remove($self->tcp_server_alias);
    $self->tcp_server(undef);
};

sub add_socket {
    my ($self, $args) = @_;

    # allocated socket_queue item
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
        # bind wheel_id to socket_id
        ## FIXME implement try/catch error handling
        $self->socket_queue->set($socket_id, { wheel_id  => $self->socket_queue->get($socket_id)->{wheel}->ID });
        $self->socket_queue->set($socket_id, { socket_id => $socket_id });
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

sub add_connection {
    my ($self, $context) = @_;
    my $kernel = $poe_kernel;

    my $socket = $self->socket_queue->get({ socket_id => $context->{socket_id} });
    # FIXME error handling if socket is not found
    $context = {
        remote_ip   => $socket->{remote_ip},
        remote_port => $socket->{remote_port},
        socket_id   => $context->{socket_id},
    };

    # inform parent connection manager and get connection_id
    my $connection = $kernel->call($self->cb_add_connection->{alias}, $self->cb_add_connection->{event}, $context);
    $self->socket_queue->set($context->{socket_id}, { connection_id => $connection->{connection_id} });

    $self->verbose(sprintf('[add_connection] %s connection_id:%s',
        ( join ' ', map { sprintf('%s:%s', $_, $context->{$_} // '') } keys %$context ), $connection->{connection_id}
    ));
    return $connection->{connection_id};
}

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
