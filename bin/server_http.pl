#!/usr/bin/env perl
use warnings;
use strict;

use Mojolicious::Plugin::Authentication;
use Mojolicious::Lite;
use File::Find;

use Data::Dumper;

use feature 'say';
use utf8;

my %accepted =
(
 'John Matrix' => {
     username => 'John Matrix',
     password => "I'll be back, Bennet.",
     name => 'John Matrix',
 }
);

app->plugin('authentication' => {
    'session_key' => 'synology',
    'load_user' => sub
    {
        my($self, $uid) = @_;

        return $accepted{$uid};
    },
    'validate_user' =>  sub
    {
        my($self, $username, $password, $extradata) = @_;

        if (defined $username and defined(my $uid = $accepted{$username}))
        {
            return $username if $uid->{username} eq $username
                and $uid->{password} eq $password;
        }
    }});

app->sessions->default_expiration(1314000); # set expiry to 1 an

# filtrage par adresse ip
my %blacklist;

# limit to 10GB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824 * 10;

my %movies;
refresh();

# parcourir le dossier contenant les films
sub refresh
{
    finddepth(
        sub
        {
            if (-f  $File::Find::name
                and $_ =~ /avi|mpg|mpeg|mp4|iso$/i)
            {
                $movies{$File::Find::name} = [ $_, $File::Find::dir ];
            }
        },
        $ENV{SRC_MOVIES} // "/mnt/cinema");
}

get '/login' => sub
{
    my $self = shift;

    my $url = $self->req->url->base;
    my $host = $url->host;

    if (defined $blacklist{$host} and $blacklist{$host} > 2)
    {
        say "access denied : $host";
        return $self->render_text('access denied!');
    }

    $self->render('login', ip => $host, retry => 3 - $blacklist{$host});
};

under sub {
    my $self = shift;

    my $url = $self->req->url->base;
    my $host = $url->host;

    if ($self->is_user_authenticated
        or $self->authenticate($self->req->param('u'), $self->req->param('p')))
    {
        undef $blacklist{$host};
        return 1;
    }

    my $retry = 3 - ++$blacklist{$host};

    $self->redirect_to('login', ip => $host, retry => $retry);
    return;
};

get '/' => \&display_main;
post '/' => \&display_main;

sub display_main
{
    my $self = shift;

    my $option = $self->req->param('option');
    refresh() if defined $option and $option eq 'refresh';
    $self->render('index', movies => \%movies);
};

get '/download' => sub
{
    my $self = shift;

    my $movie = $self->req->url->query->param('movie');

    my($name, $path) = @{$movies{$movie}};

    # Setup static file handler - or use $self->app->static
    use Mojolicious::Static;
    my $static = Mojolicious::Static->new( paths => [ $path ] );

    # Tell browser to save file as a different name.
    $self->res->headers->content_disposition(
        qq{'attatchment; filename="$name"'});

    # Send
    $static->serve($self, $name);
    $self->rendered;
};

get '/deconnect' => sub
{
    my $self = shift;

    my $url = $self->req->url->base;

    $self->logout;
    $self->render('login', ip => $url->host, retry => 3);
};

app->secret('do not tell anybody!');
app->start;

__DATA__

@@ login.html.ep
%= t h1 => "Login : $ip"

<p>Il vous reste <%= $retry %> essai(s) </p>

<form action="/" method="post">
<table>
<tr> <td> Username </td> <td> <input type="text" name="u" /> </td> </tr>
<tr> <td> Password </td> <td> <input type="password" name="p" /> </td> </tr>
</table>

<input type="submit"/>
</form>

@@ not_found.html.ep
<p>404 : Not found!</p>

@@ not_found.development.html.ep
<p>404 : Not found!</p>

@@ index.html.ep
% layout 'default';
% title 'Synology (version alpha)';

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body>
    <p>Bienvenue sur Synology!</p>

  %= link_to "/?option=refresh" => (class => 'links') => begin
  %= submit_button 'refresh list'
  % end

    <p> Cliquer sur 'DISCONNECT' une fois que vous avez fini!</p>
    <p> La session est valable pendant 1 semaine.</p>

    %= link_to "/deconnect" => (class => 'links') => begin
    %= submit_button 'disconnect'
    % end

    <p>Bonne pioche!</p>

% my @movies = sort keys %$movies;
% foreach my $movie (@movies) {
    <li>
        <%= link_to $movie => "/download?movie=$movie" %>
    </li>
% }
</body>
</html>
