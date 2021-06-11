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
  namespace: open-cluster-management
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

### Hub Basic elements creation

This phase could be done in an automated way but we want to explain 1-by-1 what we are creating here.

- **ClusterImageSet**: This manifest should contain a reachable OCP version that will be pulled from Hive and Assisted Installer in order to deploy an Spoke cluster, and this is how looks like:

```
apiVersion: hive.openshift.io/v1
kind: ClusterImageSet
metadata:
  name: openshift-v4.8.0
  namespace: open-cluster-management
spec:
  releaseImage: quay.io/openshift-release-dev/ocp-release:4.8.0-fc.8-x86_64
```

- **AsistedServiceConfig**: This is an **optional** ConfigMap that could be used to customize the Assisted Service pod deployment using an annotation in the Operand (we will go deep in this topic later).

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: assisted-service-config
  namespace: open-cluster-management
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
  namespace: open-cluster-management
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
  namespace: open-cluster-management
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
  namespace: open-cluster-management
stringData:
  .dockerconfigjson: '{"auths":{"registry.ci.openshift.org":{"auth":"dXNlcjiZ3dasdNTSFffsafzJubE80LVYngtMlRGdw=="},"registry.svc.ci.openshift.org":{"auth":"dasdaddjo3b1NwNlpYX2kyVLacctNcU9F"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGGMVlTNkk1NlVQUQ==","lab-installer.lab-net:5000":{"auth":"ZHVtbXk6ZHVtbXk=","email":"jhendrix@karmalabs.com"}}}'
```

From here we will create the manifest that regards the spoke clusters, these above ones are only necessary for the Hub cluster.

### Spoke cluster definition and deployment

In the Manifest creation phase we still need to define the relevant CR's that will represent our spoke cluster, said that we will continue with the relevant elements for the managed clusters.

- **AgentClusterInstall**: This is one of the most important elements to define, the first thing is to decide which kind of deployment you need to do. If it's SNO vs Multinode is really important here so let's focus in both cases

#### SNO Cluster Definition

For Single Node Openshift we need to specify the next things:

- `spec.provisionRequirements.controlPlaneAgents`: Set to **1**, this means that we just want a ControlPlane based on 1 Master node.
- `spec.imageSetRef`: This will reference the ClusterImageSet created in previous steps, so ensure that those are related between them using the name.
- `spec.clusterDeploymentRef.name`: This represent the name of our ClusterDeployment, will be created in the next step, so just catch the name and reflect it here.
- `spec.networking.clusterNetwork` and `spec.networking.serviceNetwork`: Are references to internal communication, so ensure that are not overlapped between them.
- `spec.networking.machineNetwork.cidr`: Represents the network range for external communication, so ensure you use the same range as you node will use to communicate with outside.

**NOTE**: We **DON'T** need the API and Ingress VIP for this kind of cluster, Assisted Service will figure it out using the `spec.networking.machineNetwork.cidr` element in the CR.

This is a sample as how should looks like on a IPv6 environment

```
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: lab-cluster-aci
  namespace: open-cluster-management
spec:
  clusterDeploymentRef:
    name: lab-cluster
  imageSetRef:
    name: openshift-v4.8.0
  networking:
    clusterNetwork:
      - cidr: "fd01::/48"
        hostPrefix: 64
    serviceNetwork:
      - "fd02::/112"
    machineNetwork:
      - cidr: "2620:52:0:1302::/64"
  provisionRequirements:
    controlPlaneAgents: 1
  sshPublicKey: 'ssh-rsa adasdlkasjdlklaskdjadoipjasdoiasj root@xxxxXXXXxxx'
```

#### Multi Node Cluster Definition

For Multi Node Openshift we need to specify the next things:

- `spec.provisionRequirements.controlPlaneAgents`: Set to **3**, this means that we just want a ControlPlane based on 3 Master nodes.
- `spec.imageSetRef`: This will reference the ClusterImageSet created in previous steps, so ensure that those are related between them using the name.
- `spec.clusterDeploymentRef.name`: This represent the name of our ClusterDeployment, will be created in the next step, so just catch the name and reflect it here.
- `spec.networking.clusterNetwork` and `spec.networking.serviceNetwork`: Are references to internal communication, so ensure that are not overlapped between them.
- `spec.apiVIP` and `spec.ingressVIP`: These elements reference the API and Ingress addresses for the OCP Spoke cluster, ensure that are not the same as you hub cluster.

**NOTE**: We **DON'T** need the `spec.networking.machineNetwork.cidr` for this kind of cluster, Assisted Service will figure it out using the `spec.apiVIP` and `spec.ingressVIP` elements in the CR.

This is a sample as how should looks like on a IPv6 environment

```
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: lab-cluster-aci
  namespace: open-cluster-management
