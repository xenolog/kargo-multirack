#!/bin/bash

# disabled, because part of commands should able to return error
#set -o errexit
set -o nounset

readonly BASE_DIR=$(realpath "$(dirname "${BASH_SOURCE}[0]")")
LONG=10
SHORT=5

NODE_CP="svasilenko-01-001"
NODE_W1="svasilenko-01-004"
NODE_W2="svasilenko-02-002"
ETCD_EP="https://10.220.1.1:2379,https://10.220.1.2:2379"
DD=$(pwd)

export INVENTORY=/root/k8s_inventory.py
export KARGO_GROUP_VARS=/root/k8s_group_vars.yaml
export KARGO_CUSTOMIZATION=/root/k8s_customization.yaml
export K8S_NETWORK_METADATA=/etc/network_metadata.yaml

source "$(realpath "$BASE_DIR")/functions.sh"

##############################################################################
# remove some artifacts, which can be existing if dev environment is in use

rm -rf /root/bird-containers

##############################################################################
# intro
print_hr
msg \
  "This is a demo of Calico Route-Reflector container separation feature."\
  "It demonstrate, how Route-Reflector can be co-executed with calico-node"\
  "container on the same node."\
  "This functionality achieved by bird into RR-container listen on non-standart"\
  "port.It's allowed to use ordinary calico-node container with its bird daemon"\
  "on minion nodes. Advanced bird container should be used for Route-Reflector"\
  "functional, and may be used (not obligatory) as replacement of bird daemon"\
  "into calico-node container. Advanced bird container is full compotible with"\
  "native Calico data format, all information for build peering tree stored"\
  "into '/calico' subtree of etcd."\
  "" \
  "This feature also give an ability to peering between RR and corresponded TOR"\
  "switch for multi-rack topology. I.e. nodes has BGP peering only with"\
  "oute Reflectors. Peering with TOR switch is out of scope of Calico data plane"\
  "and privided into dedicated sub-tree '/multirack_topology' of etcd." \
  "" \
  "This demo is present on the two-rack virtual environment that was deployed," \
  "using vagrant (https://github.com/xenolog/vagrant-multirack). All commands" \
  "runs on the master node." \
  "" \
  "Network topology and role definition for this demo:" \
  "Master-node has name 'svasilenko-000', located out of cluster network and" \
  "has BGP peering with core switch of cluster."\
  "Rack #1:" \
  "  - svasilenko-01-001 -- k8s control plane + minion + RR" \
  "  - svasilenko-01-002 -- k8s control plane + minion + RR" \
  "  - svasilenko-01-003 -- k8s minion" \
  "  - svasilenko-01-004 -- k8s minion" \
  "Rack #2:" \
  "  - svasilenko-02-001 -- k8s control plane + minion + RR" \
  "  - svasilenko-02-002 -- k8s minion"

##############################################################################
# show deployment info
echo ; print_hr
msg \
  "This is a k8s cluster, successfully deployed with Calico network plugin."\
  "You can see all network-related customizations:"
run "cat $KARGO_CUSTOMIZATION | grep -i -e kube_network_plugin -e calico"
echo ; msg \
  "Before deploy this feature we should do some customizations:"\
  " * configure TCP port where BGP daemon will be listen incoming connection."\
  " * setup peering information sourcetype"\
  " * describe a tag of container for separated bird"\
  "   ('latest' will be used by default)"\
  "Such options may be configured for each role (node,RR,TOR) in the group_vars"\
  "file."
run "cat $KARGO_GROUP_VARS"
echo ; msg \
  "This files should be defined as following ENV variables:"
run export KARGO_GROUP_VARS=$KARGO_GROUP_VARS
run export KARGO_CUSTOMIZATION=$KARGO_CUSTOMIZATION
sleep $SHORT

##############################################################################
# Demonstrate, that calico network is a flat.
echo ; print_hr
msg \
  "At this moment we have successfully deployed k8s environment with flat calico"\
  "network, and ready to deploy this feature."\
  "Before continue deployment I want to demonstrate some network"\
  "related parameters."\
  ""\
  "I will run some commands to check:"\
  " * there are no Route reflectors running, only ordinary calico-nodes present"\
  " * BGP mesh betwen all nodes are enabled"\
  " * Bird daemon running and listen on standart BGP (TCP/179) port"\
  " * there are no BGP sessions with Route-Reflectors or TORs"\
  " * there are no specific BGP sessions defined per node"
echo
run "ssh $NODE_CP docker ps | grep -i -e calico -e bird"
run "ssh $NODE_CP etcdctl --endpoints=$ETCD_EP get /calico/bgp/v1/global/node_mesh"
run "ssh $NODE_CP docker exec calico-node netstat -nlp | grep -i bird | grep tcp"
run "ssh $NODE_CP docker exec calico-node birdcl -s /var/run/calico/bird.ctl sh proto | grep -i bgp"
run "ssh $NODE_CP etcdtool -p $ETCD_EP export -f yaml /calico/bgp/v1/host"

sleep $SHORT

