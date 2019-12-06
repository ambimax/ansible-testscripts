#!/bin/bash
#
# Ansible role test shim.
#
# Usage: [OPTIONS] ./tests/test.sh
#   - distro: a supported Docker distro version (default = "centos7")
#   - playbook: a playbook in the tests directory (default = "test.yml")
#   - role_dir: the directory where the role exists (default = $PWD)
#   - cleanup: whether to remove the Docker container (default = true)
#   - container_id: the --name to set for the container (default = timestamp)
#   - test_idempotence: whether to test playbook's idempotence (default = true)
#
# If you place a requirements.yml file in tests/requirements.yml, the
# requirements listed inside that file will be installed via Ansible Galaxy
# prior to running tests.
#
# License: MIT

# Exit on any individual command failure.
set -e

# Pretty colors.
red='\033[0;31m'
green='\033[0;32m'
neutral='\033[0m'

function printNormal {
    echo -e "\n${green}#############################################################################################"
    echo -e "###   $1"
    echo -e "#############################################################################################${neutral}\n"
}

function errorExit {
    echo -e "\n${red}#############################################################################################"
    echo -e "###   $1"
    echo -e "#############################################################################################${neutral}\n"
    exit 1;
}

timestamp=$(date +%s)

# Allow environment variables to override defaults.
distro=${distro:-"debian9"}
playbook=${playbook:-"playbook.yml"}
role_dir=${role_dir:-"$PWD"}
cleanup=${cleanup:-"true"}
container_id=${container_id:-$timestamp}
test_idempotence=${test_idempotence:-"true"}
reuse=${reuse:-"false"}
DOCKER="docker exec --tty ${container_id} env TERM=xterm env ANSIBLE_FORCE_COLOR=1"

## Set up vars for Docker setup.
# CentOS 7
if [ $distro = 'centos7' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
# CentOS 6
elif [ $distro = 'centos6' ]; then
  init="/sbin/init"
  opts="--privileged"
# Ubuntu 18.04
elif [ $distro = 'ubuntu1804' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
# Ubuntu 16.04
elif [ $distro = 'ubuntu1604' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
# Ubuntu 14.04
elif [ $distro = 'ubuntu1404' ]; then
  init="/sbin/init"
  opts="--privileged --volume=/var/lib/docker"
# Ubuntu 12.04
elif [ $distro = 'ubuntu1204' ]; then
  init="/sbin/init"
  opts="--privileged --volume=/var/lib/docker"
# Debian 10
elif [ $distro = 'debian10' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
# Debian 9
elif [ $distro = 'debian9' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
# Debian 8
elif [ $distro = 'debian8' ]; then
  init="/lib/systemd/systemd"
  opts="--privileged --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
# Fedora 24
elif [ $distro = 'fedora24' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
# Fedora 27
elif [ $distro = 'fedora27' ]; then
  init="/usr/lib/systemd/systemd"
  opts="--privileged --volume=/var/lib/docker --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro"
fi

# Test if container already exists
if $reuse && docker ps -f name=$container_id | grep -q $container_id;
then
    printNormal "Container $container_id already exists. Reusing container geerlingguy/docker-$distro-ansible."
else
    # Run the container using the supplied OS.
    printNormal "Starting Docker container: geerlingguy/docker-$distro-ansible."
    docker pull geerlingguy/docker-$distro-ansible:latest
    docker run --detach --volume="$role_dir":/etc/ansible/playbook:rw \
        --name $container_id $opts geerlingguy/docker-$distro-ansible:latest $init
fi

# Run preparation if `prepare.yml` is present.
if [ -f "$role_dir/tests/prepare.yml" ]; then
  printNormal "Prepare playbook detected; Running preparation."
  ${DOCKER} ansible-playbook /etc/ansible/playbook/tests/prepare.yml
fi

# Install requirements if `requirements.yml` is present.
if [ -f "$role_dir/required-roles.yml" ]; then
  printNormal "Requirements file detected; installing dependencies."
  ${DOCKER} ansible-galaxy install -r /etc/ansible/playbook/required-roles.yml
fi

# Test Ansible syntax.
printNormal "Checking Ansible playbook syntax."
${DOCKER} ansible-playbook /etc/ansible/playbook/$playbook --syntax-check

# Run Ansible playbook.
printNormal "Running command: ${DOCKER} ansible-playbook /etc/ansible/playbook/$playbook"
${DOCKER} ansible-playbook /etc/ansible/playbook/$playbook

# Idempotence test
if [ "$test_idempotence" = true ]; then
  printNormal "Running playbook again: idempotence test"
  idempotence=$(mktemp)
  ${DOCKER} ansible-playbook /etc/ansible/playbook/$playbook | tee -a $idempotence
  tail $idempotence  | grep -q 'changed=0.*failed=0'  \
  && (printNormal 'Idempotence test: pass') || errorExit "Idempotence test: fail"
fi


# Remove the Docker container (if configured).
if [ "$cleanup" = true ]; then
  printNormal "Removing Docker container...\n"
  docker rm -f $container_id
fi
