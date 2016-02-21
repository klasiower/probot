#################################################
# package test::generic::poe;
package test_generic_poe;
use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;

extends qw(probot::generic::poe);

after ev_started => sub {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->verbose('[ev_started]');
};

1;

__PACKAGE__->meta->make_immutable;
no MooseX::POE;
