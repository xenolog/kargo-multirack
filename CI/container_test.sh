#!/bin/bash

#set -o errexit
set -o nounset
set -o pipefail

#set -x

if [ "$TRAVIS_PULL_REQUEST_BRANCH" != "" ]; then
     echo "Test of container skipped for PR. Container will be tested and uploaded after merge."
     exit 0
fi

DATE=$(date "+%Y%m%d")
WD="$(pwd)/bird-container/tmp-$DATE"
IMG_ID=$(tail -n 10 $WD/build.log  | grep 'Successfully built' | awk '{print $3}')

if [ "$IMG_ID" == "" ] ; then
    echo "Container was not successfully built."
    exit 1
fi

echo "Run etcd container"
ETCDC=$(docker run -d xenolog/etcd:latest)
ETCD_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $ETCDC)
sleep 2  # waiting for etcd run
echo "..ETCD IP: $ETCD_IP"

echo "Run RR container"
RRC=$(docker run -d -e RACK=1 -e BGPD_MODE=RR -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
RR_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $RRC)
echo "..RR IP: $RR_IP"

echo "Run peer-1 container"
PEER1C=$(docker run --privileged -d -e RACK=1 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
PEER1_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $PEER1C)
echo "..Peer-1 IP: $PEER1_IP"

echo "Run peer-2 container"
PEER2C=$(docker run --privileged -d -e RACK=1 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
PEER2_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $PEER2C)
echo "..Peer-2 IP: $PEER2_IP"

echo
echo "Upload multirack_topology data structure into etcd"
cat << EOF > /tmp/multirack_topology.yaml
racks:
  "1":
    rack_no: 1
    as_number: 65001
    RRs:
    - ipaddr: $RR_IP
      bgpport: 180
      nexthop: keep
    RR-clients:
    - ipaddr: $PEER1_IP
      bgpport: 179
      nexthop: keep
    - ipaddr: $PEER2_IP
      bgpport: 179
      nexthop: keep
EOF
docker cp /tmp/multirack_topology.yaml $ETCDC:/tmp/
docker exec $ETCDC etcdtool import -y -f yaml /multirack_topology /tmp/multirack_topology.yaml
docker exec $ETCDC etcdtool export -f yaml /multirack_topology
echo "..done"

TESTS_FAILED=""

echo
echo "Check for all bgpd started"
sleep 2
err=""
for i in $RRC $PEER1C $PEER2C ; do
  docker exec $i ps axf | grep ' bird ' ; rc=$?
  test $rc != 0 && err="$err $i"
done
if [ "$err" != "" ] ; then
    err="Bird not started for nodes: $err"
    echo ".-$err"
    TESTS_FAILED="${TESTS_FAILED}\n${err}"
else
    echo "..OK"
fi

echo
echo "Check bgpd sessions  RR-to-Peers"
sleep 2
sess=$(docker exec $RRC birdc sh proto | grep ' BGP ')
for i in $PEER1_IP $PEER2_IP ; do
    echo $sess | grep $i 2>&1 > /dev/null ; rc=$?
    if [ $rc == 0 ] ; then
        echo "..session with $i is OK"
    else
        err="No BGP session RR-to-$i"
        echo ".-$err"
        TESTS_FAILED="${TESTS_FAILED}\n${err}"
    fi
done

echo
echo "Check bgpd sessions between Peers and RR"
for id in $PEER1C $PEER2C ; do
  ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $id)
  sess=$(docker exec $id birdc sh proto | grep ' BGP ')
  echo $sess | grep $RR_IP 2>&1 > /dev/null ; rc=$?
    if [ $rc == 0 ] ; then
        echo "..session from $ip to RR is OK"
    else
        err="No BGP session from $ip-to-RR"
        echo ".-$err"
        TESTS_FAILED="${TESTS_FAILED}\n${err}"
    fi
done

echo
echo "Check IP address re-distributiion between peers"
ip="1.2.3.4"
docker exec $PEER1C ip a add $ip/32 dev lo
sleep 30
docker exec $PEER2C ip r show | grep bird | grep $ip ; rc=$?
if [ $rc == 0 ] ; then
    echo "..IP routes re-distribution is OK"
else
    err="No IP routes re-distribution"
    echo ".-$err"
    TESTS_FAILED="${TESTS_FAILED}\n${err}"
fi

echo
echo "Remove test env. containers:"
for i in $ETCDC $RRC $PEER1C $PEER2C ; do
    docker kill $i
done

echo
if [ "$TESTS_FAILED" != "" ] ; then
    echo "Failed tests:"
    echo -e $TESTS_FAILED
    exit 1
fi
echo "All tests passed..."