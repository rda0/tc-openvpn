# tc-openvpn

See http://serverfault.com/a/780233/209089

**Traffic shaping of individual clients with `tc` (traffic control) using a script called by OpenVPN**.

The traffic control settings are handled in a script `tc.sh` with the following features:

- Called by OpenVPN using directives: `up`, `down`, `client-connect` and `client-disconnect`
- All settings are passed via environment variables
- Supports theoretically up to `/16` subnets (up to 65534 clients)
- Filtering using [hashing filters][1] for very fast massive filtering
- Filters and classes are set only for clients currently connected, and are individually added and removed without affecting other `tc` settings using unique identifiers (`hashtables`, `handles`, `classids`). These identifiers are generated from the last 16 bits of the client's remote vpn IP
- Individual limiting/throttling of clients based on CN-name (client certificate common name)
- Client settings are stored in files containing their "subscription class" (`bronze`, `silver` and `gold`), to use other classes simply edit the script and modify as needed.
- "Subscription class" and the corresponding data rate ("bandwidth") can be modified on the fly from external applications while a client is connected.

----------

Configuration
---

**OpenVPN server configuration [`/etc/openvpn/tc/conf`](https://github.com/rda0/tc-openvpn/blob/master/server.conf):**

Replace the DNS servers in the last 2 lines with the correct IP addresses.

**Traffic control script [`/etc/openvpn/tc/tc.sh`](https://github.com/rda0/tc-openvpn/blob/master/tc.sh):**



**Subscription database directory `/etc/openvpn/tc/db/`:**

This directory contains a file per client named after its **CN-name** containing the "subscription class" string, configure as follows:

<!-- language: bash -->

    mkdir -p /etc/openvpn/tc/db
    echo bronze > /etc/openvpn/tc/db/client1
    echo silver > /etc/openvpn/tc/db/client2
    echo gold > /etc/openvpn/tc/db/client3

**IP database directory `/etc/openvpn/tc/ip/`:**

This directory will contain the `CN-name <-> IP-address` relation and the `tun interface` during run-time, which has to be provided for an external application updating the `tc` settings while clients are connected.

It will look as follows:

    root@ubuntu:/etc/openvpn/tc/ip# ls -l
    -rw-r--r-- 1 root root    9 Jun  1 08:31 client1.ip
    -rw-r--r-- 1 root root    9 Jun  1 08:30 client2.ip
    -rw-r--r-- 1 root root    9 Jun  1 08:30 client3.ip
    -rw-r--r-- 1 root root    5 Jun  1 08:25 dev
    root@ubuntu:/etc/openvpn/tc/ip# cat *
    10.8.0.2
    10.8.1.0
    10.8.2.123
    tun0

**Enable IP forwarding:**

<!-- language: bash -->

    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

**Configuring NAT (network address translation):**

If you have a static external IP address use `SNAT`:

<!-- language: bash -->

    iptables -t nat -A POSTROUTING -s 10.8.0.0/16 -o <if> -j SNAT --to <ip>

Or if you have a dynamically assigned IP address use `MASQUERADE` (slower):

<!-- language: bash -->

    iptables -t nat -A POSTROUTING -s 10.8.0.0/16 -o <if> -j MASQUERADE

while

 - **`<if>`** is the name of the external interface (i.e. `eth0`)
 - **`<ip>`** is the IP address of the external interface

----------

Script usage and showing tc configuration
---

**Updating "subscription class" and `tc` settings from external application:**

While the OpenVPN server is up and the client connected issue the following commands (example to upgrade `client1` to `"gold"` subscription):

<!-- language: bash -->

    echo gold > /etc/openvpn/tc/db/client1
    /etc/openvpn/tc/tc.sh update client1

**`tc` commands to show the settings:**

    tc -s qdisc show dev tun0
    tc class show dev tun0
    tc filter show dev tun0

----------

Additional information
---

**Notes and possible optimizations:**

- The script and `tc` settings were only tested using a small number of clients
- Large scale testing with massive simultaneous client traffic has to be done and possibly the `tc` settings have to be optimized
- I do not completely understand how the ingress settings work. They should probably be optimized with the use of `ifb` interface as explained in [this answer][2].

**Related documentation for a deeper understanding:**

- [Traffic Control HOWTO][3]
- [Linux Advanced Routing & Traffic Control HOWTO][4] (especially chapter 9-12)
- [HTB Linux queuing discipline manual - user guide][5] (very good explanation of `htb` qdisc)
- [TC manpage][6]
- [Identifying tc filters for `add` and `del` operations][7]
- [OpenVPN 2.3 manpage][8]


  [1]: http://lartc.org/howto/lartc.adv-filter.hashing.html
  [2]: http://serverfault.com/a/386791/209089
  [3]: http://linux-ip.net/articles/Traffic-Control-HOWTO/index.html
  [4]: http://lartc.org/howto/index.html
  [5]: http://luxik.cdi.cz/~devik/qos/htb/manual/userg.htm
  [6]: http://lartc.org/manpages/tc.txt
  [7]: https://bugzilla.kernel.org/show_bug.cgi?id=14875
  [8]: https://community.openvpn.net/openvpn/wiki/Openvpn23ManPage
