#! /bin/sh

# check for kubectl executable
if ! [ -x $(command -v kubectl) ]; then
  echo "kubectl not found"
  exit 1
fi

kubectl config get-contexts | grep \* |awk '{print $5":"$3}'
