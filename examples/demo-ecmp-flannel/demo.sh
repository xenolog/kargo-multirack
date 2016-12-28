#!/bin/bash

# disabled, because part of commands should able to return error
#set -o errexit
set -o nounset

readonly BASE_DIR=$(realpath "$(dirname "${BASH_SOURCE}[0]")")
LONG=10
SHORT=5
INVENTORY=/root/k8s_inventory.py
NODE_CP="svasilenko-01-001"
NODE_WW="svasilenko-02-002"

source "$(realpath "$BASE_DIR")/functions.sh"

##############################################################################
# remove some artifacts, which can be existing if dev environment is in use

rm -rf /root/bird-containers

##############################################################################
# intro
print_hr
msg \
  "This is the demo of advanced BGP configuration with ECMP for Kubernetes" \
  "and External IP Controller feature. The main goal is to deploy environment" \
  "with route-reflectors and multi-rack topology, and present service's " \
  "fault-tolerance, provided by ECMP." \
  "" \
  "This demo is presented on two-rack virtual environment that was deployed using" \
  "vagrant (https://github.com/xenolog/vagrant-multirack). All commands run" \
  "on the master node" \
  "" \
  "Network topology and role definition for this demo:" \
  "Master-node has name 'svasilenko-000', located out of cluster network and" \
  "has BGP peering with core switch of cluster."\
  "Rack #1:" \
  "  - svasilenko-01-001 -- k8s control plane" \
  "  - svasilenko-01-002 -- k8s control plane" \
  "  - svasilenko-01-003 -- k8s minion" \
  "  - svasilenko-01-004 -- k8s minion" \
  "Rack #2:" \
  "  - svasilenko-02-001 -- k8s control plane" \
  "  - svasilenko-02-002 -- k8s minion"

##############################################################################
# show deployment info
echo ; print_hr
msg \
  "This cluster is deployed using Kargo with Flannel network plugin. ECMP" \
  "feature is network-plugin agnostic if External IP Controller used."
echo

run "cat /root/k8s_customization.yaml | grep -e kube_network_plugin -e extip_"
run "ssh $NODE_CP kubectl get pods -o wide --show-all"
sleep $SHORT

##############################################################################
# Deploy bird containers
echo ; print_hr
msg "Deploy bird containers for dynamic routing and ECMP support:"
echo
run cd
run git clone https://github.com/Mirantis/bird-containers
run cd bird-containers
run ansible-playbook -i $INVENTORY ./cluster.yaml -e @/root/k8s_customization.yaml
echo && msg "Deployment was passed successfully."
sleep $SHORT
echo && msg \
  "Check, whether containers are running"\
  "" \
  "for control plane:"
echo
run "ssh $NODE_CP docker ps | grep bird"
echo && msg "for k8s minion:"
echo
run "ssh $NODE_WW docker ps | grep bird"
sleep $SHORT

##############################################################################
# Create example service
echo ; print_hr
msg "Check routing table for non-existing 10.0.0.* ip addresses: "
echo
run ip route show
sleep $SHORT
echo && msg "Create Nginx Pods and Services"
echo
run cat /tmp/nginx.yaml
run cat /tmp/service.yaml
run scp /tmp/nginx.yaml $NODE_CP:/tmp/
run scp /tmp/service.yaml $NODE_CP:/tmp/
run ssh $NODE_CP kubectl apply -f /tmp/nginx.yaml
run ssh $NODE_CP kubectl apply -f /tmp/service.yaml
msg "waiting some time for service get started..."
rc=1 ; while [ $rc != 0 ] ;do
  # double space between IP address and 'proto' required
  # such notation guarantee more than one route present
  ip r show  |grep '10.0.0.7  proto bird' 2>&1 > /dev/null ; rc=$?
  test $rc != 0 && sleep 1
done ; true
echo
run ssh $NODE_CP kubectl get svc nginxsvc -o wide --show-all
echo && msg \
  "EXTERNAL-IP addresses should appear into a route table of all BGP"\
  "cluster's peers."\
  "This node is outside cluster and has peering to cluster."\
  "We can check existance such routes:"
echo
run ip route show

##############################################################################
# Demonstrate fault tolerance
echo ; print_hr
msg \
  "I will emulate failure of connectivity with each rack one by one, and both " \
  "for demonstrate failure tolerance of ECMP feature if at least one rack alive" \
  "" \
  "Failures will be made by destroying virtual commutator."
echo
run curl -L --head http://10.0.0.7/
run ip route show
echo && msg "Nginx on a some rack is served requests."
sleep $SHORT
echo && msg "Make failure on the 1st rack:"
run systemctl stop tor@1
rc=1 ; while [ $rc != 0 ] ;do
  # 'via' after IP address is guarantee, only one route present
  ip r show  |grep '10.0.0.7 via' 2>&1 > /dev/null ; rc=$?
  test $rc != 0 && sleep 1
done ; true
run curl -L --head http://10.0.0.7/
run ip route show
echo && msg "Nginx on the 2nd rack is served requests."
sleep $SHORT
echo && msg "Restore 1st rack and failure on the 2nd rack:"
run systemctl start tor@1
rc=1 ; while [ $rc != 0 ] ;do
  # double space between IP address and 'proto' required
  # such notation guarantee more than one route present
  ip r show  |grep '10.0.0.7  proto bird' 2>&1 > /dev/null ; rc=$?
  test $rc != 0 && sleep 1
done ; true
run systemctl stop tor@2
rc=1 ; while [ $rc != 0 ] ;do
  # 'via' after IP address is guarantee, only one route present
  ip r show  |grep '10.0.0.7 via' 2>&1 > /dev/null
  test $rc != 0 && sleep 1 ; rc=$?
done ; true
run curl -L --head http://10.0.0.7/
run ip route show
echo && msg "Nginx on the 1nd rack is served requests."
sleep $SHORT
echo && msg "Failure all racks and see no answers:"
run systemctl stop tor@1
run systemctl status tor@1 | head -n 5
run systemctl status tor@2 | head -n 5
run curl -L --head http://10.0.0.7/
run ip route show
echo && msg "There are no connectivity with service"
sleep $SHORT
echo && msg "Resore normal connectivity:"
run systemctl start tor@1
run systemctl start tor@2
rc=1 ; while [ $rc != 0 ] ;do
  # double space between IP address and 'proto' required
  # such notation guarantee more than one route present
  ip r show  |grep '10.0.0.7  proto bird' 2>&1 > /dev/null ; rc=$?
  test $rc != 0 && sleep 1
done ; true
run curl -L --head http://10.0.0.7/
run ip route show
print_hr
echo && msg \
  "As you see, workloads into k8s cluster can be reserved by ECMP feature." \
  "" \
  "  that's all..."

sleep $LONG
