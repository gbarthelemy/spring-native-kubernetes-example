#!/bin/sh
#
# Adapted from:
# https://github.com/kubernetes-sigs/kind/commits/master/site/static/examples/kind-with-registry.sh
#
# Copyright 2020 The Kubernetes Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This script build a kind cluster with specific configuration
# Create a container responsible for docker registry at port 5001
# Create a Contour ingress controller :
# * A new namespace projectcontour
# * Two instances of Contour in the namespace
# * A Kubernetes Daemonset running Envoy on each node in the cluster listening on host ports 80/443
# * A Service of type: LoadBalancer that points to the Contour’s Envoy instances
#
# Documentation :
# cf https://kind.sigs.k8s.io/docs/user/local-registry/
# cf https://kind.sigs.k8s.io/docs/user/ingress/

set -o errexit

# desired cluster name; default is "kind"
KIND_CLUSTER_NAME='quarkus-kube'
kind_version=$(kind version)
reg_port='5000'
reg_name='quarkus-kube-registry'
reg_network='kind'
reg_ip_selector='{{.NetworkSettings.Networks.kind.IPAddress}}'

case "${kind_version}" in
"kind v0.7."* | "kind v0.6."* | "kind v0.5."*)
  reg_ip_selector='{{.NetworkSettings.IPAddress}}'
  reg_network='bridge'
  ;;
esac

# create registry container unless it already exists
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"

# If the registry already exists, but is in the wrong network, we have to
# re-create it.
if [ "${running}" = 'true' ]; then
  reg_ip="$(docker inspect -f ${reg_ip_selector} "${reg_name}")"
  if [ "${reg_ip}" = '' ]; then
    docker kill ${reg_name}
    docker rm ${reg_name}
    running="false"
  fi
fi

if [ "${running}" != 'true' ]; then
  if [ "${reg_network}" != "bridge" ]; then
    docker network create "${reg_network}" || true
  fi

  docker run \
    -d --restart=always -p "${reg_port}:${reg_port}" --name "${reg_name}" --net "${reg_network}" \
    registry:2
fi

reg_ip="$(docker inspect -f ${reg_ip_selector} "${reg_name}")"
if [ "${reg_ip}" = "" ]; then
  echo "Error creating registry: no IPAddress found at: ${reg_ip_selector}"
  exit 1
fi
echo "Registry IP: ${reg_ip}"

# create a cluster with the local registry enabled in containerd
cat <<EOF | kind create cluster --name "${KIND_CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_ip}:${reg_port}"]
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

for node in $(kind get nodes --name "${KIND_CLUSTER_NAME}"); do
  kubectl annotate node "${node}" tilt.dev/registry=localhost:${reg_port}
done

#kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
# Deploy NGINX ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

kubectl apply -f metric-server.yml

# For more information about metric-server, check :
# * https://kubernetes.io/docs/tasks/debug-application-cluster/resource-metrics-pipeline/
# * https://github.com/kubernetes-sigs/metrics-server

kubectl delete -f ../gateway-service/api-ingress.yml
kubectl create -f ../gateway-service/api-ingress.yml
