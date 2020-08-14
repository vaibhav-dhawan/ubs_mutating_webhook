# Usage

Deploy Controller:

```
platform_namespace=domino-platform compute_namespace=domino-compute ./deploy.sh $UNIQUE_CONTROLLER_NAME $HARDWARE_TIERS $MEMORY_LIMIT
```

`HARDWARE_TIERS` can be a comma separated list.
`MEMORY_LIMIT` limits the size that the ramdisk can grow to. Note that the pod will simply be evicted, causing a poor user experience.  example: `8Gi`

If you are not using the default platform and compute namespaces, specify them as above, shown there are the defaults.

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
