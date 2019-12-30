#!/usr/bin/env bash

cd scripts_kubeadm_local

# Get OS type
function get_os()
{
unameOut="$(uname -s)"
    case "${unameOut}" in
        Linux*)     machine="linux";;
        Darwin*)    machine="darwin";;
        CYGWIN*)    machine="windows";;
        MINGW*)     machine="windows";;
        *)          machine="UNKNOWN:${unameOut}" && exit 1
    esac

    echo ${machine} && export os=${machine}
}

function box_out()
{
  local s=("$@") b w
  for l in "${s[@]}"; do
    ((w<${#l})) && { b="$l"; w="${#l}"; }
  done
  tput setaf 3
  echo " -${b//?/-}-
| ${b//?/ } |"
  for l in "${s[@]}"; do
    printf '| %s%*s%s |\n' "$(tput setaf 4)" "-$w" "$l" "$(tput setaf 3)"
  done
  echo "| ${b//?/ } |
 -${b//?/-}-"
  tput sgr 0
}

get_os

box_out "02_client_tools"
#./02_client_tools.sh

box_out "03_compute_resources"
./03_compute_resources.sh

box_out "04_docker_kubedm_install"
./04_docker_kubedm_install.sh

box_out "05_bootstrap_master"
./05_bootstrap_master.sh

box_out "06_bootstrap_k8s_workers"
./06_bootstrap_k8s_workers.sh

box_out "07_k8s_cni"
./07_k8s_cni.sh

box_out "08_smoke_test"
./08_smoke_test.sh
