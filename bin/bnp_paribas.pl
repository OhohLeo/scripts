#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Parser;
use Image::Magick;
use Crypt::SSLeay;
use Mozilla::CA;

use Data::Dumper;

use feature 'say';
use v5.10.1;

my($user, $pass, $dir) = qw();

for ($^O)
{
    when (/linux/)
    {
        $dir = '/home/leo/Images';
    }

    when (/MSWin32/)
    {
        mkdir 'c:\bnp' unless -d 'c:\bnp';
        $dir = 'c:\bnp';
    }

    default
    {
        say "Unknown OS type '$^O'";
        exit(0);
    }
}

# on ajoute des cookies par défault
my $cookies = HTTP::Cookies->new();

my $ua = LWP::UserAgent->new(
    agent => 'Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20100101 Firefox/14.0.1',
    cookie_jar => $cookies);

$ua->add_handler("request_send",  sub { shift->dump; return });
$ua->add_handler("response_done", sub { shift->dump; return });

# $ua->ssl_opts(verify_hostnames => 1,
# 	      SSL_ca_file => 'ca-bundle.crt');#Mozilla::CA::SSL_ca_file());

sub send_req
{
    my $result = shift;

    die $result->status_line if not $result->is_success;

    die 'Bad received response!' unless ($result->code == 200);

    return $result;
}

my($req, $res, $p);

my $url = 'https://www.secure.bnpparibas.net/banque/portail/particulier/HomeConnexion?type=homeconnex';

# création de la requête
$req = HTTP::Request->new(
    GET => $url,
    [ 'Host'            => 'www.secure.bnpparibas.net',
      'User-Agent'      => 'Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20100101 Firefox/14.0.1',
      'Accept'          => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' => 'fr,fr-fr;q=0.8,en-us;q=0.5,en;q=0.3',
      'Accept-Encoding' => 'gzip, deflate',
      'DNT'             => '1',
      'Connection'      => 'keep-alive',
    ]);

# on exécute la requête et reçoit la redirection :
$res = send_req($ua->request($req));

my(%password, $timestamp, $action);

# crée un nouvel analyseur
$p = HTML::Parser->new();
$p->handler(start => \&get_data, "tagname,attr");

# analyse le document
$p->parse($res->content);
$p->eof;

# on génère le password
my $password = "";

foreach my $word (split(//, $pass))
{
    $password .= $password{$word}[0] // '';
}

say "Get password '$password'";

my $cookie_value;
$cookies->scan(\&get_cookies);

sub get_cookies
{
    shift;
    if (shift eq 'JSESSIONID')
    {
	$cookie_value = shift;
    }
}

say "Get cookie '$cookie_value'";

$ua->cookie_jar({});

$res = $ua->post('https://www.secure.bnpparibas.net' . $action,
		 'Host'            => 'www.secure.bnpparibas.net',
		 'User-Agent'      => 'Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20100101 Firefox/14.0.1',
		 'Accept'          => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
		 'Accept-Language' => 'fr,fr-fr;q=0.8,en-us;q=0.5,en;q=0.3',
		 'Accept-Encoding' => 'gzip, deflate',
		 'DNT'             => '1',
		 'Connection'      => 'keep-alive',
		 'Referer'         => $url,
		 'Content-Type'    => 'application/x-www-form-urlencoded',
		 'Cookie'          => "JSESSIONID=$cookie_value; "
		 . 'wbo_segment_354528=AA%7CAB%7CAA%7CAA%7C; wbo_segment_354532=AA%7CAB%7CAA%7CAA%7C',
		 'Content'         => [ time   => $timestamp,
					act    => 'actionParValidationEntree',
					outil  => 'IdentificationGraphique',
					etape  => 1,
					bouton => 'espece',
					ch5    => $password,
					ch1    => $user ]);

# on exécute la requête et reçoit la redirection :
send_req($res);

sub save_img
{
    my($src, $dst) = @_;

    my $file;
    open($file, '>', $dst);
    binmode $file;
    print {$file} $src;
    close($file);
}

sub get_data
{
    my($tag, $args) = @_;

    if ($tag eq 'input'
	and defined($args->{name})
	and $args->{name} eq 'time'
	and defined $args->{value})
    {
	$timestamp = $args->{value};
    }

    if ($tag eq 'form'
	and defined($args->{method})
	and $args->{method} eq 'post'
	and defined($args->{name})
	and $args->{name} eq 'logincanalnet'
	and defined $args->{action})
    {
	$action = $args->{action};
    }

    if ($tag eq 'img'
	and exists($args->{src})
	and defined $args->{usemap}
	and $args->{usemap} =~ /^#MapGril/)
    {
	# on télécharge l'image
	$res = $ua->get('https://www.secure.bnpparibas.net/' . $args->{src},
			'Host'            => 'ecaremobile.orange.fr',
			'User-Agent'      => 'Mozilla/5.0 (Windows NT 5.1; rv:14.0) Gecko/20100101 Firefox/14.0.1',
			'Accept'          => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
			'Accept-Language' => 'fr,fr-fr;q=0.8,en-us;q=0.5,en;q=0.3',
			'Accept-Encoding' => 'gzip, deflate',
			'DNT'             => 1,
			'Connection'      => 'keep-alive');

	send_req($res);

      	say "Read image '$dir/grille.gif'";

	save_img($res->content, "$dir/grille.gif");

	my $count = 1;
        foreach my $y (0 .. 4)
        {
            foreach my $x (0 .. 4)
            {
		# on découpe chaque grille contenant un chiffre
                my $img = Image::Magick->new();
                $img->Read("$dir/grille.gif");
		$img->Crop('width'  => 27,
			   'height' => 27,
			   'x' => 27 * $x,
			   'y' => 27 * $y,
			   'Gravity' => 'Center');
		$img->Set(page => '0x0+0+0');

                foreach my $i (0 .. 9)
                {
		    $password{$i} //= [ undef, 1 ];

		    # on récupère l'image
                    my $img_cmp = Image::Magick->new;
                    $img_cmp->Read("$dir/gifs/$i.gif");

                    my $diff = $img->Compare(image => $img_cmp,
					     metric => 'RMSE');
		    if (ref($diff))
		    {
			# on recherche le maximum
			my $error = $diff->Get('error');

			if ($password{$i}[1] > $error)
			{
			    $password{$i} = [ sprintf('%02d', $count), $error ];
			}
		    }
                }

		$count++;
            }
        }
    }
}
