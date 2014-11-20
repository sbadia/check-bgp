# check-bgp

Gitoyen BGP checks by SNMP

## Links

* http://routing.explode.gr/quagga-snmp
* http://exchange.nagios.org/directory/Plugins/Network-Protocols/BGP-2D4/check_bgp/details
* http://forums.cacti.net/viewtopic.php?f=12&t=51271
* http://xmodulo.com/monitor-bgp-sessions-nagios.html

## Install

### On the monitored router

Just install the `quagga-snmp-bgpd.pl` script in `/usr/local/etc/quagga-snmp-bgpd`

And add this line in your `snmpd.conf`

```conf
pass_persist .1.3.6.1.4.1.99999.1 /usr/local/etc/quagga-snmp-bgpd
```

### On the monitoring server

Install `check_bgp.pl` in the nagios/checkmk plugin directory.

And run

```
./check_bgp.pl -H router1.myisp.net -C mysUp3rsecr3t -p 8.8.8.8
```

## Limitations

For the moment, this script in IPv4 only :-(
