#!/usr/bin/env perl

use Test::More;
BEGIN {
	use_ok('Net::HTTPS::NB');
}
use strict;

SKIP: {
	skip "I heared fork doesn't work on Windows"
		if $^O =~ /MSWin/i;
	
	my ($host, $port) = make_server();
	my $start = time();
	my $sock = Net::HTTPS::NB->new(Host => $host, PeerPort => $port);
	
	ok(time() - $start >= 3, 'Blocking connect');
	ok(! defined $sock, 'https init error');
	
	my ($host, $port) = make_server();
	$start = time();
	$sock = Net::HTTPS::NB->new(Host => $host, PeerPort => $port, Blocking => 0);
	
	ok(time() - $start < 3, 'Non blocking connect');
	isa_ok($sock, 'Net::HTTPS::NB');
}

done_testing();

sub make_server {
	my $serv = IO::Socket::INET->new(Listen => 3);
	my $child = fork();
	die 'fork:', $! unless defined $child;
	
	if ($child == 0) {
		sleep 3;
		$serv->accept();
		exit;
	}
	
	return ($serv->sockhost, $serv->sockport);
}
