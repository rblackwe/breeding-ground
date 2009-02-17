package Socialtext::Routes;
use strict;
use warnings;
use Carp qw(croak);
use Tie::IxHash;

sub new {
    my ($class, @routes) = @_;
    my $self = bless({}, ref($class) || $class);
    $self->routes_map(@routes);
    return $self;
}

sub routes_map {
    my ($self, @routes) = @_;
    if (@routes) {
        $self->{routes_map} = Tie::IxHash->new(@routes);
    }
    $self->{routes_map} ||= Tie::IxHash->new;
    return $self->{routes_map};
}

sub append_routes {
    my ($self, @routes) = @_;
    croak 'Odd number of elements given to append_routes' if @routes%2;
    $self->{routes_map}->Push(@routes);
}

sub run {
    my ($self, $path) = @_;
    for my $route ($self->routes_map->Keys) {
        my $regex = join "\\/",
                    map {/^:/ ? '([^/]*)' : quotemeta $_}
                    split m{/}, $route;
        if ($path =~ $regex) {
            return $self->_apply_match($route);
        }
    }
    croak "run(): No route matched $path";
}

# Various _apply_match(String $route)
#
# Check if any of the routes in the routing map match $route.  If so, pull out
# the variables, and call the code reference passing in the hash.
sub _apply_match {
    my ($self, $route) = @_;
    my @matches = $self->_get_matches;
    my @vars = map {s/^://; $_} grep /^:/, split m{/}, $route;
    my %hash; 
    @hash{@vars} = @matches;
    return $self->routes_map->FETCH($route)->(%hash);
}

# List _get_matches(void)
#
# Grabs the values of $1, $2, etc. as set by the last regular expression to
# run in the current dyanamic scope.  This of course exploits that $1, $2,
# etc. and @+ are dynamically scoped.  The list of matches is returned where
# the array values are $1, $2, $3, etc.
sub _get_matches {
    my $self = shift;
    no strict 'refs'; # For the $$_ symbolic reference below.
    return map $$_, (1 ..  scalar(@+)-1);  # See "perlvar" for @+.
}

1;
__END__

=head1 NAME

Socialtext::Routes  - A simple implementation of Ruby on Rails type routes.

=head1 SYNOPSIS

    my $obj = Socialtext::Routes->new(
        '/data/workspaces/:ws/pages/:page', => \&do_thing,
        # ... other routes here ...
    );

    $obj->run("/data/workspaces/cows/pages/good"); # prints "cows good"

    sub do_thing {
        my %vars = @_;
        print $vars{ws} . " " . $vars{page} . "\n";
    }

=head1 DESCRIPTION

Ruby on Rails has this concept of routes.  Routes are URI path info templates
which are tied to specific code (i.e. Controllers and Actions in Rails).  That
is routes consist of key value pairs, called the route map, where the key is
the path info template and the value is a code reference.

A template is of the form: C</foo/:variable/bar> where variables are always
prefaced with a colon.  When a given path is passed to C<run()> the code
reference which the template maps to will be passed a hash where the keys are
the variable names (sans colon) and the values are what was specified in place
of the variables.

The route map is ordered, so the most specific matching template is used and
so you should order your templates from least generic to most generic.

=head1 METHODS

=head2 new(%routes)

Create a new L<Socialtext::Routes> object and seed the routes map with the key
value pairs passed in.  The keys are URI templates (see above) and the values
are code references.

=head2 routes_map([%routes])

Returns the current routing map object.  If C<%routes> is passed in then the
routing map is reset with those routes.

=head2 append_routes(%routes)

Apped the listed routes to the current routing map.

=head2 run($path)

Cycles through the templates in the routing map and if any of them match the
code reference is called and passed a hash.  The place holders in the template
are the keys in the hash and the values are what's stored in C<$path> that
corresponds to the placeholders.

=head1 COPYRIGHT

Copyright 2006, Socialtext Inc.

=cut
