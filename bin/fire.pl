#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Parser;

use Data::Dumper;

use feature qw(say switch);

# ne v�rifie pas le certificat h�te
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

# les param�tres personnels
my($ip, $port, $dest) = splice(@ARGV, 0, 3);

# v�rifications de base
unless (defined $ip and defined $port and defined $dest)
{
    say "usage - ./scripts.pl port ip destination";
    exit 0;
}

unless (-d $dest)
{
    say "destination $dest not found!";
    exit 0;
}

my $browser = LWP::UserAgent->new;
my $agent =
    'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:28.0) Gecko/20100101 Firefox/28.0';

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

# la requ�te
my $req = HTTP::Request->new(
    GET => "http://$ip:$port");

# on envoie la requ�te et on re�oit la r�ponse
my $res = send_req($req);

# on cr�e l'analyseur
my $p = HTML::Parser->new();

# on r�cup�re les �l�ments int�ressants
$p->handler(start => \&parse, 'tagname,attr');
$p->parse($res->content);
$p->eof;

my($addr, $title, $accept_title, $next_url);

sub parse
{
   my($tag, $args) = @_;

   if ($tag eq 'a')
   {
       if (exists $args->{href}
	   and $args->{href} =~ /^javascript:void\(window\.open\(\'([^\.]+)/)
       {
	   $addr = $1;
	   if ($args->{href} =~ /(\d+)-(\d+) (\d+):(\d+) ([A|P]M)/)
	   {
	       $title = sprintf('2014%02d%02d - %02d:%02d',
				$1, $2, ($5 eq 'PM') ? $3 + 12 : $3, $4);
	   }
	   else
	   {
	       $title = 'unknown';
	   }

	   say "download url: $title $addr";

	   # la requ�te pour la recherche
	   $req = HTTP::Request->new(
	       GET => "http://$ip:$port/download?filename=$addr&format=aif");

	   # on envoie la requ�te et on re�oit la r�ponse
	   $res = send_req($req);

	   # on t�l�charge le fichier
	   my $file;
	   open($file, ">> $dest/$title.aif") or die $!;
	   print {$file} $res->content;
	   close($file);;
       }
   }
}
