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

echo "Testing BIRD containers functional for native Calico data source"
echo

echo "Run etcd container"
ETCDC=$(docker run -d xenolog/etcd:latest)
ETCD_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $ETCDC)
sleep 2  # waiting for etcd run
echo "..ETCD IP: $ETCD_IP"

echo "Run Rack-1 RR1 container"
RRC_11=$(docker run -d -e RACK=1 -e BGPD_MODE=RR -e RR_BGP_PORT=180 -e PEERING_SOURCE=calico -e HOSTNAME=node-01-001 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
RACK1_RR1_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $RRC_11)
echo "..Rack-1/RR1 IP: $RACK1_RR1_IP"

echo "Run Rack-1 RR2 container"
RRC_12=$(docker run -d -e RACK=1 -e BGPD_MODE=RR -e RR_BGP_PORT=180 -e PEERING_SOURCE=calico -e HOSTNAME=node-01-002 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
RACK1_RR2_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $RRC_12)
echo "..Rack-1/RR2 IP: $RACK1_RR2_IP"

echo "Run Rack-1/peer-1 container"
PEER11C=$(docker run --privileged -d -e RACK=1 -e RR_BGP_PORT=180 -e PEERING_SOURCE=calico -e HOSTNAME=node-01-003 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
PEER11_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $PEER11C)
echo "..Rack-1/peer-1 IP: $PEER11_IP"

echo "Run Rack-1 peer-2 container"
PEER12C=$(docker run --privileged -d -e RACK=1 -e RR_BGP_PORT=180 -e PEERING_SOURCE=calico -e HOSTNAME=node-01-004 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
PEER12_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $PEER12C)
echo "..Rack-1/peer-2 IP: $PEER12_IP"


echo "Run Rack-2 RR container"
RRC_2=$(docker run -d -e RACK=2 -e BGPD_MODE=RR -e RR_BGP_PORT=180 -e PEERING_SOURCE=calico -e HOSTNAME=node-02-001 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
RACK2_RR_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $RRC_2)
echo "..Rack-2/RR IP: $RACK2_RR_IP"

echo "Run Rack-2 peer-1 container"
PEER21C=$(docker run --privileged -d -e RACK=2 -e RR_BGP_PORT=180 -e PEERING_SOURCE=calico -e HOSTNAME=node-02-002 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
PEER21_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $PEER21C)
echo "..Rack-2/peer-1 IP: $PEER21_IP"

echo "Run Rack-2 peer-2 container"
PEER22C=$(docker run --privileged -d -e RACK=2 -e RR_BGP_PORT=180 -e PEERING_SOURCE=calico -e HOSTNAME=node-02-003 -e ETCD_AUTHORITY=http://${ETCD_IP}:2379/ $IMG_ID)
PEER22_IP=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $PEER22C)
echo "..Rack-2/peer-2: $PEER22_IP"

RACK1_TOR_IP="10.222.1.254"
RACK2_TOR_IP="10.222.2.254"

echo
echo "Upload '/multirack_topology' data structure into etcd"
cat << EOF > /tmp/multirack_topology.yaml
racks:
  "1":
    rack_no: 1
    as_number: 65001
    tor: "${RACK1_TOR_IP}"
    bgpport: 179
  "2":
    rack_no: 2
    as_number: 65002
    tor: "${RACK2_TOR_IP}"
    bgpport: 179
EOF
docker cp /tmp/multirack_topology.yaml $ETCDC:/tmp/
docker exec $ETCDC etcdtool import -y -f yaml /multirack_topology /tmp/multirack_topology.yaml
docker exec $ETCDC etcdtool export -f yaml /multirack_topology
echo
echo "Upload '/calico' data structure into etcd"
cat << EOF > /tmp/calico.yaml
bgp:
  v1:
    global:
      as_num: "64512"
      node_mesh: '{"enabled":false}'
    rr_v4:
      ${RACK1_RR1_IP}: '{"ip":"${RACK1_RR1_IP}","cluster_id":"1","as_num":"65001"}'
      ${RACK1_RR2_IP}: '{"ip":"${RACK1_RR2_IP}","cluster_id":"1","as_num":"65001"}'
      ${RACK2_RR_IP}: '{"ip":"${RACK2_RR_IP}","cluster_id":"2","as_num":"65002"}'
    host:
      node-01-001:
        as_num: 65001
        ip_addr_v4: ${RACK1_RR1_IP}
      node-01-002:
        as_num: 65001
        ip_addr_v4: ${RACK1_RR2_IP}
      node-01-003:
        ip_addr_v4: ${PEER11_IP}
        as_num: 65001
        peer_v4:
          ${RACK1_RR1_IP}: '{"ip":"${RACK1_RR1_IP}","as_num":"65001"}'
          ${RACK1_RR2_IP}: '{"ip":"${RACK1_RR2_IP}","as_num":"65001"}'
      node-01-004:
        ip_addr_v4: ${PEER12_IP}
        as_num: 65001
        peer_v4:
          ${RACK1_RR1_IP}: '{"ip":"${RACK1_RR1_IP}","as_num":"65001"}'
          ${RACK1_RR2_IP}: '{"ip":"${RACK1_RR2_IP}","as_num":"65001"}'
      node-02-001:
        ip_addr_v4: ${RACK2_RR_IP}
        as_num: 65002
      node-02-002:
        ip_addr_v4: ${PEER21_IP}
        as_num: 65002
        peer_v4:
          ${RACK2_RR_IP}: '{"ip":"${RACK2_RR_IP}","as_num":"65002"}'
      node-02-003:
        ip_addr_v4: ${PEER22_IP}
        as_num: 65002
        peer_v4:
          ${RACK2_RR_IP}: '{"ip":"${RACK2_RR_IP}","as_num":"65002"}'