spec:
  clusterDeploymentRef:
    name: lab-cluster
  imageSetRef:
    name: openshift-v4.8.0
  apiVIP: "2620:52:0:1302::3"
  ingressVIP: "2620:52:0:1302::2"
  networking:
    clusterNetwork:
      - cidr: "fd01::/48"
        hostPrefix: 64
    serviceNetwork:
      - "fd02::/112"
  provisionRequirements:
    controlPlaneAgents: 3
  sshPublicKey: 'ssh-rsa adasdlkasjdlklaskdjadoipjasdoiasj root@xxxxXXXXxxx'
```

**NOTE**: This is also the CR where you will diagnose the issues in the deployment when you trigger it up, more concretely in the field `status.conditions` are all the relevant fields on the deployment status side.

---

Continuing with the **Spoke cluster definition and deployment** components, the next one is:

- **ClusterDeployment**: This element represent a Cluster as you use to see on the SaaS UI of Assisted Installer, and it's referenced from the `AgentClusterInstall` CR that contains the details regarding addressing, name, nodes, etc... . Also this CR belongs to Hive API as an extension, it will need to have access to a **FeatureGate** mentioned in a past section called `AlphaAgentInstallStrategy`, so be sure that it's already enabled, if not you can do it using this patch:

```
oc patch hiveconfig hive --type merge -p '{"spec":{"targetNamespace":"hive","logLevel":"debug","featureGates":{"custom":{"enabled":["AlphaAgentInstallStrategy"]},"featureSet":"Custom"}}}'
```

The most important fields on this CR are the next:

- `spec.baseDomain` and `spec.clusterName`: Which represent the ClusterName and the Domain for it, so in this case for example the API address will be something like `api.lab-spoke.alklabs.com` and the ingress will be represented with something like `*.apps.lab-spoke.alklabs.com`.
- `spec.clusterInstallRef`: Represents the reference to the `AgentClusterInstall` created before, so be sure you are pointing to the right name.
- `spec.pullSecretRef.name`: Points to the PullSecret's name created in the section before this one.

This is a sample as how should looks like on a IPv6 environment

```
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: lab-cluster
  namespace: open-cluster-management
spec:
  baseDomain: alklabs.com
  clusterName: lab-spoke
  controlPlaneConfig:
    servingCertificates: {}
  installed: false
  clusterInstallRef:
    group: extensions.hive.openshift.io
    kind: AgentClusterInstall
    name: lab-cluster-aci
    version: v1beta1
  platform:
    agentBareMetal:
      agentSelector:
        matchLabels:
          bla: "aaa"
  pullSecretRef:
    name: assisted-deployment-pull-secret
```

- **NMState Config**: This is an **optional** configuration that you want to add when the Network configuration need some adjustments like work with Bonding or use a concrete VLAN or just to declare an Static IP. The NMState it's a generic/standard configuration that could be used in a separated way of Assisted Installer/ACM and the [documentation can be found here](https://github.com/nmstate/nmstate) and [here are some examples](https://nmstate.io/examples.html). One NMState profile will map in a relation of 1-1 to an InfraEnv (we will cover this one later) and this profile should cover all nodes involved on the cluster.

This is a sample as how should looks like on a IPv6 environment

```
apiVersion: agent-install.openshift.io/v1beta1
kind: NMStateConfig
metadata:
  name: assisted-deployment-nmstate-lab-spoke
  labels:
    cluster-name: nmstate-lab-spoke
spec:
  config:
    interfaces:
      - name: bond99
        type: bond
        state: up
        ipv6:
          address:
          - ip:2620:52:0:1302::100
            prefix-length: 64
          enabled: true
        link-aggregation:
          mode: balance-rr
          options:
            miimon: '140'
          slaves:
          - eth0
          - eth1
  interfaces:
    - name: "eth0"
      macAddress: "02:00:00:80:12:14"
    - name: "eth1"
      macAddress: "02:00:00:80:12:15"
```

- **InfraEnv**: When you creates this CR, you are telling the Assisted Service that you want to create the final ISO to be mounted on the destination nodes, so this is the final step of the Manifest creation phase.

The most important fields on this CR are the next:

- `spec.clusterRef.name` and `spec.clusterRef.namespace`: This will reference the Name and the Namespace of our `ClusterDeployment` CR and where is located, so be sure that you are pointing to the right ones.
- `spec.agentLabelSelector.matchLabels`: Should be the same as you created before in the other CR's.
- `spec.pullSecretRef.name`: Should point to the right PullSecret created in the previous stage.
- `spec.sshAuthorizedKey`: Yes, again, this is in case something goes wrong when the Host is booting with the Discovery ISO and cannot pull the image, or maybe fails in other thing... this will allow us to jump into the node and troubleshoot what it's happening.

This is a sample as how should looks like.

```
apiVersion: agent-install.openshift.io/v1beta1
kind: InfraEnv
metadata:
  name: lab-env
  namespace: open-cluster-management
spec:
  clusterRef:
    name: lab-cluster
    namespace: open-cluster-management
  sshAuthorizedKey: 'ssh-rsa adasdlkasjdlklaskdjadoipjasdoiasj root@xxxxXXXXxxx'
  agentLabelSelector:
    matchLabels:
      bla: "aaa"
  pullSecretRef:
    name: assisted-deployment-pull-secret
```