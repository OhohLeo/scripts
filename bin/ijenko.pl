#!/usr/bin/perl

use strict;
use warnings;

use Mail::IMAPClient;
use Mail::IMAPClient::BodyStructure;
use Email::MIME::Encodings;
use MIME::Parser;
use Email::MIME;
use IO::Socket::SSL;
use feature 'say';

my($user, $password, $dst, $last) = qw(TO SPECIFY);

my $socket = IO::Socket::SSL->new(
    PeerAddr => 'imap.gmail.com',
    PeerPort => 993,
    SSL_verify_mode => SSL_VERIFY_NONE);

my $imap = Mail::IMAPClient->new(
    User      => $user,
    Password  => $password,
    Socket    => $socket,
    IgnoreSizeErrors => 1);

warn $imap;

$imap->select('NICOLAS');

my @msgs = $imap->search("ALL");
my $count = 0;

foreach my $id (reverse @msgs)
{
    my $h = $imap->parse_headers($id , "Subject", "Date");

    if ($h->{"Subject"}[0] =~ /bulletin/i)
    {
	my $str = $imap->message_string($id) or die "$0: message_string: $@";

	my $parsed = Email::MIME->new($str);

	$parsed->walk_parts(
	    sub
	    {
		my $part = shift;
		return unless $part->content_type =~ /\bname="([^"]+)"/;

		my $name = $1;
		if ($name =~ /([0-9]{6})/)
		{
		    $count++;

		    my $name = $dst . "$1.pdf";
		    print "$0: writing $name...\n";
		    open my $fh, ">", $name
			or die "$0: open $name: $!";
		    binmode $fh;
		    print $fh $part->content_type =~ m!^text/!
			? $part->body_str
			: $part->body
			or die "$0: print $name: $!";
		    close $fh
			or warn "$0: close $name: $!";

		    # if ($count == 1)
		    # {
		    #     $imap->logout();
		    #     exit(0);
		    # }
		}
	    });
    }
}

$imap->logout();
