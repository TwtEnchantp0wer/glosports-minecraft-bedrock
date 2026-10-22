#!/bin/sh
# Minecraft Bedrock - loopback acici.
#
# Tek oyunculu dunya, yerel sunucuya 127.0.0.1 uzerinden baglanir. lo kapaliysa
# oyun sonsuza kadar "yukleniyor" ekraninda kalir.
#
# goodluckOS'ta uygulama "player" kullanicisi olarak calisir ve root yoktur.
# Bu yuzden user+network namespace kullaniyoruz:
#   1) unshare -Un ile yeni userns+netns acilir (root gerekmez).
#   2) uid/gid eslemesini EBEVEYN yazar (cocuk ilk exec'te capability kaybeder).
#   3) Esleme sonrasi cocuk yeniden exec edilir; artik uid 0'dir ve
#      netns icinde CAP_NET_ADMIN'e sahiptir -> lo acilir.
#   4) Istemci calistirilir.
#
# setgroups(0) CAGRILMAZ; boylece video/audio/input ek gruplari korunur
# (/dev/dri/card0 660 root:video oldugu icin bu sart). Bunun yerine
# /proc/PID/setgroups dosyasina "deny" yazilir.

SELF="$0"
READY="/dev/shm/mcpe_net.ready"
NETLOG="/dev/shm/mcpe_net.log"

if sleep 0.1 >/dev/null 2>&1; then SHORT_SLEEP=0.1; else SHORT_SLEEP=1; fi

log_net() {
  {
    echo "=== netrun mode=$1 uid=$(id -u 2>/dev/null) gid=$(id -g 2>/dev/null) ==="
    echo "groups=$(id -G 2>/dev/null) dri=$([ -r /dev/dri/card0 ] && echo OK || echo NO)"
    ip addr 2>&1 | head -n 40
    ip route 2>&1 | head -n 10
    echo "if_inet6: $(cat /proc/net/if_inet6 2>/dev/null | tr '\n' ' ' | head -c 200)"
    echo "getent_localhost: $(getent hosts localhost 2>&1 | tr '\n' ' ' | head -c 200)"
    echo "hosts_localhost_satir: $(grep -c localhost /etc/hosts 2>/dev/null)"
  } >> "$NETLOG" 2>&1 || true
}

netup() {
  ip link set lo up 2>/dev/null || ifconfig lo up 2>/dev/null || true
  ip addr add 127.0.0.1/8 dev lo 2>/dev/null || ifconfig lo 127.0.0.1 2>/dev/null || true
  # IPv6 loopback: oyun ::1 / localhost deneyebilir
  [ -e /proc/sys/net/ipv6/conf/lo/disable_ipv6 ] && echo 0 > /proc/sys/net/ipv6/conf/lo/disable_ipv6 2>/dev/null
  ip -6 addr add ::1/128 dev lo 2>/dev/null || true
  # Loopback disi bir arayuz: yerel sunucu "yerel IP" secemezse takilabiliyor.
  ip link show mcp0 >/dev/null 2>&1 || ip link add mcp0 type dummy 2>/dev/null || true
  if ip link show mcp0 >/dev/null 2>&1; then
    ip addr add 10.13.37.1/24 dev mcp0 2>/dev/null || true
    ip link set mcp0 up 2>/dev/null || true
    ip route add default dev mcp0 2>/dev/null || true
  elif ip link show mcp1 >/dev/null 2>&1 || ip link add mcp1 type veth peer name mcp2 2>/dev/null; then
    ip addr add 10.13.37.1/24 dev mcp1 2>/dev/null || true
    ip addr add 10.13.37.2/24 dev mcp2 2>/dev/null || true
    ip link set mcp1 up 2>/dev/null || true
    ip link set mcp2 up 2>/dev/null || true
    ip route add default dev mcp1 2>/dev/null || true
  elif ip tuntap add dev mcp3 mode tap 2>/dev/null; then
    ip addr add 10.13.37.1/24 dev mcp3 2>/dev/null || true
    ip link set mcp3 up 2>/dev/null || true
    ip route add default dev mcp3 2>/dev/null || true
  fi
}

fix_hosts() {
  # /etc/hosts icinde localhost yoksa/yanlissa: kopyasina localhost satirlarini
  # ekleyip bind mount et. Mount namespace yoksa sessizce gec.
  H=/dev/shm/mcpe_hosts
  if { cat /etc/hosts 2>/dev/null; echo "127.0.0.1 localhost"; echo "::1 localhost ip6-localhost ip6-loopback"; } > "$H" 2>/dev/null; then
    if mount --bind "$H" /etc/hosts 2>/dev/null; then
      echo "HOSTS_BIND=OK" >> "$NETLOG" 2>&1 || true
    else
      echo "HOSTS_BIND=FAIL" >> "$NETLOG" 2>&1 || true
    fi
  fi
}

