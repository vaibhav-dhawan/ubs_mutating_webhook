#!/bin/bash
set -e

name=$1
platform_namespace="${platform_namespace:-domino-platform}"
compute_namespace="${compute_namespace:-domino-compute}"
tls_secret=$2
host=$3
replicas=$4

[ -z ${name} ] && echo "Please specify a webhook unique name" && exit 1
[ -z ${tls_secret} ] && echo "Please specify a tls secret" && exit 1
[ -z ${host} ] && echo "Please specify a host name" && exit 1
if [ -z ${replicas} ]; then
    replicas="1"
fi

secret="${name}-webhook-certs"
service="${name}-webhook-svc"

if [ ! -x "$(command -v openssl)" ]; then
    echo "openssl not found"
    exit 1
fi


csrName=${service}.${platform_namespace}
tmpdir=$(mktemp -d)
echo "creating certs in tmpdir ${tmpdir} "

cat <<EOF >> ${tmpdir}/csr.conf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${service}
DNS.2 = ${service}.${platform_namespace}
DNS.3 = ${service}.${platform_namespace}.svc
EOF

# generate a self-signed cert.
# can be replaced with custom cert
openssl genrsa -out ${tmpdir}/server-key.pem 2048
openssl req -new -key ${tmpdir}/server-key.pem \
  -subj "/CN=${service}.${platform_namespace}.svc" \
  -x509 -days 3650 -out ${tmpdir}/server-cert.pem \
  -config ${tmpdir}/csr.conf

# create the secret with CA cert and server cert/key
kubectl create secret generic ${secret} \
        --from-file=key.pem=${tmpdir}/server-key.pem \
        --from-file=cert.pem=${tmpdir}/server-cert.pem \
        --dry-run -o yaml |
    kubectl -n ${platform_namespace} apply -f -

CA_BUNDLE=$(cat ${tmpdir}/server-cert.pem | base64 | tr -d '\n\r')

echo "Creating Script ConfigMap"

kubectl create cm ${name}-webhook-cm --from-file=./app -n ${platform_namespace}

echo "Creating Deployment"
cat <<EOF | kubectl create -n ${platform_namespace} -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}-webhook
  labels:
    app: ${name}-webhook
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${name}-webhook
  template:
    metadata:
      labels:
        app: ${name}-webhook
    spec:
      nodeSelector:
        dominodatalab.com/node-pool: platform
      imagePullSecrets:
      - name: domino-quay-repos
      containers:
      - name: ${name}-webhook
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
        image: python:3.8.4
        ports:
        - containerPort: 5000
        livenessProbe:
          httpGet:
            path: /healthz
            port: 5000
            scheme: HTTPS
          initialDelaySeconds: 20
          failureThreshold: 2
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /healthz
            port: 5000
            scheme: HTTPS
          initialDelaySeconds: 20
          failureThreshold: 2
          timeoutSeconds: 5
        command: [/app/init.sh]
        args:
        - '${tls_secret}'
        - '${host}'
        - '${compute_namespace}'
        imagePullPolicy: Always
        env:
        - name: PYTHONUSERBASE
          value: /home/app
        - name: FLASK_ENV
          value: development
        - name: PYTHONUNBUFFERED
          value: "true"
        volumeMounts:
          - name: app
            mountPath: /app
          - name: certs
            mountPath: /ssl
            readOnly: true
          - name: fakehome
            mountPath: /home/app
      volumes:
        - name: fakehome
          emptyDir: {}
        - name: app
          configMap:
            name: ${name}-webhook-cm
            defaultMode: 0755
        - name: certs
          secret:
            secretName: ${name}-webhook-certs
EOF

echo "Creating Service"
cat <<EOF | kubectl create -n ${platform_namespace} -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ${name}-webhook
  name: ${service}
  namespace: ${platform_namespace}
spec:
  ports:
  - name: https
    port: 443
    targetPort: 5000
  selector:
    app: ${name}-webhook
  sessionAffinity: None
  type: ClusterIP
EOF

# Wait for the app to actually be up before starting the webhook.
let tries=1
availreps=""
while [[ ${tries} -lt 10 && "${availreps}" != ${replicas} ]]; do
  echo "Checking deployment, try $tries"
  kubectl get deployment -n ${platform_namespace} ${name}-webhook
  availreps=$(kubectl get deployment -n ${platform_namespace} ${name}-webhook -o jsonpath='{.status.availableReplicas}')
  let tries+=1
  sleep 10
done

if [[ ${availreps} != ${replicas} ]]; then
  echo "Deployment never became available, exiting."
  exit 1
fi

cat <<EOF | kubectl create -n ${platform_namespace} -f -
apiVersion: admissionregistration.k8s.io/v1beta1
kind: MutatingWebhookConfiguration
metadata:
  name: ${name}-webhook
webhooks:
  - name: ${name}-webhook.k8s.twr.io
    clientConfig:
      service:
        name: ${service}
        namespace: ${platform_namespace}
        path: "/"
      caBundle: ${CA_BUNDLE}
    namespaceSelector:
      matchExpressions:
      - key: ${name}-enabled
        operator: Exists
    rules:
      - operations:
          - "CREATE"
        apiGroups:
          - "*"
        apiVersions:
          - "*"
        resources:
          - "ingresses"
        scope: "Namespaced"
    failurePolicy: Ignore
EOF

kubectl label namespace ${compute_namespace} ${name}-enabled=true
