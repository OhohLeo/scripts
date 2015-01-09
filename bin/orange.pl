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
    print "usage - ./orange.pl username password destination [want_last]\n";
    exit 0;
}

my $agent =
    'Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20100101 Firefox/14.0.1';

my @header = ('User-Agent' => $agent,
              'Accept' =>
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language' => 'fr,fr-fr;q=0.8,en-us;q=0.5,en;q=0.3',
              'Accept-Encoding' => 'gzip, deflate',
              'DNT' => 1,
              'Connection' => 'keep-alive');

# initialisation de l'agent
my $ua = LWP::UserAgent->new(
    agent => $agent,
    cookie_jar => HTTP::Cookies->new());

sub send_req
{
    my $res = $ua->request(shift);

    die $res->status_line if not $res->is_success;

    die 'Bad received response!' unless ($res->code == 200);

    return $res;
}

# création de la requête
my $req = HTTP::Request->new(
    GET => 'http://id.orange.fr/auth_user/bin/auth0user.cgi');

# on exécute la requête et reçoit la redirection :
my $res = send_req($req);

# on envoie la requête d'authentification
$req = HTTP::Request->new(
    POST => $res->base,
    [
     'Host' => 'id.orange.fr',
     @header,
     'Content-Type' => 'application/x-www-form-urlencoded',
    ],
    "credential=$user\&pwd=$password"
    . '&save_user=true&save_pwd=true&save_TC=true'
    . '&action=valider&usertype=&service=&url=&case=&origin=');

# on stocke les cookies
$res = send_req($req);

# on envoie la requête pour afficher les factures
$req = HTTP::Request->new(
    GET => 'http://mobile.orange.fr/0/accueil/Retour?SA=CPTFACTURES',
    [
     'Host' => 'mobile.orange.fr',
     @header,
     'Referer' => 'http://www.orange.fr/portail/',
    ]);

$res = send_req($req);

# crée un nouvel analyseur
my $p = HTML::Parser->new();
$p->handler( start => \&start, "tagname,attr" );

# analyse le document
my $count = 0;
p->parse($res->content);
$p->eof;
exit($count);

sub start
{
    my($tag, $args) = @_;

    if ($tag eq 'a'
	and exists($args->{href})
	and $args->{href} =~ /^servlet/
	and $args->{href} =~ /DateFacture=([0-9]{8})/i)
    {
	# on envoie la requête pour afficher les factures
	$req = HTTP::Request->new(
	    GET => 'https://ecaremobile.orange.fr/EcareAsGenerator/'
            . $args->{href},
	    [
	     'Host' => 'ecaremobile.orange.fr',
             @header,
	     'Referer' =>
             'https://ecaremobile.orange.fr/EcareAsGenerator/servlet/'
	     . 'ecareweb.servlet.redirector.AppServerRedirectorServlet?rubrique=F',
	    ]);

	my $res = send_req($req);

	# on écrit le contenu dans le fichier
	my $file;
	open($file, ">> $dest/$1.pdf") or die $!;
	print {$file} $res->content;
	close($file);

        print "wrote $dest/$1.pdf file";
	$count++;
	# on arrête ici si l'on ne souhaite que le dernier
	exit(1) if $last;
    }
}
