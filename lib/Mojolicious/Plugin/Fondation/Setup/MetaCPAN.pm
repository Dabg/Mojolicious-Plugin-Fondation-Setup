package Mojolicious::Plugin::Fondation::Setup::MetaCPAN;

# ABSTRACT: MetaCPAN discovery for Fondation plugins

use Mojo::Base -base, -signatures;

our $VERSION = '0.01';

has base_url => 'https://fastapi.metacpan.org/v1';

=head1 NAME

Mojolicious::Plugin::Fondation::Setup::MetaCPAN — MetaCPAN discovery for Fondation plugins

=head1 SYNOPSIS

  my $mc = Mojolicious::Plugin::Fondation::Setup::MetaCPAN->new;

  $mc->discover_p($app)->then(sub ($plugins) {
      for my $p (@$plugins) {
          say "$p->{module_class} — $p->{abstract}";
          say "  installed: " . ($p->{installed} ? 'yes' : 'no');
      }
  });

=head1 METHODS

=head2 discover_p

  my $promise = $mc->discover_p($app);

Queries MetaCPAN for all releases whose distribution starts with
C<Mojolicious-Plugin-Fondation->. Deduplicates by distribution name
(showing the latest version only). Derives the Perl module class from
the distribution name.

Returns a L<Mojo::Promise> resolving to an arrayref of hashrefs:

  {
      distribution  => 'Mojolicious-Plugin-Fondation-Blog',
      version       => '0.01',
      abstract      => 'Blog plugin for Fondation',
      author        => 'DAB',
      date          => '2026-06-15',
      module_class  => 'Mojolicious::Plugin::Fondation::Blog',
      installed     => $bool,
  }

=cut

sub discover_p ($self, $app) {
    my $ua  = $app->ua;
    my $url = $self->base_url
        . '/release/_search?q=distribution:Mojolicious-Plugin-Fondation-*'
        . '&size=100&sort=date:desc';

    return $ua->get_p($url)->then(sub ($tx) {
        my $data = $tx->result->json;
        my $hits = $data->{hits}{hits} // [];

        my %seen;
        my @plugins;

        for my $hit (@$hits) {
            my $src = $hit->{_source} // {};

            my $dist = $src->{distribution} or next;
            next if $seen{$dist}++;  # latest version only (sorted by date desc)

            # Derive the plugin class from the distribution name:
            # Mojolicious-Plugin-Fondation-Foo-Bar → Mojolicious::Plugin::Fondation::Foo::Bar
            my $module_class = $dist;
            $module_class =~ s/^Mojolicious-Plugin-//;
            $module_class = "Mojolicious::Plugin::$module_class";
            $module_class =~ s/-/::/g;

            push @plugins, {
                distribution => $dist,
                version      => $src->{version} // '',
                abstract     => $src->{abstract}  // '',
                author       => $src->{author}    // '',
                date         => $src->{date}      // '',
                module_class => $module_class,
                installed    => $self->is_installed($module_class),
                dependencies => $self->_fondation_deps($src->{dependency}),
            };
        }

        return \@plugins;
    });
}

=head2 is_installed

  my $bool = $mc->is_installed('Mojolicious::Plugin::Fondation::Blog');

Returns true if the Perl class can be loaded via C<require>.

=cut

sub is_installed ($self, $class) {
    return 1 if $INC{ $class =~ s{::}{/}gr . '.pm' };
    return eval "require $class; 1" ? 1 : 0;
}

# Extract Fondation-level dependencies from CPAN runtime requirements.
# Filters modules starting with Mojolicious::Plugin::Fondation::,
# excluding Mojolicious::Plugin::Fondation itself (the loader).
sub _fondation_deps ($self, $deps) {
    return [] unless $deps && ref $deps eq 'ARRAY';
    my @deps;
    for my $d (@$deps) {
        next unless ($d->{phase} // '') eq 'runtime';
        next unless ($d->{module} // '') =~ /^Mojolicious::Plugin::Fondation::/;
        next if $d->{module} eq 'Mojolicious::Plugin::Fondation';
        push @deps, $d->{module};
    }
    return \@deps;
}

1;

=encoding UTF-8

=head1 SEE ALSO

L<Mojolicious::Plugin::Fondation::Setup>,
L<https://metacpan.org>

=cut
