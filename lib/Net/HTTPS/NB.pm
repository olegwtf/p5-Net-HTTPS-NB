package Net::HTTPS::NB;

use strict;
use Net::HTTP;
use IO::Socket::SSL 0.98;
use Exporter;
use vars qw($VERSION @ISA @EXPORT $HTTPS_ERROR);

$VERSION = 0.01;

# we only supports IO::Socket::SSL now
# use it force
$Net::HTTPS::SSL_SOCKET_CLASS = 'IO::Socket::SSL';
require Net::HTTPS;

# make aliases
use constant {
	HTTPS_WANT_READ  => SSL_WANT_READ,
	HTTPS_WANT_WRITE => SSL_WANT_WRITE,
};
*HTTPS_ERROR = \$SSL_ERROR;

# need export some stuff for errors handling
@EXPORT = qw($HTTPS_ERROR HTTPS_WANT_READ HTTPS_WANT_WRITE);
@ISA = qw(Net::HTTPS Exporter);

sub new {
	my ($class, %args) = @_;
	
	unless (exists $args{PeerPort}) {
		$args{PeerPort} = 443;
	}
	
	# create plain socket first
	my $self = Net::HTTP->new(%args)
		or return;
	
	# and upgrade it to SSL then
	$class->start_SSL($self, SSL_startHandshake => 0);
	$HTTPS_ERROR = HTTPS_WANT_WRITE;
	
	if (exists($args{Blocking}) && !$args{Blocking} && $self->SUPER::connected) {
		# non-blocking connect
		$self->connect_SSL();
	}
	elsif (!exists($args{Blocking}) || $args{Blocking}) {
		# blocking connect
		$self->connect_SSL()
			or return;
		${*$self}{httpsnb_connected} = 1;
	}
	
	return $self;
}

sub connected {
	my $self = shift;
	
	if (exists ${*$self}{httpsnb_connected}) {
		return ${*$self}{httpsnb_connected};
	}
	
	if (${*$self}{httpsnb_super_connected}) {
		my $st = $self->connect_SSL();
		if ($st) {
			return ${*$self}{httpsnb_connected} = 1;
		}
		return 0;
	}
	
	if ($self->SUPER::connected) {
		${*$self}{httpsnb_super_connected} = 1;
		return $self->connected;
	}
	
	$HTTPS_ERROR = HTTPS_WANT_WRITE;
	return 0;
}

sub close {
	my $self = shift;
	# need some cleanup
	${*$self}{httpsnb_connected} = 0;
	return $self->SUPER::close();
}

sub blocking {
	# blocking() is breaked in Net::HTTPS
	# restore it here
	my $self = shift;
	$self->IO::Socket::INET::blocking(@_);
}

# code below copied from Net::HTTP::NB with some modifications
# Author: Gisle Aas

sub sysread {
	my $self = shift;
	unless (${*$self}{'httpsnb_reading'}) {
		return $self->SUPER::sysread(@_);
	}
	
	if (${*$self}{'httpsnb_read_count'}++) {
		${*$self}{'http_buf'} = ${*$self}{'httpsnb_save'};
		die "Multi-read\n";
	}
	
	my $offset = $_[2] || 0;
	my $n = $self->SUPER::sysread($_[0], $_[1], $offset);
	${*$self}{'httpsnb_save'} .= substr($_[0], $offset);
	return $n;
}

sub read_response_headers {
	my $self = shift;
	${*$self}{'httpsnb_reading'} = 1;
	${*$self}{'httpsnb_read_count'} = 0;
	${*$self}{'httpsnb_save'} = ${*$self}{'http_buf'};
	my @h = eval { $self->SUPER::read_response_headers(@_) };
	${*$self}{'httpsnb_reading'} = 0;
	if ($@) {
		return if $@ eq "Multi-read\n" || $HTTPS_ERROR == HTTPS_WANT_READ;
		die;
	}
	return @h;
}

sub read_entity_body {
	my $self = shift;
	${*$self}{'httpsnb_reading'} = 1;
	${*$self}{'httpsnb_read_count'} = 0;
	${*$self}{'httpsnb_save'} = ${*$self}{'http_buf'};
	# XXX I'm not so sure this does the correct thing in case of
	# transfer-encoding tranforms
	my $n = eval { $self->SUPER::read_entity_body(@_) };
	${*$self}{'httpsnb_reading'} = 0;
	if ($@ || (!defined($n) && $HTTPS_ERROR == HTTPS_WANT_READ)) {
		$_[0] = "";
		return -1;
	}
	return $n;
}

1;
