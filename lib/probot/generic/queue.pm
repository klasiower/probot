package probot::generic::queue;

use warnings;
use strict;
use Moose;
# just for dumping / debugging
use JSON;
use namespace::autoclean;
extends qw(probot::generic);

has 'name'      => (
    isa         => 'Str',
    is          => 'rw',
    default     => sub { __PACKAGE__ }
);

has 'items'  => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub { {} },
);

has 'item_id' => (
    isa         => 'Num',
    is          => 'rw',
    traits  => ['Counter'],
    default => 0,
    handles => {
        'inc_item_id' => 'inc',
    },
);

# hash keys used to index items
has 'keys'  => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub {{}},
);

# mappings key -> item_id
has 'by_key'    => (
    isa         => 'HashRef',
    is          => 'rw',
    default     => sub {{}},
);

has 'json'      => (
    isa         => 'JSON',
    is          => 'ro',
    builder     => 'build_json',
);
sub build_json {
    return JSON->new();
}

sub add {
    my ($self, $args) = @_;
    $self->inc_item_id();
    my $item_id = $self->item_id;

    my $item = { %{$args} };

    $self->items->{$item_id} = $item;
    foreach my $k (keys %$args) {
        if (exists $self->keys->{$k}) {
            $self->verbose(sprintf('[add][%s] key %s = %s', $item_id, $k, $args->{$k}));
            $self->by_key->{$k}{$args->{$k}} = $item_id;
        }
    }
    return $item_id;
}

sub del {
    my ($self, $args) = @_;

    my $item_id;
    if (ref $args eq 'HASH') {
        my ($k, $v) = each %$args;
        $item_id = $self->by_key->{$k}{$v};
        $self->verbose(sprintf('[del][%s] key %s = %s', $item_id, $k, $v));
    } else {
        $item_id = $args;
    }

    $self->verbose(sprintf('[del] deleting item_id:%s', $item_id));
    foreach my $k (keys %{$self->items->{$item_id}}) {
        if (exists $self->keys->{$k}) {
            my $v = $self->items->{$item_id}{$k};
            $self->verbose(sprintf('[del][%s] removing mapping key %s = %s', $item_id, $k, $v));
            delete $self->by_key->{$k}{$v};
        }
    }
    delete $self->items->{$item_id};
}

sub set {
    my ($self, $id, $args) = @_;

    foreach my $k (keys %$args) {
        my $v = delete $args->{$k};
        $self->verbose(sprintf('[set][%s] %s = %s', $id, $k, $v));
        $self->items->{$id}{$k} = $v;

        if (exists $self->keys->{$k}) {
            $self->verbose(sprintf('[set][%s] adding mapping key %s = %s', $id, $k, $v));
            $self->by_key->{$k}{$v} = $id;
        }
    }
}

sub get {
    my ($self, $id) = @_;
    return $self->items->{$id};
}

sub dump {
    my ($self) = @_;

    return $self->json->pretty->encode({
        keys    => $self->keys,
        by_key  => $self->by_key,
        items   => $self->items,
    });
}

__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;

