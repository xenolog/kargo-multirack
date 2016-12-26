# Multirack solution for Kubernetes cluster [![Build Status](https://travis-ci.org/xenolog/kargo-multirack.svg?branch=master)](https://travis-ci.org/xenolog/kargo-multirack)

This repo contains Ansible Cookbook, for configure existing 
k8s environment to multirack case.

Also Route Redistribution container stored here.

---
Ansible inventory for kargo should looks like:

```
[all]
node1    ansible_host=10.90.1.2 ip=10.90.1.2
node2    ansible_host=10.90.1.3 ip=10.90.1.3
node3    ansible_host=10.90.2.4 ip=10.90.2.4

[all:vars]
calico_network_backend="none"

.....

[rack1]
node1
node2

[rack1:vars]
  as_number=65001
  subnet=10.90.1.0/24
  tor=10.90.1.254
  bgpport=179
  rr_bgpport=180
  rack_no=1

[rack2]
node3

[rack2:vars]
  as_number=65002
  subnet=10.90.2.0/24
  tor=10.90.2.254
  bgpport=179
  rr_bgpport=190
  rack_no=2

# This group mapping required if your environment deployed by Kargo.
# If You use another deployment tool, or need more custom deployment
# please remove group mapping and list nodes into corresponded groups
# (like in commented example bellow)
# [bird-rr]
# node-1
# node-3
# [bird-node]
# node-2

[bird-rr:children]
kube-master

[bird-node:children]
kube-node
```

Deployment can be started by
```
# ansible-playbook -i $INVENTORY ./cluster.yaml -e @/root/k8s_customization.yaml
```
Where `INVENTORY` may be inventory file or dynamic inventory from `vagrant-multirack`, `-e ...` is optional.

---
Route Redistribution container, implements Route-Reflector, Calico-node, ExtIP announce for multi-rack deployment of Kubernetes.

run `make help` for instruction to build container. 

After build container should be tagged and uploaded to Docker registry. Corresponded tag should be described in the `cluster.yaml` in the `bgpd_container_tag:` parameter.

Example:
```
# make build-container
.....
Removing intermediate container 79bd1bebf920
Successfully built _503598dcebd2_

# docker tag 503598dcebd2 xenolog/k8s-rr-container:20161222-01
# docker push  xenolog/k8s-rr-container:20161222-01

```

On the host system container should be run with network=host.

When container started, ENV should contains:
```
ETCD_AUTHORITY=https://127.0.0.1:2379/,https://10.0.0.1:2379/
HOSTNAME=svasilenko-01-001
RACK=1
BGPD_MODE=RR  # may be RR or NODE (default)
IP=10.222.1.1
DEBUG=1
```
