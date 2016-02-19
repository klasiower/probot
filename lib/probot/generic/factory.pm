package probot::generic::factory;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
with qw(probot::generic);

# generic factory interface

# class name prefix
has 'base_class' => (
    isa     => 'Str',
    is      => 'rw',
    default => 'probot',
);

# inline => 1 means;
# class has been defined within same file
has 'inline' => (
    isa     => 'Bool',
    is      => 'rw',
    default => 0,
);

sub create {
    my ($self, $type, $args) = @_;

    unless (defined $type) {
        $self->error('[create] type undefined');
        return undef;
    }

    my $class = (defined $self->base_class ? $self->base_class.'::' : '') . $type;

    unless ($self->inline) {
        # FIXME that's not very elegant (and not portable at all ...)
        my $path  = $class;  $path =~ s{::}{/}g;  $path .= '.pm';
        $self->verbose(sprintf('[create] type:%s class:%s path:%s', $type, $class, $path));
        eval {
            require $path;
        }; if ($@) {
            my $e = $@; chomp $e;
            $self->error("[create] can't load class file:$path error:($e)");
            return undef;
        }
    }

    # XXX check if exists
    # XXX copy arguments, don't pass them
    my $object = undef;
    eval {
        $args //= {};
        $object = $class->new($args);
    }; if ($@) {
        my $e = $@; chomp $e;
        $self->error("[create] can't instantiate class:$class error:($e)");
        return undef;
    }
    
    return $object;
}

__PACKAGE__->meta->make_immutable;
# no MooseX::POE;

1;