EOF
docker cp /tmp/calico.yaml $ETCDC:/tmp/
docker exec $ETCDC etcdtool import -y -f yaml /calico /tmp/calico.yaml
docker exec $ETCDC etcdtool export -f yaml /calico
echo "..done"

TESTS_FAILED=""

echo
echo "Check for all bgpd started"
sleep 120  # this sleep required, because containers starts before data source wes ready
err=""
for i in $RRC_11 $RRC_12 $RRC_2 $PEER11C $PEER12C $PEER21C $PEER22C ; do
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
echo "Check bgpd sessions into Rack-1 RR-to-Peers"
sleep 2
sess=$(docker exec $RRC_11 birdc sh proto | grep ' BGP ')
echo $sess
for i in $PEER11_IP $PEER12_IP $RACK1_RR2_IP ; do
    echo $sess | grep $i 2>&1 > /dev/null ; rc=$?
    if [ $rc == 0 ] ; then
        echo "..session with $i is OK"
    else
        err="No BGP session RR-to-$i"
        echo ".-$err"
        TESTS_FAILED="${TESTS_FAILED}\n${err}"
    fi
done
sess=$(docker exec $RRC_12 birdc sh proto | grep ' BGP ')
echo $sess
for i in $PEER11_IP $PEER12_IP $RACK1_RR1_IP ; do
    echo $sess | grep $i 2>&1 > /dev/null ; rc=$?
    if [ $rc == 0 ] ; then
        echo "..session with $i is OK"
    else
        err="No BGP session RR-to-$i"
        echo ".-$err"
        TESTS_FAILED="${TESTS_FAILED}\n${err}"
    fi
done
for i in $PEER21_IP $PEER22_IP RACK2_RR_IP; do
    echo $sess | grep $i 2>&1 > /dev/null ; rc=$?
    if [ $rc == 0 ] ; then
        err="Unrequired BGP session RR-to-$i found"
        echo ".-$err"
        TESTS_FAILED="${TESTS_FAILED}\n${err}"
    fi
done
sess=$(docker exec $RRC_2 birdc sh proto | grep ' BGP ')
echo $sess
for i in $PEER21_IP $PEER22_IP ; do
    echo $sess | grep $i 2>&1 > /dev/null ; rc=$?
    if [ $rc == 0 ] ; then
        echo "..session with $i is OK"
    else
        err="No BGP session RR-to-$i"
        echo ".-$err"
        TESTS_FAILED="${TESTS_FAILED}\n${err}"
    fi
done
for i in $PEER11_IP $PEER12_IP $RACK1_RR1_IP $RACK1_RR2_IP; do
    echo $sess | grep $i 2>&1 > /dev/null ; rc=$?
    if [ $rc == 0 ] ; then
        err="Unrequired BGP session RR-to-$i found"
        echo ".-$err"
        TESTS_FAILED="${TESTS_FAILED}\n${err}"
    fi
done

# echo
# echo "Check bgpd sessions between Peers and RR"
# for id in $PEER11C $PEER12C ; do
#   ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $id)
#   sess=$(docker exec $id birdc sh proto | grep ' BGP ')
#   echo $sess | grep $RACK1_RR_IP 2>&1 > /dev/null ; rc=$?
#     if [ $rc == 0 ] ; then
#         echo "..session from $ip to RR is OK"
#     else
#         err="No BGP session from $ip-to-RR"
#         echo ".-$err"
#         TESTS_FAILED="${TESTS_FAILED}\n${err}"
#     fi
# done

# echo
# echo "Check IP address re-distributiion between peers"
# ip="1.2.3.4"
# docker exec $PEER11C ip a add $ip/32 dev lo
# sleep 30
# docker exec $PEER12C ip r show | grep bird | grep $ip ; rc=$?
# if [ $rc == 0 ] ; then
#     echo "..IP routes re-distribution is OK"
# else
#     err="No IP routes re-distribution"
#     echo ".-$err"
#     TESTS_FAILED="${TESTS_FAILED}\n${err}"
# fi

echo
echo "Remove test env. containers:"
docker kill $ETCDC
docker rm -f $ETCDC
for i in $RRC_11 $RRC_12 $RRC_2 $PEER11C $PEER12C $PEER21C $PEER22C ; do
    #docker cp "${i}:/etc/bird/bird.conf" /tmp/
    #mv /tmp/bird.conf /tmp/bird.conf-$(docker exec -it $i env | grep HOSTNAME | awk -F= '{print $2}')
    docker kill $i
    docker rm -f $i
done

echo
if [ "$TESTS_FAILED" != "" ] ; then
    echo "Failed tests:"
    echo -e $TESTS_FAILED
    exit 1
fi
echo "All tests passed..."