package probot::generic::poe;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
# use FindBin;
# use lib $FindBin::Bin.'/../lib';
# require qw(probot/generic.pm);
use MooseX::NonMoose;
extends qw(probot::generic);

# light wrapper for a POE::Session
# has some nifty features:
# * catches SIGINT and calls ev_shutdown
# * provides some housekeeping for alarm-timers

has 'name'              => ( isa => 'Str',              is => 'rw', required => 0 );
has 'alias'             => ( isa => 'Str',              is => 'rw', required => 0 );
has 'is_shutting_down'  => ( isa => 'Bool',             is => 'rw', default  => 0 );
has 'alarms'            => ( isa => 'Maybe[HashRef]',   is => 'rw', default  => sub {{}} );

sub BUILD {
    my ($self, $args) = @_;
    die 'needs name or alias' unless (defined $self->name or defined $self->alias);
    unless (defined $self->name)  { $self->name($self->alias) }
    unless (defined $self->alias) { $self->alias($self->name) }
    $self->verbose(sprintf('[probot::generic::poe::BUILD] name:%s alias:%s', $self->name, $self->alias));
    return $self;
}

after START => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $kernel->alias_set($self->alias);
    $kernel->sig('INT',  'ev_sig_int');
    # $kernel->sig('CHLD', 'ev_sig_child');
    $self->verbose(sprintf('[probot::generic::poe::START] alias:%s', $self->alias));
    $kernel->yield('ev_started');
};

event ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
};

event _default => sub {
    my ($self, $kernel, $session, $event, $args) = @_[OBJECT, KERNEL, SESSION, ARG0 .. $#_];
    my $alias = $session->[0]{alias};
    $self->error(sprintf('[probot::generic::poe::ev_default] Session %s (alias:%s) caught unhandled event %s with (%s)', $session->ID, $alias, $event, "@$args"));
};

event _child => sub {
    my ($self, $session, @args) = @_[OBJECT, SESSION, ARG0 .. $#_];
    $self->debug(sprintf('[_child] Session %s (alias:%s) with (%s)', $session->ID, $session->[0]{alias}, (join ' ', @args)));
};
 
event ev_sig_child => sub {
    my ($self, $session, @args) = @_[OBJECT, SESSION, ARG0 .. $#_];
    $self->debug(sprintf('[ev_sig_child] Session %s (alias:%s) with (%s)', $session->ID, $session->[0]{alias}, (join ' ', @args)));
};
 
event _stop => sub {
    my ($self, $event, $args) = @_[OBJECT, ARG0, ARG1];
    $self->debug("[_stop]");
};

event ev_sig_int => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->debug("[probot::generic::poe::ev_sig_int]");
    $kernel->sig_handled();
    unless ($self->is_shutting_down) {
        $kernel->call($self->alias, 'ev_shutdown');
    }
};

event ev_shutdown => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_shutdown]');
    $self->is_shutting_down(1);
    $self->del_all_alarms();
};

event ev_add_alarm => sub {
    my ($self, $kernel, $alarm) = @_[OBJECT, KERNEL, ARG0];
    # alarm_add EVENT_NAME, EPOCH_TIME [, PARAMETER_LIST]
    # my $session = (defined $alarm->{session} ? $alarm->{session} : $self->alias);
    unless (defined $alarm->{event}) {
        $self->error("[ev_add_alarm] event missing");
        exit 1;
    }
    unless (defined $alarm->{time}) {
        $self->error("[ev_add_alarm] time missing");
        exit 1;
    }
    if (exists $self->alarms->{$alarm->{event}}) {
        $self->verbose(sprintf('[ev_add_alarm] deleting existing alarm event:%s', $alarm->{event}));
        $self->del_alarm($alarm->{event});
    }
    $self->alarms->{$alarm->{event}} = $kernel->alarm_set($alarm->{event}, $alarm->{time}, $alarm->{args});
    $self->verbose(sprintf('[ev_add_alarm] event:%s time:%i id:%i args:(%s)',
        $alarm->{event}, $alarm->{time},
        $self->alarms->{$alarm->{event}},
        (defined $alarm->{args} ? $alarm->{args} : '')
    ));
};

event ev_del_alarm => sub {
    my ($self, $kernel, $name) = @_[OBJECT, KERNEL, ARG0];
    if (exists $self->alarms->{$name}) {
        $kernel->alarm_remove($self->alarms->{$name});
        $self->verbose(sprintf('[ev_del_alarm] event:%s id:%i', $name, $self->alarms->{$name}));
        delete $self->alarms->{$name};
    }
};

sub add_alarm {
    my ($self, $alarm) = @_;
    POE::Kernel->call($self->alias, 'ev_add_alarm', $alarm);
}

sub del_alarm {
    my ($self, $name) = @_;
    POE::Kernel->call($self->alias, 'ev_del_alarm', $name);
}

sub del_all_alarms {
    my ($self) = @_;
    map {
        $self->del_alarm($_);
    } keys %{$self->alarms}
}

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
