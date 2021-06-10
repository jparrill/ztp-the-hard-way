# Connected ZTP Flow Hub deployment

In an ideal world we try just pull the ACM Operator image from the OperatorHub platform, but here in the real world, the ACM v2.3.0 is not released yet, so we need to follow [these instructions](https://github.com/open-cluster-management/deploy#lets-get-started) in order to deploy a non-released ACM version.

To do it in a regular manner, we just need to go to the Openshift Marketplace and look for the "Red Hat Advance Cluster Management" operator and the deploy will start. It takes a while to finish, so please be patience.

We will follow the connected diagram we've seen before:

![](https://i.imgur.com/JpoupQT.png)


Once the ACM deployment finishes, the first 2 steps (Pre-requisites and ACM Deployment) should be already filled, but to be 100% sure let's check a couple of things (Ensure you have your KUBECONFIG loaded)

```
oc get HiveConfig -o yaml

# Should show something like this
apiVersion: hive.openshift.io/v1
kind: HiveConfig
metadata:
  name: hive
spec:
  featureGates:
    custom:
      enabled:
      - AlphaAgentInstallStrategy
    featureSet: Custom
  logLevel: debug
  targetNamespace: hive
```

**NOTE**: If this is not the same content as you have already in your HiveConfig CR, please ensure that you apply this manifests, if not another CRD called ClusterDeployment will fail in future steps.

## Manifest Creation Phase

This phase could be done in an automated way but we want to explain 1-by-1 what we are creating here.

- **ClusterImageSet**: This manifest should contain a reachable OCP version that will be pulled from Hive and Assisted Installer in order to deploy an Spoke cluster, and this is how looks like:

```
apiVersion: hive.openshift.io/v1
kind: ClusterImageSet
metadata:
  name: openshift-v4.8.0
  namespace: assisted-installer
spec:
  releaseImage: quay.io/openshift-release-dev/ocp-release:4.8.0-fc.8-x86_64
```

- **AsistedServiceConfig**: This is an **optional** ConfigMap that could be used to customize the Assisted Service pod deployment using an annotation in the Operand (we will go deep in this topic later).

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: assisted-service-config
  labels:
    app: assisted-service
data:
  CONTROLLER_IMAGE: quay.io/ocpmetal/assisted-installer-controller@sha256:93f193d97556711dce20b2f11f9e2793ae26eb25ad34a23b93d74484bc497ecc
  LOG_LEVEL: "debug"
```

**NOTE**: We don't recommend to use this functionality in production environments and also it's not supported.

- **AgentServiceConfig**: This is the Operand, the Assisted Service pod that handles the spoke clusters deployment's.

```
apiVersion: agent-install.openshift.io/v1beta1
kind: AgentServiceConfig
metadata:
  name: agent
### This is the annotation that injects modifications in the Assisted Service pod
  annotations:
    unsupported.agent-install.openshift.io/assisted-service-configmap: 'assisted-service-config'
###
spec:
  databaseStorage:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 40Gi
  filesystemStorage:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 40Gi
### This is a ConfigMap that only will make sense on Disconnected environments
  mirrorRegistryRef:
    name: 'lab-index-mirror'
###
  osImages:
    - openshiftVersion: "4.8"
      version: "48.84.202106070419-0"
      url: "https://releases-rhcos-art.cloud.privileged.psi.redhat.com/storage/releases/rhcos-4.8/48.84.202106070419-0/x86_64/rhcos-48.84.202106070419-0-live.x86_64.iso"
      rootFSUrl: "https://releases-rhcos-art.cloud.privileged.psi.redhat.com/storage/releases/rhcos-4.8/48.84.202106070419-0/x86_64/rhcos-48.84.202106070419-0-live-rootfs.x86_64.img"
```


- **Private Key**: This is a Secret created that contains the private key that will be used by Assisted Service pod.

```
apiVersion: v1
kind: Secret
metadata:
  name: assisted-deployment-ssh-private-key
stringData:
  ssh-privatekey: |-
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn
    xe+m0Tg8fgoEdogPgx6W0T30Y9b1lytPZKr3gBhKdEGD79by/vjIulP2CqkeNBCfdmIHts
    ...
    ...
    ...
    KnSXpjTZqJen9KAoSl9+U6hJ9mh8uBKAT4B74g4JtjILKiXiKkyWI75PpWb05RXxBxzUYX
    4qqJ4OPv/pnjM7UAAAAXcm9vdEBxY3QtZDE0dTExLnZsYW4yMDgBAgME
    -----END OPENSSH PRIVATE KEY-----
type: Opaque
```

- **Pull Secret**: This is a Secret that contains the access credentials for the Registry access (Internal or External)

```
apiVersion: v1
kind: Secret
metadata:
  name: assisted-deployment-pull-secret
stringData:
  .dockerconfigjson: '{"auths":{"registry.ci.openshift.org":{"auth":"dXNlcjiZ3dasdsaffsafzJubE80LVYngtMlRGdw=="},"registry.svc.ci.openshift.org":{"auth":"dasdaddjo3b1NwNlpYX2kyVLacctNcU9F"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGGMVlTNkk1NlVQUQ==","lab-installer.lab-net:5000":{"auth":"ZHVtbXk6ZHVtbXk=","email":"jhendrix@karmalabs.com"}}}'
```

From here we will create the manifest that regards the spoke clusters, these above ones are only necessary for the Hub cluster.