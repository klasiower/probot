package probot::channel::manager;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
use probot::generic::factory;
extends qw(probot::generic);

has 'name'      => (
    isa         => 'Str',
    is          => 'rw',
    default     => sub { __PACKAGE__ }
);

has 'channels'  => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub { {} },
);

has 'factory'   => (
    isa         => 'probot::generic::factory',
    is          => 'ro',
    lazy        => 1,
    builder     => 'build_factory'
);
sub build_factory {
    my ($self) = @_;
    return probot::generic::factory->new({
        name        => $self->name . '/factory',
        base_class  => 'probot::channel',
    });
}

sub add {
    my ($self, $args) = @_;
    # { type, name, prototype }
    for (qw(type name)) {
        unless (defined $args->{$_}) {
            $self->error(sprintf('[add] config error, attribute %s missing', $_));
            return undef;
        }
    }

    if (exists $self->channels->{$args->{name}}) {
        $self->warn(sprintf('[add] overwriting channel name:%s type:%s', $args->{name}, $args->{type}));
    }

    my $channel;
    eval {
        $channel = $self->factory->create(
            $args->{type}, {
                %{$args->{prototype} // {}}, (
                    name => $args->{name},
                    type => $args->{type}
                )
            });
    };  if ($@) {
        my $e = $@;  chomp $e;
        $self->error(sprintf('[add] error creating channel name:%s type:%s (%s)', $args->{name}, $args->{type}, $e));
        return undef;
    }

    $self->channels->{$args->{name}} = $channel;
    return $channel;
}


__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;


