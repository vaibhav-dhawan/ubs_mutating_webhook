# Usage

Deploy Controller:

```
platform_namespace=domino-platform compute_namespace=domino-compute ./deploy.sh $UNIQUE_CONTROLLER_NAME $TLS_SECRET $HOSTNAME $REPLICAS
```

`TLS_SECRET` should be the kubernetes secret that contains the tls cert, in the format namespace/secret name
`HOSTNAME` The domino frontend host, linked to the tls cert 
`REPLICAS` Number of webhook controller pods. Optional: Defaults to 1

Remove Controller:

```
platform_namespace=domino-platform compute_namespace=domino-compute ./destroy.sh $UNIQUE_CONTROLLER_NAME
```

# NOTES:
In Rancher clusters, you will likely have to enable the mutating admission webhook.

An example from the Rancher UI, Edit Cluster, Edit as YAML section below:
```
kube-api:
  always_pull_images: false
  extra_args:
    enable-admission-plugins: 'NodeRestriction,PodSecurityPolicy,ExtendedResourceToleration,MutatingAdmissionWebhook'
```
