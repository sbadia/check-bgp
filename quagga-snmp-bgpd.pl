#! /usr/bin/perl
# --------------------------------------------------------------------
# Copyright (C) 2004-2006 Oliver Hitz <oliver@net-track.ch>
#
# $Id: quagga-snmp-bgpd.in,v 1.3 2006-07-04 14:26:03 oli Exp $
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston,
# MA 02111-1307, USA.
# --------------------------------------------------------------------
# quagga-snmp-bgpd
#
# An extension for polling BGP peer data from a running Quagga bgpd
# instance.
#
# Please read the man page quagga-snmp-bgpd(8) for instructions.
# --------------------------------------------------------------------

use strict;

# The base OID of this extension. Has to match the OID in snmpd.conf:
my $baseoid = ".1.3.6.1.4.1.99999.1";

# Put in the path to vtysh:
my $vtysh = "/usr/bin/vtysh";

# Results from "sh ip bgp su" are cached for some seconds so that an
# SNMP walk doesn't result in vtysh being called hundreds of times:
my $cache_secs = 60;

# --------------------------------------------------------------------

my $mib;
my $mibtime;

# Switch on autoflush
$| = 1;

while (my $cmd = <STDIN>) {
  chomp $cmd;

  if ($cmd eq "PING") {
    print "PONG\n";
  } elsif ($cmd eq "get") {
    my $oid_in = <STDIN>;

    my $oid = get_oid($oid_in);
    my $mib = create_bgp_mib();

    if ($oid != 0 && defined($mib->{$oid})) {
      print "$baseoid.$oid\n";
      print $mib->{$oid}[0]."\n";
      print $mib->{$oid}[1]."\n";
    } else {
      print "NONE\n";
    }
  } elsif ($cmd eq "getnext") {
    my $oid_in = <STDIN>;

    my $oid = get_oid($oid_in);
    my $found = 0;

    my $mib = create_bgp_mib();
    my @s = sort { oidcmp($a, $b) } keys %{ $mib };
    for (my $i = 0; $i < @s; $i++) {
      if (oidcmp($oid, $s[$i]) == -1) {
	print "$baseoid.".$s[$i]."\n";
	print $mib->{$s[$i]}[0]."\n";
	print $mib->{$s[$i]}[1]."\n";
	$found = 1;
	last;
      }
    }
    if (!$found) {
      print "NONE\n";
    }
  } else {
    # Unknown command
  }
}

exit 0;

sub get_oid
{

  my ($oid) = @_;
  chomp $oid;

  my $base = $baseoid;
  $base =~ s/\./\\./g;

  if ($oid !~ /^$base(\.|$)/) {
    # Requested oid doesn't match base oid
    return 0;
  }

  $oid =~ s/^$base\.?//;
  return $oid;
}

sub oidcmp {
  my ($x, $y) = @_;

  my @a = split /\./, $x;
  my @b = split /\./, $y;

  my $i = 0;

  while (1) {

    if ($i > $#a) {
      if ($i > $#b) {
	return 0;
      } else {
	return -1;
      }
    } elsif ($i > $#b) {
      return 1;
    }

    if ($a[$i] < $b[$i]) {
      return -1;
    } elsif ($a[$i] > $b[$i]) {
      return 1;
    }

    $i++;
  }
}

sub create_bgp_mib
{
  # We cache the results for $cache_secs seconds
  if (time - $mibtime < $cache_secs) {
    return $mib;
  }

  my %bgp = (
	     "1" => [ "integer", 0 ],	# Number of configured peers
	     "2" => [ "integer", 0 ],	# Number of active peers
	     "3" => [ "integer", 0 ],	# Number of AS-PATH entries
	     "4" => [ "integer", 0 ],	# Number of BGP community entries
	     "5" => [ "integer", 0 ]	# Number of Prefixes
	    );

  open Q, "$vtysh -e \"show ip bgp summary\" |";
  while (my $l = <Q>) {
    if ($l =~ /^(\d+) BGP AS-PATH entries/) {
      $bgp{"3"}[1] = $1;
    } elsif ($l =~ /^(\d+) BGP community entries/) {
      $bgp{"4"}[1] = $1;
    } elsif ($l =~ /^(\d+\.\d+\.\d+\.\d+)\s/) {
      $bgp{"1"}[1]++;
      my @n = split /\s+/, $l;
      # .1 IP Address
      $bgp{"9.".$n[0].".1"} = [ "ipaddress", $n[0] ];
      # .2 State, .4 Prefixes
      if ($n[9] =~ /\d+/) {
	$bgp{"9.".$n[0].".2"} = [ "integer", 1 ];
	$bgp{"9.".$n[0].".4"} = [ "integer", $n[9] ];
	$bgp{"2"}[1]++;
	$bgp{"5"}[1] += $n[9];
      } else {
	$bgp{"9.".$n[0].".2"} = [ "integer", 0 ];
	$bgp{"9.".$n[0].".4"} = [ "integer", 0 ];      }
      # .3 ASN
      $bgp{"9.".$n[0].".3"} = [ "integer", $n[2] ];
      # .5 Up/down
      $bgp{"9.".$n[0].".5"} = [ "timeticks", uptime($n[8]) ];
    }
  }
  close Q;

  # If no AS-PATH info could be found, issue "show bgp memory"
  if ($bgp{"3"}[1] == 0) {
    open Q, "$vtysh -e \"show bgp memory\" |";
    while (my $l = <Q>) {
      if ($l =~ /^(\d+) BGP AS-PATH entries/) {
	$bgp{"3"}[1] = $1;
      } elsif ($l =~ /^(\d+) BGP community entries/) {
	$bgp{"4"}[1] = $1;
      }
    }
    close Q;
  }

  $mib = \%bgp;
  $mibtime = time;
  return $mib;
}

sub uptime
{
  my ($t) = @_;

  if ($t =~ /^(\d+):(\d+):(\d+)$/) {
    return 100*($3+60*($2+$1*60));
  } elsif ($t =~ /^(\d+)d(\d+)h(\d+)m$/) {
    return 100*60*($3+60*($2+24*$1));
  } elsif ($t =~ /^(\d+)w(\d+)d(\d+)h$/) {
    return 100*60*60*($3+24*$2+7*24*$1);
  }
  return 0;
}
