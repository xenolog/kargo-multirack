#!/usr/bin/python
# -*- coding: utf-8 -*-

from ansible.module_utils.basic import *
import json

DOCUMENTATION = """
---
module: generate_node_peer_list
short_description: Generate Calico peering hash which can be uploaded into etcd
description:
  - Generate Calico peering hash. Result can be uploaded into etcd
version_added: "2.0"
options:
  inventory:
    required: true
    default: null
    description:
      - 'hostvars' should be here
author: "Sergey Vasilenko (svasilenko@mirantis.com)"
"""

EXAMPLES = """
- name: Generate nodes peering
  generate_node_peer_list: inventory="{% for host in groups['all'] %}{{ hostvars[host]|to_json }}{% endfor %}"
"""

# RETURN = """
# """

def main():
    module = AnsibleModule(
        argument_spec=dict(
            inventory=dict(required=True),
        )
    )
    # this is a workaround to https://github.com/ansible/ansible/issues/13838
    inventory = "[" + module.params.get("inventory").replace("}{", "},{") + "]"
    nodes = json.loads(inventory)
    racks = {}
    # calculate RR list per rack
    for node in nodes:
        rack_no = int(node.get('rack_no', 0))
        if 0 == rack_no:
            continue
        rack_no_name = "{0}".format(rack_no)
        if racks.get(rack_no_name, None) == None:
            # we can setup rack by first node, because group-based variables are equal for all nodes into rack
            racks[rack_no_name] = {
              'rack_no': rack_no,
              'as_number': node.get('as_number', 65000+rack_no),
              'rr_bgpport': int(node.get('rr_bgpport', int(node.get('bgpport', 179)) + 1)),
              'RRs': [],
              'nodes': []
            }
        racks[rack_no_name]['nodes'].append(node['inventory_hostname_short'])
        if 'bird-rr' in node.get('group_names', []):
            # RR should be run on kube_master
            racks[rack_no_name]['RRs'].append(node['ip'])
    # calculate RR list
    rr_v4 = {}
    rr_peering = {}
    for rack in racks.itervalues():
        rr_peering[rack['rack_no']] = {}
        for ipaddr in rack['RRs']:
            rr_v4[ipaddr] = json.dumps({
              'ip': ipaddr,
              'cluster_id': str(rack['rack_no']),
              'as_num': str(rack['as_number']),
              'bgp_port': str(rack['rr_bgpport'])
            })
            rr_peering[rack['rack_no']][ipaddr] = json.dumps({
              'ip': ipaddr,
              'as_num': str(rack['as_number'])
            })
    # calculate RR peering for each node
    hosts = {}
    for rack in racks.itervalues():
        for hostname in rack['nodes']:
            hosts[hostname] = {
              'as_num': rack['as_number'],
              'peer_v4': rr_peering[rack['rack_no']]
            }
    #
    res = {
        'result': {
            'bgp': {
                'v1': {
                    'global': {'node_mesh': '{"enabled":false}'},
                    'host': hosts,
                    'rr_v4': rr_v4,
                }
            }
        }
    }
    module.exit_json(**res)

if __name__ == '__main__':
    main()
