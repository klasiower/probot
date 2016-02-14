package probot::channel::socket::listener;

use warnings;
use strict;
use MooseX::POE;
use IO::Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);

use namespace::autoclean;
extends qw(probot::channel);

use probot::generic::queue;
use probot::session::manager;

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

has session_manager => (
    isa     => 'probot::session::manager',
    is      => 'rw',
    builder => 'build_sesssion_manager',
    lazy    => 1,
);
sub build_sesssion_manager {
    my ($self) = @_;
    $self->session_manager(probot::session::manager->new({
        name    => $self->alias . '/session_manager',
    }));
};

has session_timeout => (
    isa     => 'Maybe[Num]',
    is      => 'rw',
    default => 60,
);

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
            socket_id   => 1,
        },
        ## callbacks
        cb_close    => { alias => $self->alias, event => 'ev_session_close'  },
        cb_output   => { alias => $self->alias, event => 'ev_session_output' },
    }));
}


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

    # allocate session and bind it to socket
    my $session_id = $self->session_manager->add({
        type        => 'generic',
        socket_id   => $socket_id,
    });

    # bind socket to session
    $self->socket_queue->set($socket_id, { session_id => $session_id });

    $self->verbose(sprintf('[ev_connected][%s:%s] wheel_id:%s socket_id:%s session_id:%s',
        $remote_ip, $remote_port, $self->socket_queue->get($socket_id)->{wheel}->ID, $socket_id, $session_id
    ));
};

event ev_client_input => sub {
    my ($self, $kernel, $input, $id) = @_[OBJECT, KERNEL, ARG0, ARG1];
    my $session_id = $self->socket_queue->get({ wheel_id => $id })->{session_id};
    $self->verbose(sprintf('[ev_client_input] wheel_id:%s session_id:%s %s', $id, $session_id, $input));
};

event ev_client_error => sub {
    my ($self, $kernel, $operation, $errnum, $errstr, $id) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2, ARG3];
    if ($operation eq 'read' and 0 == $errnum) {
        $self->debug(sprintf('[ev_client_error] wheel_id:%s closed connection', $id));

        # unbind socket <-> session
        # and delete allocated queue items
        my $session_id = $self->socket_queue->get({ wheel_id => $id })->{session_id};
        $self->socket_queue->del({ wheel_id => $id });
        $self->session_manager->del($session_id);
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

    ## shutdown sessions
    $self->session_manager->shutdown();
    # show leaks
    map { $self->verbose(sprintf('[ev_shutdown][session_manager] %s', $_)) } split /\n/, $self->session_manager->dump;

    ## shutdown sockets
    foreach my $s (keys %{$self->socket_queue->items}) { $self->socket_queue->del($s) }
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

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
