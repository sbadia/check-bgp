#!/usr/bin/perl -w
# check_bgp - nagios plugin
# See /usr/local/etc/quagga-snmp-bgpd on routers
#
# Copyright (C) 2006 Larry Low
#               2014 Sebastien Badia
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# http://routing.explode.gr/quagga-snmp
# http://exchange.nagios.org/directory/Plugins/Network-Protocols/BGP-2D4/check_bgp/details
# http://forums.cacti.net/viewtopic.php?f=12&t=51271
# http://xmodulo.com/monitor-bgp-sessions-nagios.html
#
use strict;
use warnings;
use lib "/usr/lib/nagios/plugins"  ;
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use vars qw($PROGNAME);

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
	print ("ERROR: Plugin took too long to complete (alarm)\n");
	exit $ERRORS{"UNKNOWN"};
};
alarm($TIMEOUT);

$PROGNAME = "check_bgp.pl";
sub print_help ();
sub print_usage ();
use POSIX qw(floor);

my ($opt_h,$opt_V);
my $community = "public";
my $snmp_version = 2;
my ($hostname,$bgppeer);;

use Getopt::Long;
&Getopt::Long::config('bundling');
GetOptions(
	"V"   => \$opt_V,	"version"    => \$opt_V,
	"h"   => \$opt_h,	"help"       => \$opt_h,
	"C=s" => \$community,	"community=s" => \$community,
	"H=s" => \$hostname,	"hostname=s" => \$hostname,
	"p=s" => \$bgppeer,	"peer=s" => \$bgppeer,
	"v=i" => \$snmp_version,"snmp_version=i" => \$snmp_version
);
# -h & --help print help
if ($opt_h) { print_help(); exit $ERRORS{'OK'}; }
# -V & --version print version
if ($opt_V) { print_revision($PROGNAME,'$Revision: 0.2 $ '); exit $ERRORS{'OK'}; }
# Invalid hostname print usage
if (!utils::is_hostname($hostname)) { print_usage(); exit $ERRORS{'UNKNOWN'}; }
# No BGP peer specified, print usage
if (!defined($bgppeer)) { print_usage(); exit $ERRORS{'UNKNOWN'}; }

# Setup SNMP object
use Net::SNMP qw(INTEGER OCTET_STRING IPADDRESS OBJECT_IDENTIFIER NULL);
my ($snmp, $snmperror);
if ($snmp_version == 2) {
	($snmp, $snmperror) = Net::SNMP->session(
		-hostname => $hostname,
		-version => 'snmpv2c',
		-community => $community
	);
} elsif ($snmp_version == 3) {
	my ($v3_username,$v3_password,$v3_protocol,$v3_priv_passphrase,$v3_priv_protocol) = split(":",$community);
	my @auth = ();
	if (defined($v3_password)) { push(@auth,($v3_password =~ /^0x/) ? 'authkey' : 'authpassword',$v3_password); }
	if (defined($v3_protocol)) { push(@auth,'authprotocol',$v3_protocol); }
	if (defined($v3_priv_passphrase)) { push(@auth,($v3_priv_passphrase =~ /^0x/) ? 'privkey' : 'privpassword',$v3_priv_passphrase); }
	if (defined($v3_priv_protocol)) { push(@auth,'privprotocol',$v3_priv_protocol); }

	($snmp, $snmperror) = Net::SNMP->session(
		-hostname => $hostname,
		-version => 'snmpv3',
		-username => $v3_username,
		@auth
	);
} else {
	($snmp, $snmperror) = Net::SNMP->session(
		-hostname => $hostname,
		-version => 'snmpv1',
		-community => $community
	);
}

if (!defined($snmp)) {
	print ("UNKNOWN - SNMP error: $snmperror\n");
	exit $ERRORS{'UNKNOWN'};
}

