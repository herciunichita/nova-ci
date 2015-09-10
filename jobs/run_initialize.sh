#!/bin/bash
#
# Copyright 2013 Cloudbase Solutions Srl
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

# Loading params.txt if exists
set +e
source /usr/local/src/params.txt
set -e

# Loading OpenStack credentials
source /home/jenkins-slave/keystonerc_admin

# Loading all the needed functions
source /usr/local/src/nova-ci/jobs/library.sh

DEVSTACK_SSH_KEY=/home/jenkins-slave/admin-msft.pem

FLOATING_IP=$(nova floating-ip-create public | awk '{print $2}'|sed '/^$/d' | tail -n 1) || echo `date -u +%H:%M:%S` "Failed to alocate floating IP" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
if [ -z "$FLOATING_IP" ]
then
   exit 1
fi
echo FLOATING_IP=$FLOATING_IP > /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt

NAME="nov-dvs-$ZUUL_CHANGE-$ZUUL_PATCHSET"
if [[ ! -z $IS_DEBUG_JOB ]] && [[ $IS_DEBUG_JOB = "yes" ]]; then
	NAME="$NAME-dbg"
fi
export NAME=$NAME

echo NAME=$NAME >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt

NET_ID=$(nova net-list | grep private| awk '{print $2}')
echo NET_ID=$NET_ID >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt

echo `date -u +%H:%M:%S` FLOATING_IP=$FLOATING_IP >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
echo `date -u +%H:%M:%S` NAME=$NAME >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
echo `date -u +%H:%M:%S` NET_ID=$NET_ID >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

echo `date -u +%H:%M:%S` "Deploying devstack $NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

devstack_image="devstack-62v3"

echo `date -u +%H:%M:%S` "Image used is: $devstack_image" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
echo `date -u +%H:%M:%S` "Deploying devstack $NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

# Boot the new 10G of RAM flavor
nova boot --availability-zone hyper-v --flavor nova.devstack --image $devstack_image --key-name default --security-groups devstack --nic net-id="$NET_ID" "$NAME" --poll >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
if [ $? -ne 0 ]
then
    echo `date -u +%H:%M:%S` "Failed to create devstack VM: $NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
    nova show "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
    exit 1
fi

nova show "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

export VMID=`nova show $NAME | awk '{if (NR == 20) {print $4}}'`
echo VM_ID=$VMID >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt

echo `date -u +%H:%M:%S` VM_ID=$VMID >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

echo `date -u +%H:%M:%S` "Fetching devstack VM fixed IP address" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}')
export FIXED_IP="${FIXED_IP//,}"

COUNT=1
while [ -z "$FIXED_IP" ]
do
    if [ $COUNT -lt 10 ]
    then
        sleep 15
        FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}')
        export FIXED_IP="${FIXED_IP//,}"
        COUNT=$(($COUNT + 1))
    else
        echo "Failed to get fixed IP using nova show $NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
        echo "Trying to get the IP from console-log and port-list" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
        FIXED_IP1=`nova console-log $VMID | grep "ci-info" | grep "eth0" | grep "True" | awk '{print $7}'`
        echo "From console-log we got IP: $FIXED_IP1" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
        FIXED_IP2=`neutron port-list -D -c device_id -c fixed_ips | grep $VMID | awk '{print $7}' | tr -d \" | tr -d }`
        echo "From neutron port-list we got IP: $FIXED_IP2" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
        if [[ -z "$FIXED_IP1" || -z "$FIXED_IP2" ||  "$FIXED_IP1" != "$FIXED_IP2" ]]
        then
            echo `date -u +%H:%M:%S` "Failed to get fixed IP" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
            echo `date -u +%H:%M:%S` "nova show output:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
            nova show "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
            echo `date -u +%H:%M:%S` "nova console-log output:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
            nova console-log "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
            echo `date -u +%H:%M:%S` "neutron port-list output:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
            neutron port-list -D -c device_id -c fixed_ips | grep $VMID >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
            exit 1
        else
            export FIXED_IP=$FIXED_IP1
        fi
    fi
done

echo FIXED_IP=$FIXED_IP >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt
echo `date -u +%H:%M:%S` "FIXED_IP=$FIXED_IP" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

