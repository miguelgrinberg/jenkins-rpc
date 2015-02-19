#!/usr/bin/env bash

set -e
set -x

env

# Set HOME to /root
export HOME=/root

# Lab variables
LAB=dev-sat6-lab01
CLUSTER=cluster0{$EXECUTOR_NUMBER}

# Switch to home directory
cd

# We haven't trapped yet
trapped=0

# Trap setter; passes signal name as $1
set_trap() {
      func=$1; shift
  for sig; do
    trap "$func $sig" "$sig"
  done
}

# Cleanup trap
cleanup() {
  # If first trap
  if [[ $trapped -eq 0 ]]
  then
    # We've trapped now
    trapped=1
    # Store exit code
    case $1 in
      INT|TERM|ERR)
        retval=1;; # exit 1 on INT, TERM, ERR
      *)
        retval=$1;; # specified code otherwise
    esac
    # Kill process group, retriggering trap
    kill 0
  fi
  # Disable trap
  trap - INT TERM ERR

  # Rekick the nodes in preperation for the next run.
  [ -e playbooks ] || pushd jenkins-rpc
  [[ $REKICK == "yes" ]] &&  ansible-playbook -i inventory/$LAB-$CLUSTER playbooks/dev-labs/clean.yml ||:

  # Exit
  exit $retval
}

# Set the trap
set_trap cleanup INT TERM ERR

# Clone jenkins-rpc repo
git clone git@github.com:rcbops/jenkins-rpc.git & wait %1


if [[ $BUILD == "yes" ]]
then
  # Move into jenkins-rpc
  pushd jenkins-rpc

  # Read creds for cloud account, used for glance-swift
  # /var/creds is mounted from the host using -v
  # when the docker instance is started.
  source /var/creds/cloud10

  # Prepare the lab
  export PYTHONUNBUFFERED=1
  export ANSIBLE_FORCE_COLOR=1
  ansible-playbook \
    -i inventory/$LAB-$CLUSTER \
    -e @vars/$LAB \
    -e cluster_number=${EXECUTOR_NUMBER} \
    -e lab_name=$LAB \
    -e pullRequestID=${ghprbPullId} \
    -e targetBranch=${TARGET_BRANCH} \
    -e RPC_REPO_URL=${RPC_REPO_URL} \
    -e TRIGGER=${TRIGGER}\
    -e GERRIT_REFSPEC=${GERRIT_REFSPEC}\
    playbooks/gating-labs/site.yml & wait %1

  popd

  # run ansible-lxc-rpc
  ssh $(<target.ip) ./target.sh & wait %1
fi

cleanup 0
