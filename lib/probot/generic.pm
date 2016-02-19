##########################################################
package probot::generic;
use warnings;
use strict;
use Moose::Role;
# use MooseX::POE;
use namespace::autoclean;

has 'name' => ( is => 'rw', required => 1 );

sub log {
    my ($self, $string) = @_;
    print STDERR $string,"\n";
}

sub debug {
    my ($self, $string) = @_;
    $self->log(sprintf('[DBG][%i][%s] %s', time(), $self->name, $string));
}

sub verbose {
    my ($self, $string) = @_;
    $self->log(sprintf('[VERB][%i][%s] %s', time(), $self->name, $string));
}

sub error {
    my ($self, $string) = @_;
    $self->log(sprintf('[ERR][%i][%s] %s', time(), $self->name, $string));
}

sub warn {
    my ($self, $string) = @_;
    $self->log(sprintf('[WARN][%i][%s] %s', time(), $self->name, $string));
}

# __PACKAGE__->meta->make_immutable;
# no MooseX::POE;

1;