sleep 10
exec_with_retry "nova add-floating-ip $NAME $FLOATING_IP" 15 5 || { echo `date -u +%H:%M:%S` "nova show $NAME:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1; nova show "$NAME" >> /home/jenkins-slave/console-$NAME.log 2>&1; echo `date -u +%H:%M:%S` "nova console-log $NAME:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1; nova console-log "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1; exit 1; }

echo `date -u +%H:%M:%S` "nova show $NAME:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
nova show "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

sleep 30
wait_for_listening_port $FLOATING_IP 22 30 || { echo `date -u +%H:%M:%S` "nova console-log $NAME:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1; nova console-log "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1;echo "Failed listening for ssh port on devstack" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1;exit 1; }
sleep 5

echo "adding apt-cacher-ng:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'echo "Acquire::http { Proxy \"http://10.21.7.214:3142\" };" | sudo tee --append /etc/apt/apt.conf.d/90-apt-proxy.conf' 1

echo "clean any apt files:"  >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "sudo rm -rf /var/lib/apt/lists/*" 1

echo "apt-get update:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "sudo apt-get update -y" 1

echo "apt-get upgrade:" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'DEBIAN_FRONTEND=noninteractive && DEBIAN_PRIORITY=critical && sudo apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade' 1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'DEBIAN_FRONTEND=noninteractive && DEBIAN_PRIORITY=critical && sudo apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install pkg-config' 1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'DEBIAN_FRONTEND=noninteractive && DEBIAN_PRIORITY=critical && sudo apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" autoremove' 1

# set timezone to UTC
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime" 1

# copy files to devstack
scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i $DEVSTACK_SSH_KEY /usr/local/src/nova-ci/devstack_vm/* ubuntu@$FLOATING_IP:/home/ubuntu/ >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

set +e
VLAN_RANGE=`/usr/local/src/nova-ci/vlan_allocation.py -a $NAME`
if [ ! -z "$VLAN_RANGE" ]
then
  run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "sed -i 's/TENANT_VLAN_RANGE.*/TENANT_VLAN_RANGE='$VLAN_RANGE'/g' /home/ubuntu/devstack/local.conf" 3
fi
set -e

run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "sed -i 's/export OS_AUTH_URL.*/export OS_AUTH_URL=http:\/\/127.0.0.1:5000\/v2.0\//g' /home/ubuntu/keystonerc" 3

# Add 1 more interface after successful SSH
nova interface-attach --net-id "$NET_ID" "$NAME" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1

# update repos
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "/home/ubuntu/bin/update_devstack_repos.sh --branch $ZUUL_BRANCH --build-for $ZUUL_PROJECT" 1

echo ZUUL_SITE=$ZUUL_SITE >> /home/jenkins-slave/runs/devstack_params.$ZUUL_UUID.$JOB_TYPE.txt

# gerrit-git-prep
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "/home/ubuntu/bin/gerrit_git_prep.sh --zuul-site $ZUUL_SITE --gerrit-site $ZUUL_SITE --zuul-ref $ZUUL_REF --zuul-change $ZUUL_CHANGE --zuul-project $ZUUL_PROJECT" 1

# get locally the vhdx files used by tempest
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "mkdir -p /home/ubuntu/devstack/files/images"
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "wget http://dl.openstack.tld/cirros-0.3.3-x86_64.vhdx -O /home/ubuntu/devstack/files/images/cirros-0.3.3-x86_64.vhdx"
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "wget http://dl.openstack.tld/Fedora-x86_64-20-20140618-sda.vhdx -O /home/ubuntu/devstack/files/images/Fedora-x86_64-20-20140618-sda.vhdx"

# install neutron pip package as it is external
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "sudo pip install -U networking-hyperv --pre"

# make local.sh executable
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "chmod a+x /home/ubuntu/devstack/local.sh"

# run devstack
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'source /home/ubuntu/keystonerc; /home/ubuntu/bin/run_devstack.sh' 5

# run post_stack
echo `date -u +%H:%M:%S` "Running post_stack" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/post_stack.sh" 5

# join Hyper-V servers
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'mkdir -p /openstack/logs; chmod 777 /openstack/logs; sudo chown nobody:nogroup /openstack/logs'
echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv01"
echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv01" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
join_hyperv $hyperv01 $WIN_USER $WIN_PASS

echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv02"
echo `date -u +%H:%M:%S` "Joining Hyper-V node: $hyperv02" >> /home/jenkins-slave/logs/console-$NAME.log 2>&1
join_hyperv $hyperv02 $WIN_USER $WIN_PASS

#check for nova join (must equal 2)
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'source /home/ubuntu/keystonerc; NOVA_COUNT=$(nova service-list | grep nova-compute | grep -c -w up); if [ "$NOVA_COUNT" != 2 ];then nova service-list; exit 1;fi' 12
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'source /home/ubuntu/keystonerc; nova service-list' 1
#check for neutron join (must equal 2)
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'source /home/ubuntu/keystonerc; NEUTRON_COUNT=$(neutron agent-list | grep -c "HyperV agent.*:-)"); if [ "$NEUTRON_COUNT" != 2 ];then neutron agent-list; exit 1;fi' 12
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'source /home/ubuntu/keystonerc; neutron agent-list' 1
