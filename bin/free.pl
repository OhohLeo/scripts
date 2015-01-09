#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Parser;

use Data::Dumper;

use feature 'say';

# ne vérifie pas le certificat hôte
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

# les paramètres personnels
my($user, $password, $dest, $last) = @ARGV;

unless (defined $user and defined $password and defined $dest)
{
    print "usage - ./perl.pl username password destination [want_last]\n";
    exit 0;
}

my $agent =
    'Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20100101 Firefox/14.0.1';

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

# on envoie la requête d'authentification
my $req = HTTP::Request->new(
    POST => 'https://subscribe.free.fr/login/login.pl',
    [
     'Host' => 'subscribe.free.fr',
     @header,
     'Content-Type' => 'application/x-www-form-urlencoded',
    ],
    "login=$user&pass=$password&ok=Envoyer");

# on reçoit la redirection
my $res = send_req($req);

my($id, $idt) = ($res =~ /id=([0-9]+)&idt=(.*)$/);

unless (defined $id and defined $idt)
{
    die 'id and/or idt not defined';
}

say "id=$id\nidt=$idt";

# on envoie la requête pour afficher les factures
$req = HTTP::Request->new(
    GET => 'https://adsl.free.fr/liste-factures.pl?' . "id=$id&idt=$idt",
    [
     'Host' => 'adsl.free.fr',
     @header,
     'Referer' => 'https://adsl.free.fr/home.pl?' . "id=$id&idt=$idt",
    ]);

$res = send_req($req);

# crée un nouvel analyseur
my $p = HTML::Parser->new();
$p->handler( start => \&start, "tagname,attr" );

# analyse le document
my $count = 0;
$p->parse($res->content);
$p->eof;
exit($count);

sub start
{
    my($tag, $args) = @_;

    if ($tag eq 'a'
        and exists($args->{href})
        and $args->{href} =~ /^facture/
        and $args->{href} =~ /mois=([^&]+)/)
    {
        my $month = $1;

	# on envoie la requête pour afficher les factures
	$req = HTTP::Request->new(
	    GET => 'https://adsl.free.fr/' . $args->{href},
	    [
	     'Host' => 'adsl.free.fr',
             @header,
	     'Referer' => 'https://adsl.free.fr/home.pl?' . "id=$id&idt=$idt",
	    ]);

	my $res = send_req($req);

        my $extension =  ($args->{href} =~ /^facture_pdf/) ? 'pdf' : 'html';

	# on écrit le contenu dans le fichier
	my $file;
	open($file, ">> $dest/$month.$extension") or die $!;
	print {$file} $res->content;
	close($file);

        say "wrote $dest/$month.$extension file";
	$count++;
	# on arrête ici si l'on ne souhaite que le dernier
	exit(1) if $last;
    }
}
