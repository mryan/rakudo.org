#!/usr/bin/env perl

use lib qw<lib>;
use Mojolicious::Lite;
use Mojo::UserAgent;
use Mojo::File qw/path/;
use Mojo::Util qw/trim  xml_escape/;
use Time::Moment;
use RakudoOrg::Posts;

my $posts = RakudoOrg::Posts->new;
my $ua = Mojo::UserAgent->new;

app->config({ hypnotoad => { listen => ['http://*:4242'], proxy => 1 } });

plugin 'AssetPack' => { pipes => [qw/Sass  JavaScript  Combine/] };
app->asset->process('app.css' => qw{
    https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css

    sass/open-iconic-bootstrap.css
    sass/main.scss
});
app->asset->process('app.js' => qw{
    https://code.jquery.com/jquery-3.2.1.slim.min.js
    https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.12.9/umd/popper.min.js
    https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/js/bootstrap.min.js

    js/platform.js
    js/main.js
});

### Routes
get '/' => sub {
    my $self = shift;
    $self->stash(body_class => 'home');
}, => 'home';
get $_ for qw{/about /bugs /docs /files /people};
get '/files/star' => 'files-star';
get '/files/star/windows' => 'files-star-windows';
get '/files/star/source'  => 'files-star-source';

get '/downloads/star/rakudo-star-latest-x86_64%20(JIT).msi'
    => 'latest-star-windows-64';
get '/downloads/star/rakudo-star-latest-x86 (no JIT).msi'
    => 'latest-star-windows-32';

get '/people/irc' => sub {
    shift->redirect_to('https://webchat.freenode.net/?channels=#perl6');
} => 'people-irc';
get '/people/irc-dev' => sub {
    shift->redirect_to('https://webchat.freenode.net/?channels=#perl6-dev');
} => 'people-irc-dev';

get '/post/#post' => sub {
    my $c = shift;
    my ($meta, $html) = $posts->load($c->param('post'));
    $html or return $c->reply->not_found;

    $c->stash(%$meta, post => $html, title => $meta->{title});
} => 'post';

any $_ => sub {
    my $c = shift;
    my $posts = [ map +{ %$_ }, @{ $posts->all } ];
    $_->{date} = blog_date_to_feed_date($_->{date}) for @$posts;

    my $blog_last_updated_date = $posts->[0]{date};
    $c->stash(
        posts       => $posts,
        last_update => $blog_last_updated_date,
        template    => 'feed',
        format      => 'xml',
    );
}, ($_ eq '/feed' ? 'feed' : ())
    for '/feed', '/feed/', '/feed/index', '/atom', '/atom/', '/atom/index';

get '/pull/*password' => sub {
    my $c = shift;

    return $c->reply->not_found
        unless $c->param('password') eq trim path('pull-password')->slurp;

    $c->render(
        text   => "Pulled!\n" . `git pull`,
        format => 'txt',
    );
};

helper third_party => sub {
    my ($self, $text, $url) = @_;
    q|<a data-toggle="tooltip" href="| . xml_escape($url) . q|"|
    . q| title="⚠ This package was prepared by a 3rd party,|
    . q| not the core Rakudo team"><span class="oi oi-people"></span>|
    . q| | . xml_escape($text) . q|</a>|;
},
helper contribute => sub {
    my $self = shift;
    q|<a href="| . $self->url_for('people') . q|" data-toggle="tooltip"|
    . q| title="Would you like to help us fix that? Contribute ♥"|
    . q| class="text-primary"><span class="oi oi-wrench"></span></a>|
};
helper p6 => sub { '<span class="nb">Perl 6</span>' };
helper nav_active => sub {
    my ($self, $nav) = @_;
    $self->url_for('current')->to_abs eq $self->url_for($nav)->to_abs
        ? ' active' : ''
};
helper posts => sub { $posts->all };
helper items_in => sub {
        my ($c, $what ) = @_;
        return unless defined $what;
        $what = $c->stash($what) // [] unless ref $what;
        return @$what;
    };

app->start;

sub blog_date_to_feed_date {
    my $date = shift;
    return Time::Moment->from_string("${date}T00:00:00Z")
        ->strftime("%a, %d %b %Y %H:%M:%S %z");
}