my $state = 'UNKNOWN';
my $output = "$bgppeer status retrieval failed.";
# Begin plugin check code
{

	my $bgpsnmp = "1.3.6.1.4.1.99999.1.9";
	my $bgpPeer = "1";
	my $bgpPeerState = "2";
	my $bgpPeerRemoteAs = "3";
	my $bgpPeerMessage = "4";
	my $bgpPeerLastError = "5";

	my %bgpPeerStates = (
		0 => 'down',
		1 => 'up'
	);

	my @snmpoids;
	push (@snmpoids,"$bgpsnmp.$bgppeer.$bgpPeer");
	push (@snmpoids,"$bgpsnmp.$bgppeer.$bgpPeerState");
	push (@snmpoids,"$bgpsnmp.$bgppeer.$bgpPeerRemoteAs");
	push (@snmpoids,"$bgpsnmp.$bgppeer.$bgpPeerMessage");
	push (@snmpoids,"$bgpsnmp.$bgppeer.$bgpPeerLastError");
	my $result = $snmp->get_request(
		-varbindlist => \@snmpoids
	);
	if (!defined($result)) {
		my $answer = $snmp->error;
		$snmp->close;
		print ("UNKNOWN: SNMP error: $answer\n");
		exit $ERRORS{'UNKNOWN'};
	}

	if ($result->{"$bgpsnmp.$bgppeer.$bgpPeerState"} ne "noSuchInstance") {
		$output = "$bgppeer (AS".
			$result->{"$bgpsnmp.$bgppeer.$bgpPeerRemoteAs"}.
			") state is ".
			$bgpPeerStates{$result->{"$bgpsnmp.$bgppeer.$bgpPeerState"}};

		my $established = $result->{"$bgpsnmp.$bgppeer.$bgpPeerLastError"};

		if ($result->{"$bgpsnmp.$bgppeer.$bgpPeerState"} == 1) {
			$state = 'OK';
			$output .= ". Last change ($established)";
		} else {
			if ($result->{"$bgpsnmp.$bgppeer.$bgpPeerMessage"} =~ 'Idle') {
				$state = 'WARNING';
				$output .= ". (disabled by admin) - Last change ($established)";
			} else {
				$state = 'CRITICAL';
				$output .= ". Last change ($established)";
			}
		}
	}
}
print "$state - $output\n";
exit $ERRORS{$state};

sub print_help() {
	print_revision($PROGNAME,'$Revision: 0.2 $ ');
	print "Copyright (c) 2014 Sebastien Badia\n";
	print "This program is licensed under the terms of the\n";
	print "GNU General Public License\n(check source code for details)\n";
	print "\n";
	printf "Check BGP peer status via SNMP.\n";
	print "\n";
	print_usage();
	print "\n";
	print " -H (--hostname)     Hostname to query - (required)\n";
	print " -C (--community)    SNMP read community or v3 auth (defaults to public)\n";
	print "                     (v3 specified as username:authpassword:... )\n";
	print "                       username = SNMPv3 security name\n";
	print "                       authpassword = SNMPv3 authentication pass phrase (or hexidecimal key)\n";
	print "                       authprotocol = SNMPv3 authentication protocol (md5 (default) or sha)\n";
	print "                       privpassword = SNMPv3 privacy pass phrase (or hexidecmal key)\n";
	print "                       privprotocol = SNMPv3 privacy protocol (des (default) or aes)\n";
	print " -v (--snmp_version) 1 for SNMP v1\n";
	print "                     2 for SNMP v2c (default)\n";
	print "                     3 for SNMP v3\n";
	print " -p {--peer}         IP of BGP Peer\n";
	print " -V (--version)      Plugin version\n";
	print " -h (--help)         usage help\n";
	print "\n";
	support();
}

sub print_usage() {
	print "Usage: \n";
	print "  $PROGNAME -H <HOSTNAME> [-C <community>] -p <bgppeer>\n";
	print "  $PROGNAME [-h | --help]\n";
	print "  $PROGNAME [-V | --version]\n";
}
