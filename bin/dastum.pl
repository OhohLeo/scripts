#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Parser;
use MP3::Tag;
use Encode qw(encode);

use Data::Dumper;

use feature qw(say switch);

# ne vérifie pas le certificat hôte
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

# les paramètres personnels
my($user, $password, $dest) = splice(@ARGV, 0, 3);

# vérifications de base
unless (defined $user and defined $password and defined $dest)
{
    say "usage - ./dastum.pl username password destination search";
    exit 0;
}

unless (-d $dest)
{
    say "destination $dest not found!";
    exit 0;
}

# on remplace les espaces par des +
my $search = join ('+', @ARGV);
say "dastum research : $search";

# on crée le dossier associé à la recherche
mkdir "$dest/$search";
$dest .= "/$search";

my $cookie_jar = HTTP::Cookies->new(
    file => 'dastum_cookies.dat',
    autosave => 1,
    );

my $browser = LWP::UserAgent->new;
$browser->cookie_jar($cookie_jar);

my $agent =
    'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:28.0) Gecko/20100101 Firefox/28.0';

my @header = ('User-Agent' => $agent,
              'Accept' =>
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language' => 'fr,fr-fr;q=0.8,en-us;q=0.5,en;q=0.3',
              'Accept-Encoding' => 'gzip, deflate',
              'Connection' => 'keep-alive');

# initialisation de l'agent
my $ua = LWP::UserAgent->new(
    agent => $agent,
    cookie_jar => HTTP::Cookies->new());

sub send_req
{
    my $res = $ua->request(shift);

    if ($res->code == 302)
    {
        say 'Redirection received: ' . $res->header('Location');
        return $res->header('Location');
    }

    die $res->status_line if not $res->is_success;

    die 'Bad received response!' unless $res->code == 200;

    return $res;
}

# la requête d'authentification
my $req = HTTP::Request->new(
    POST => 'http://mediatheque.dastum.net/CONNECTI',
    [
     'Host' => 'mediatheque.dastum.net',
     @header,
     'Content-Type' => 'application/x-www-form-urlencoded',
    ],
    "ID=lmartin&PW=obubra");

# on envoie la requête et on reçoit la réponse
my $res = send_req($req);

# on récupère le cookie
$cookie_jar->extract_cookies($res);

# la requête pour la recherche
$req = HTTP::Request->new(
    GET => "http://mediatheque.dastum.net/ListRecord.htm?selectobjet=3&what=$search",
    [
     'Host' => 'mediatheque.dastum.net',
     @header,
     'Referer' => 'http://mediatheque.dastum.net/CONNECTI',
     'Content-Type' => 'application/x-www-form-urlencoded',
    ]);

# on replace le cookie
$cookie_jar->add_cookie_header($req);

# on envoie la requête et on reçoit la réponse
$res = send_req($req);

# on crée l'analyseur
my $p = HTML::Parser->new();

# on récupère les éléments intéressants
$p->handler(start => \&parse, 'tagname,attr');
$p->handler(text => \&text, 'dtext');
$p->parse($res->content);
$p->eof;


sub next_request
{
    # la requête pour la recherche
    $req = HTTP::Request->new(
	GET => 'http://mediatheque.dastum.net/' . shift,
	[
	 'Host' => 'mediatheque.dastum.net',
	 @header,
	 'Referer' => 'http://mediatheque.dastum.net/CONNECTI',
	 'Content-Type' => 'application/x-www-form-urlencoded',
	]);

    # on replace le cookie
    $cookie_jar->add_cookie_header($req);

    # on envoie la requête et on reçoit la réponse
    $res = send_req($req);

    # on parse les réponses
    my $p = HTML::Parser->new();
    $p->handler(start => \&parse, 'tagname,attr');
    $p->handler(text => \&text, 'dtext');

    $p->parse($res->content);
    $p->eof;
}

my($nb, $title, $accept_title, $next_url);

sub parse
{
   my($tag, $args) = @_;

   if ($tag eq 'img')
   {
       if (exists $args->{src} and $args->{src} eq 'GIF/RectG.gif'
	   and exists $args->{border} and $args->{border} == 0)
       {
	   $accept_title = 1;
       }

       if (exists $args->{src}
	   and $args->{src} eq 'Ressource.jpg?resnum=200001'
	   and exists $args->{border} and $args->{border} == 0)
       {
	   undef $accept_title;
       }

       if (defined $next_url
	   and exists $args->{src} and $args->{src} eq 'GIF/NavSui.gif'
	   and exists $args->{border} and $args->{border} == 0)
       {
	   next_request($next_url);
	   undef $next_url;
       }
   }

   if ($tag eq 'a'
       and exists $args->{target} and $args->{target} eq 'new'
       and exists $args->{href}
       and $args->{href} =~ /^GEIDEFile\//
       and $args->{href} =~ /mp3/i)
   {
       $nb++;
       my $url = $args->{href};

       my @data = split(/\//, $title);

       my $filename = encode('utf8', "$nb - " . $data[0]);

       say "download url: $url\ntitle: $title\n";

       # la requête pour la recherche
       $req = HTTP::Request->new(
       	   GET => "http://mediatheque.dastum.net/$url",
       	   [
       	    'Host' => 'mediatheque.dastum.net',
       	    @header,
       	    'Referer' => 'http://mediatheque.dastum.net/CONNECTI',
       	    'Content-Type' => 'application/x-www-form-urlencoded',
       	   ]);

       # on replace le cookie
       $cookie_jar->add_cookie_header($req);

       # on envoie la requête et on reçoit la réponse
       $res = send_req($req);

       # on télécharge le fichier
       my $file;
       open($file, ">> $dest/$filename.mp3") or die $!;
       print {$file} $res->content;
       close($file);

       my $mp3 = MP3::Tag->new("$dest/$filename.mp3");
       $mp3->update_tags(
	   {
	       title   => shift @data,
	       comment => shift @data,
	   });

       $mp3->close();
       say "mp3 downloaded!";
       undef $title;
   }


   if ($tag eq 'a'
       and exists $args->{href} and $args->{href} =~ /^ListRecord.htm\?/)
   {
       $next_url = $args->{href};
   }
}

sub text
{
    my $text = shift;
    if (defined $accept_title)
    {
	# un petit nettoyage s'impose
	$text =~ s/  / /g;
	$text =~ tr/\r\t\$#@~!&*.()[]^`\\//d;

        $title .= $text;
    }
}