# Ebeveyn tarafi: userns'i kur, eslemeyi yaz, cocugu serbest birak.
orchestrate() {
  OMODE="$1"
  MAPU="$2"
  MAPG="$3"
  shift 3

  rm -f "$READY"

  if ! command -v unshare >/dev/null 2>&1; then
    if [ "$OMODE" = "probe" ]; then echo 65534; exit 0; fi
    netup
    fix_hosts
    log_net "fallback-$OMODE"
    exec "$@"
  fi

  unshare -Un sh "$SELF" wait "$READY" "$SELF" "$MAPU" "$MAPG" "$OMODE" "$@" &
  CHILD=$!
  trap 'kill "$CHILD" 2>/dev/null' TERM INT HUP

  # Eslemeyi ebeveyn yazar; cocuk bunu yapamaz (ilk exec'te caps kaybetti).
  # Cocuk henuz unshare etmediyse yazimlar EPERM verir; kisa araliklarla dene.
  n=0
  while [ "$n" -lt 40 ]; do
    [ -d "/proc/$CHILD" ] || break
    echo deny > "/proc/$CHILD/setgroups" 2>/dev/null || true
    echo "0 $MAPU 1" > "/proc/$CHILD/uid_map" 2>/dev/null || true
    echo "0 $MAPG 1" > "/proc/$CHILD/gid_map" 2>/dev/null || true
    grep -q '^[[:space:]]*0[[:space:]]' "/proc/$CHILD/uid_map" 2>/dev/null && break
    sleep "$SHORT_SLEEP"
    n=$((n + 1))
  done

  {
    echo "=== userns map uid=[$(tr '\n' ' ' < "/proc/$CHILD/uid_map" 2>/dev/null)] gid=[$(tr '\n' ' ' < "/proc/$CHILD/gid_map" 2>/dev/null)] ==="
  } >> "$NETLOG" 2>&1 || true

  if ! grep -q '^[[:space:]]*0[[:space:]]' "/proc/$CHILD/uid_map" 2>/dev/null; then
    kill "$CHILD" 2>/dev/null || true
    wait "$CHILD" 2>/dev/null || true
    if [ "$OMODE" = "probe" ]; then echo 65534; exit 0; fi
    netup
    fix_hosts
    log_net "map-fail-$OMODE"
    exec "$@"
  fi

  : > "$READY" 2>/dev/null || true
  wait "$CHILD"
  exit $?
}

case "$1" in
  probe)
    orchestrate probe "$2" "$3"
    ;;
  spawn)
    MAPU="$2"
    MAPG="$3"
    shift 3
    orchestrate run "$MAPU" "$MAPG" "$@"
    ;;
  wait)
    # unshare icindeki ilk surec: esleme yazilana kadar bekle, sonra yeniden exec et.
    W_READY="$2"
    W_SELF="$3"
    W_UID="$4"
    W_GID="$5"
    W_MODE="$6"
    shift 6
    n=0
    while [ ! -e "$W_READY" ] && [ "$n" -lt 30 ]; do
      sleep 1
      n=$((n + 1))
    done
    exec sh "$W_SELF" "$W_MODE-ready" "$W_UID" "$W_GID" "$@"
    ;;
  mapped)
    # unshare'in kendisi uid_map'i yazar (ebeveyn yazamaz: dumpable degil).
    # -m (mount ns) varsa /etc/hosts duzeltmesi de yapilabilir.
    shift
    if unshare -m true 2>/dev/null; then
      exec unshare -Unm --map-user=0 sh "$SELF" ready "$@"
    fi
    exec unshare -Un --map-user=0 sh "$SELF" ready "$@"
    ;;
  mappedr)
    # Eski util-linux: --map-user yok; -r kullan. Ek gruplar korunuyorsa
    # /dev/dri erisimi surer (launcher bunu probe ile dogrular).
    shift
    if unshare -m true 2>/dev/null; then
      exec unshare -Unmr sh "$SELF" ready "$@"
    fi
    exec unshare -Unr sh "$SELF" ready "$@"
    ;;
  ready)
    shift
    netup
    fix_hosts
    log_net ready
    exec "$@"
    ;;
  probe-ready)
    # Esleme sonrasi yeniden exec: uid 0 -> capability'ler geri geldi.
    id -u 2>/dev/null
    exit 0
    ;;
  run-ready)
    shift 3
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
      log_net run-ready-unmapped
      exit 42
    fi
    netup
    fix_hosts
    log_net run-ready
    exec "$@"
    ;;
  direct)
    shift
    netup
    fix_hosts
    log_net direct
    exec "$@"
    ;;
esac
