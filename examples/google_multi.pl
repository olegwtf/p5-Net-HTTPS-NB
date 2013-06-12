#!/usr/bin/env perl

use lib '../lib';
use Net::HTTPS::NB;
use AnyEvent;
use strict;
use warnings;

# Get number of the search results for each specified language in parallel via encrypted google
# Make it easier with AnyEvent

my $loop = AnyEvent->condvar;

for my $q (qw(perl python ruby php lua)) {
	my $sock = Net::HTTPS::NB->new(Host => 'encrypted.google.com', Blocking => 0)
		or next;
	
	$loop->begin();
	
	my $wc; $wc = AnyEvent->io(
		fh => $sock,
		poll => 'w', # first wait until non-blocking socket connection completed
		cb => sub { wait_connection($wc, $loop, $sock, $q) }
	);
}

$loop->recv();

# wait until non-blocking connection completed
sub wait_connection {
	undef $_[0]; # remove watcher completely
	my ($wc, $loop, $sock, $q) = @_;
	
	if ($sock->connected) { # handsheke completed
		print "$q: Connected\n";
		$sock->write_request(GET => "/search?q=$q");
		my $wh; $wh = AnyEvent->io( # now wait headers
			fh => $sock,
			poll => 'r',
			cb => sub { wait_headers($wh, $loop, $sock, $q) }
		);
	}
	elsif($HTTPS_ERROR == HTTPS_WANT_READ) {
		$wc = AnyEvent->io( # handsheke need reading
			fh => $sock,
			poll => 'r',
			cb => sub { wait_connection($wc, $loop, $sock, $q) }
		);
	}
	elsif($HTTPS_ERROR == HTTPS_WANT_WRITE) {
		$wc = AnyEvent->io( # handsheke need writing
			fh => $sock,
			poll => 'w',
			cb => sub { wait_connection($wc, $loop, $sock, $q) }
		);
	}
	else {
		print "$q: Connection failed - $HTTPS_ERROR\n";
		$loop->end();
	}
}

# wait for full headers
sub wait_headers {
	my (undef, $loop, $sock, $q) = @_;
	
	if (my @h = $sock->read_response_headers()) {
		undef $_[0]; # remove headers watcher
		
		print "$q: HTTP code - $h[0]\n";
		my $body = '';
		my $wb; $wb = AnyEvent->io( # now wait body
			fh => $sock,
			poll => 'r',
			cb => sub { wait_body($wb, $loop, $sock, $q, \$body) }
		);
	}
	# else this sub will invoked again when new data will arrive
}

# wait for full body
sub wait_body {
	my (undef, $loop, $sock, $q, $body) = @_;
	
	my $n = $sock->read_entity_body(my $buf, 1024);
	if (!$n) { # error or eof, but who cares?
		undef $_[0]; # remove body watcher
		
		my ($result) = $$body =~ /([\d,]+\s+results?)/;
		print "$q: ", $result||'unknown', "\n";
		$loop->end;
	}
	elsif ($n != -1) {
		substr($$body, length $$body) = $buf; # append body
	}
}
