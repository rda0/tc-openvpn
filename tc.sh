#!/bin/bash

ipdir=/etc/openvpn/tc/ip
dbdir=/etc/openvpn/tc/db
ip="$ifconfig_pool_remote_ip"
cn="$common_name"
ip_local="$ifconfig_local"

debug=0
log=/tmp/tc.log

if [[ "$debug" > 0 ]]; then
  exec >>"$log" 2>&1
  chmod 666 "$log" 2>/dev/null
  if [[ "$debug" > 1 ]]; then
    date
    id
    echo "PATH=$PATH"
    [[ "$debug" > 2 ]] && printenv
  fi
  echo
  echo "script_type=$script_type"
  echo "dev=$dev"
  echo "ip=$ip"
  echo "user=$cn"
  echo "\$1=$1"
  echo "\$2=$2"
  echo "\$3=$3"
fi

cut_ip_local() {
  if [ -n "$ip_local" ]; then
    ip_local_byte1=`echo "$ip_local" | cut -d. -f1`
    ip_local_byte2=`echo "$ip_local" | cut -d. -f2`
  fi

  [[ "$debug" > 0 ]] && echo "ip_local_byte1=$ip_local_byte1"
  [[ "$debug" > 0 ]] && echo "ip_local_byte2=$ip_local_byte2"
}

create_identifiers() {
  if [ -n "$ip" ]; then
    ip_byte3=`echo "$ip" | cut -d. -f3`
    handle=`printf "%x\n" "$ip_byte3"`
    ip_byte4=`echo "$ip" | cut -d. -f4`
    hash=`printf "%x\n" "$ip_byte4"`
    classid=`printf "%x\n" $((256*ip_byte3+ip_byte4))`
  fi

  [[ "$debug" > 0 ]] && echo "ip_byte3=$ip_byte3"
  [[ "$debug" > 0 ]] && echo "ip_byte4=$ip_byte4"
  [[ "$debug" > 0 ]] && echo "handle=$handle"
  [[ "$debug" > 0 ]] && echo "hash=$hash"
}

start_tc() {
  [[ "$debug" > 1 ]] && echo "start_tc()"

  cut_ip_local

  echo "$dev" > "$ipdir"/dev

  tc qdisc add dev "$dev" root handle 1: htb
  tc qdisc add dev "$dev" handle ffff: ingress

  tc filter add dev "$dev" parent 1:0 prio 1 protocol ip u32
  tc filter add dev "$dev" parent 1:0 prio 1 handle 2: protocol ip u32 divisor 256
  tc filter add dev "$dev" parent 1:0 prio 1 protocol ip u32 ht 800:: \
      match ip dst "${ip_local_byte1}"."${ip_local_byte2}".0.0/16 \
      hashkey mask 0x000000ff at 16 link 2:

  tc filter add dev "$dev" parent ffff:0 prio 1 protocol ip u32
  tc filter add dev "$dev" parent ffff:0 prio 1 handle 3: protocol ip u32 divisor 256
  tc filter add dev "$dev" parent ffff:0 prio 1 protocol ip u32 ht 800:: \
      match ip src "${ip_local_byte1}"."${ip_local_byte2}".0.0/16 \
      hashkey mask 0x000000ff at 12 link 3:
}

stop_tc() {
  [[ "$debug" > 1 ]] && echo "stop_tc()"

  tc qdisc del dev "$dev" root
  tc qdisc del dev "$dev" handle ffff: ingress

  [ -e "$ipdir"/dev ] && rm "$ipdir"/dev
}

function bwlimit-enable() {
  [[ "$debug" > 1 ]] && echo "bwlimit-enable()"

  create_identifiers

  echo "$ip" > "$ipdir"/"$cn".ip

  # Find this user's bandwidth limit
  [[ "$debug" > 0 ]] && echo "userdbfile=${dbdir}/${cn}"
  user=`cat "${dbdir}/${cn}"`
  [[ "$debug" > 0 ]] && echo "subscription=$user"

  if [ "$user" == "gold" ]; then
    downrate=100mbit
    uprate=100mbit
  elif [ "$user" == "silver" ]; then
    downrate=10mbit
    uprate=10mbit
  elif [ "$user" == "bronze" ]; then
    downrate=1mbit
    uprate=1mbit
  else
    downrate=10kbit
    uprate=10kbit
  fi

  # Limit traffic from VPN server to client
  tc class add dev "$dev" parent 1: classid 1:"$classid" htb rate "$downrate"
  tc filter add dev "$dev" parent 1:0 protocol ip prio 1 \
      handle 2:"${hash}":"${handle}" \
      u32 ht 2:"${hash}": match ip dst "$ip"/32 flowid 1:"$classid"

  # Limit traffic from client to VPN server
  # Maybe better use ifb for ingress? See: http://serverfault.com/a/386791/209089
  tc filter add dev "$dev" parent ffff:0 protocol ip prio 1 \
      handle 3:"${hash}":"${handle}" \
      u32 ht 3:"${hash}": match ip src "$ip"/32 \
      police rate "$uprate" burst 80k drop flowid :"$classid"
}

function bwlimit-disable() {
  [[ "$debug" > 1 ]] && echo "bwlimit-disable()"

  create_identifiers

  tc filter del dev "$dev" parent 1:0 protocol ip prio 1 \
      handle 2:"${hash}":"${handle}" u32 ht 2:"${hash}":
  tc class del dev "$dev" classid 1:"$classid"
  tc filter del dev "$dev" parent ffff:0 protocol ip prio 1 \
      handle 3:"${hash}":"${handle}" u32 ht 3:"${hash}":

  # Remove .ip
  [ -e "$ipdir"/"$cn".ip ] && rm "$ipdir"/"$cn".ip
}

case "$script_type" in
  up)
    start_tc
    ;;
  down)
    stop_tc
    ;;
  client-connect)
    bwlimit-enable
    ;;
  client-disconnect)
    bwlimit-disable
    ;;
  *)
    case "$1" in
      update)
        [ -z "$2" ] && echo "$0 $1: missing argument [client-CN]" >&2 && exit 1
        [ ! -e "$ipdir"/"$2".ip ] &&  \
            echo "$0 $1 $2: file $ipdir/$2.ip not found" >&2 && exit 1
        [ ! -e "$ipdir"/dev ] && \
            echo "$0 $1: file $ipdir/dev not found" >&2 && exit 1
        ip=`cat "$ipdir/$2.ip"`
        dev=`cat "$ipdir/dev"`
        cn="$2"
        bwlimit-disable
        bwlimit-enable
        ;;
      *)
        echo "$0: unknown operation [$1]" >&2
        exit 1
        ;;
    esac
    ;;
esac

exit 0
