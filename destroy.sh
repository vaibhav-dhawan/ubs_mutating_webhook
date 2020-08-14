#!/bin/bash

name=$1
platform_namespace="${platform_namespace:-domino-platform}"
compute_namespace="${compute_namespace:-domino-compute}"

[ -z ${name} ] && echo "Please specify a name" && exit 1

secret="${name}-webhook-certs"
service="${name}-webhook-svc"

kubectl delete mutatingwebhookconfiguration ${name}-webhook

kubectl delete secret ${secret} -n ${platform_namespace}

kubectl delete cm ${name}-webhook-cm -n ${platform_namespace}

kubectl delete deployment -n ${platform_namespace} "${name}-webhook"

kubectl delete svc -n ${platform_namespace} ${service}

kubectl label namespace ${compute_namespace} "${name}-enabled"-