##############################################################################
# Explain, what we should do for multi-rack setup with RRs and run it
echo ; print_hr
msg \
  "For deploy network configuration with Route-Reflectors we should done"\
  "following actions:" \
  " * disable node mesh"\
  " * upload configuration of route-reflectors into etcd"\
  " * configure sessions between route-reflectors and corresponded nodes"\
  " * configure sessions between rack's route-reflectors and TOR switches"\
  " * start RR-containers on following nodes"\
  ""\
  "For apply this we should clone and run the ansible playbooks."
echo
run cd
run git clone https://github.com/Mirantis/bird-containers
#run git clone https://github.com/xenolog/kargo-multirack bird-containers
run cd bird-containers
run ansible-playbook -i $INVENTORY ./cluster.yaml -e @/root/k8s_customization.yaml
echo ; msg \
  "Deployment was passed successfully. Nodes which has only k8s minion role has"\
  "'unchanged' status because I demonstrate native calico-node container usage"\
  "for minion nodes. It demonstrate full compatibility with native Calico data"\
  "model v1."
sleep $SHORT

##############################################################################
# Demonstrate, that calico network is a multirack now.
echo ; print_hr
msg \
  "Well, deployment successfull, and I can demonstrate the BGP configuration"\
  "changes for RR usage:" \
  " * the BGP mesh mode disabled"\
  " * all Route reflectors are configured"\
  " * Calico-nodes are configured for BGP peering only with corresponded RRs"
echo
run "ssh $NODE_CP etcdctl --endpoints=$ETCD_EP get /calico/bgp/v1/global/node_mesh"
run "ssh $NODE_CP etcdtool -p $ETCD_EP export -f yaml /calico/bgp/v1/rr_v4"
run "ssh $NODE_CP etcdtool -p $ETCD_EP export -f yaml /calico/bgp/v1/host"
msg \
  "see 'as_num' and 'peer_v4' in the each host configuration section. Nodes"\
  "from rack #1 has peering with two RRs because this rack contains two RR."\
  "Each node form rack #2 configured for only one peering session, because only"\
  "one RR exists in the rack #2."
sleep $SHORT
echo ; print_hr
msg \
  "Now, I'll demonstrate functional part. For example, I take two nodes from 1st" \
  "rack. Node $NODE_CP has a k8s control-plane, minion and RR roles."\
  "This node should present:"\
  " * both calico-node and Route-Reflector containers should be run"\
  " * Route-Reflector container has BGP sessions to all minions of this rack,"\
  "   TOR switch, and all another RRs of this rack (this rack has two RRs)"\
  " * bird daemon into RR-container should listen on the TCP/180 port" \
  " * Node bird container has only BGP sessions with RRs of this rack"\
  " * bird daemon into Node container should listen on the TCP/179 port"
echo
run "ssh $NODE_CP docker ps | grep -i -e calico -e bird"
run "ssh $NODE_CP docker exec bird-rr.service birdcl -s /var/run/bird.ctl sh proto | grep -i bgp"
run "ssh $NODE_CP docker exec bird-rr.service netstat -nlp | grep -i bird | grep tcp"
run "ssh $NODE_CP docker exec calico-node birdcl -s /var/run/calico/bird.ctl sh proto | grep -i bgp"
run "ssh $NODE_CP docker exec calico-node netstat -nlp | grep -i bird  | grep tcp"
echo ; msg \
  "Node $NODE_W1 has only k8s minion role, and should present:"\
  " * only calico-node container should be running"\
  " * calico-node container should have BGP sessions only with RRs of this rack"\
  " * bird inside calico-node container used standart BGP port (TCP/179)"
echo
run "ssh $NODE_W1 docker ps | grep -i -e calico -e bird"
run "ssh $NODE_W1 docker exec calico-node birdcl -s /var/run/calico/bird.ctl sh proto | grep -i bgp"
run "ssh $NODE_W1 docker exec calico-node netstat -nlp | grep -i bird  | grep tcp"
sleep $SHORT

##############################################################################
# Create example service
echo ; print_hr
msg \
  "Well, It remains only to show that k8s cluster with such configuration"\
  "provide connectivity between nodes and pods. For demonstrate it, I'll create"\
  "set of Nginx pods and demonstrate traffic path, for example, between node"\
  "from rack #1 and pod, running on node #2."\
  ""\
  "Creating pods:"
echo
run cat $DD/nginx.yaml
run scp $DD/nginx.yaml $NODE_CP:/tmp/
run ssh $NODE_CP kubectl apply -f /tmp/nginx.yaml
msg "waiting some time for service got started:"
while [ $(ssh $NODE_CP kubectl get deployments -o wide | awk '{print $5}' | grep -v AVAILABLE) != '6' ] ;do
  sleep 1
done ; true
echo
run "ssh $NODE_CP kubectl get deployments -o wide"
run "ssh $NODE_CP kubectl get pods -o wide | grep nginx"
TGT_IP=$(ssh $NODE_CP kubectl get pods -o wide | grep nginx | grep $NODE_W2 | tail -n1 | awk '{print $6}')
echo ; msg \
  "Now will be demonstrated path from node $NODE_W1 to POD with IP $TGT_IP"
echo
run "ssh $NODE_W1 traceroute $TGT_IP"
echo ; msg \
  "As you can see, routing information was transfered successfully, which is "\
  "confirmed by traceroute result, shown above." \
  "" \
  "  that's all..."

sleep $LONG
