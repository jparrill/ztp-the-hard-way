Table of contents:

<!-- TOC depthfrom:1 orderedlist:false -->

- [Disconnected ZTP Flow Hub deployment](#disconnected-ztp-flow-hub-deployment)
  - [Pre Requirements Phase](#pre-requirements-phase)
  - [ACM Deployment in a disconnected Environment](#acm-deployment-in-a-disconnected-environment)
  - [Manifest Creation Phase](#manifest-creation-phase)
    - [Hub Basic elements creation](#hub-basic-elements-creation)
    - [Spoke cluster definition](#spoke-cluster-definition)
      - [SNO Cluster Definition](#sno-cluster-definition)
      - [Multi Node Cluster Definition](#multi-node-cluster-definition)
    - [Spoke cluster deployment](#spoke-cluster-deployment)
      - [Fully Automated ZTP](#fully-automated-ztp)
      - [Manual Spoke cluster deployment](#manual-spoke-cluster-deployment)

<!-- /TOC -->

# Disconnected ZTP Flow Hub deployment

In an ideal world we try just pull the ACM Operator image from the OperatorHub platform once mirrored from Internet, but here in the real world, the ACM v2.3.0 is not released yet, so we need to follow [these instructions](https://github.com/open-cluster-management/deploy#lets-get-started) in order to deploy a non-released ACM version.

Also the Disconnected world is not easy so we will try to explain which are the steps to do it in a right way and following supported procedures.

This time we will follow the disconnected diagram we've seen before:

![](/assets/ztp-flow-disconnected.png)

## Pre Requirements Phase

To do it in a regular manner and as a pre-requirement for the OCP deployment we need to (The links bellow points you to the official documentation):

- [Deploy an HTTP server](https://access.redhat.com/documentation/es-es/red_hat_enterprise_linux/8/html/deploying_different_types_of_servers/setting-apache-http-server_deploying-different-types-of-servers)
- [Deploy an Internal Registry server](https://docs.openshift.com/container-platform/4.7/installing/installing_bare_metal_ipi/ipi-install-installation-workflow.html#ipi-install-creating-a-disconnected-registry_ipi-install-configuration-files)
- [Mirror the OpenShift Container Platform Release for the Spoke Clusters and host it in an Internal Registry](https://docs.openshift.com/container-platform/4.7/installing/installing-mirroring-installation-images.html#installing-mirroring-installation-images)
- [Mirror the OLM into your brand new Internal Registry](https://docs.openshift.com/container-platform/4.7/operators/admin/olm-restricted-networks.html)
- [Download and Host the RHCOS LiveISO and RootFS on a HTTP server](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/)
- Open Firewall rules to allow external host to access the hosted data
- Ensure DNS Entries are placed and DHCP is well configured

If you did this in a previous step to deploy the Hub, perfect, if not, you will need to do this before to deploy the Hub cluster (The Hub cluster is the one that will manage the other OCP clusters, we can call it, the father)

We will point to the right resource to go through all these pre-requisites in order to help you understand the procedure and how it works (The links points to every step 1-by-1 in the documentation of this repository).

- [**Host Internal resources (Registry and HTTPD)**](/docs/prerequirements/host-internal-resources.md): Contains the necessary things to raise up a HTTPD, Internal Registry and Download the ISO's and RootFS files to be hosted in the node
- [**Mirror OCP Release**](/docs/prerequirements/mirror-ocp-release.md): Contains the way to mirror an OCP Release.
- [**Mirror OLM Marketplace**](/docs/prerequirements/mirror-olm.md): Contains the way to mirror the OLM in order to see it in a disconnected environment.

After going through these steps, we can continue with the typical flow.

But first we need to deploy the OpenShift Hub:

- if you already did this step, continue on [ACM Deployment](#acm-deployment-in-a-disconnected-environment)
- If not, please go here and follow the [instructions for the OpenShift Hub Cluster](/docs/prerequirements/ocp4-ipi-deployment.md)

---

## ACM Deployment in a disconnected Environment

go to the OpenShift Marketplace and look for the "Red Hat Advance Cluster Management" operator and the deploy will start. It takes a while to finish, so please be patience.

**NOTE**: If you are from QE, DEV or any Red Hat Associate that wanna work with Downstreams versions you need to ask for permissions for this kind of images in the Slack Channel `#forum-acm`. If you already have permissions to do this, you will need to do some extra steps **[explained here](/docs/prerequirements/acm-downstream-deployment.md)**.

Once the ACM deployment finishes, the first two steps (Pre-requisites and ACM Deployment) should be already filled, but to be 100% sure let's check a couple of things (Ensure you have your KUBECONFIG loaded)

```yaml
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

**NOTE**: If this is not the same content as you have already in your HiveConfig CR, please ensure that you apply this manifests, if not another CRD called ClusterDeployment will fail in future steps. You can also use a `patch` command:

```
oc patch hiveconfig hive --type merge -p '{"spec":{"targetNamespace":"hive","logLevel":"debug","featureGates":{"custom":{"enabled":["AlphaAgentInstallStrategy"]},"featureSet":"Custom"}}}'
```

## Manifest Creation Phase

### Hub Basic elements creation

This phase could be done in an automated way but we want to explain 1-by-1 what we are creating here.

- **ClusterImageSet**: This manifest should contain a reachable OCP version that will be pulled from Hive and Assisted Installer in order to deploy an Spoke cluster, and this is how looks like:

```yaml
apiVersion: hive.openshift.io/v1
kind: ClusterImageSet
metadata:
  name: openshift-v4.8.0
  namespace: open-cluster-management
spec:
  releaseImage: bm-cluster-1-hyper.e2e.bos.redhat.com:5000/ocp4:4.8.0-fc.9-x86_64
```

- **AsistedServiceConfig**: This is an **optional** ConfigMap that could be used to customize the Assisted Service pod deployment using an annotation in the Operand (we will go deep in this topic later).

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: assisted-service-config
  namespace: open-cluster-management
  labels:
    app: assisted-service
data:
  LOG_LEVEL: "debug"
```

**NOTE**: We don't recommend to use this functionality in production environments and also it's not supported.

- **Private Key**: This is a Secret created that contains the private key that will be used by Assisted Service pod.

```yaml
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

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: assisted-deployment-pull-secret
  namespace: open-cluster-management
stringData:
  .dockerconfigjson: '{"auths":{"registry.ci.openshift.org":{"auth":"dXNlcjiZ3dasdNTSFffsafzJubE80LVYngtMlRGdw=="},"registry.svc.ci.openshift.org":{"auth":"dasdaddjo3b1NwNlpYX2kyVLacctNcU9F"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGGMVlTNkk1NlVQUQ==","lab-installer.lab-net:5000":{"auth":"ZHVtbXk6ZHVtbXk=","email":"jhendrix@karmalabs.com"}}}'
```

- **Mirror Configuration**: This is a ConfigMap that contains the data to be injected on the `DiscoveryImage` and also in the `PointerIgnition` that happens after writing the `OSTREE` image to the OCP Node disk. It includes two parts:

  - `data.ca-bundle.crt`: Which contains the CA Certificate of our Internal Registry
  - `data.registries.conf`: Which contains the file that will be injected in the `/etc/containers/registries.conf` path and will act as a ICSP

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: hyper1-mirror-config
  namespace: open-cluster-management
  labels:
    app: assisted-service
data:
  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    MIIGJzCCBA+gAwIBAgIUcuRdl0sEsCZMPWuE44snY/MLgcowDQYJKoZIhvcNAQEL
    BQAwgYgxCzAJBgNVBAYTAlVTMRYwFAYDVQQIDA1NYXNzYWNodXNldHRzMREwDwYD
    VQQHDAhXZXN0Zm9yZDEPMA0GA1UECgwGUmVkSGF0MQ0wCwYDVQQLDARNR01UMS4w
    ...
    ...
       GGfmDnicADMISxGIDnfhPUf+GllZtEn8D+c6WyfnDQMfqy9A56stxHWmwdlTf+UM
    6Rf1YNZC6XaR2GzJTz8mdiyG4L/cG6um65TigWOjaAOfD5ecei+d0maqmw==
    -----END CERTIFICATE-----
  registries.conf: |
    unqualified-search-registries = ["registry.access.redhat.com", "docker.io"]

    [[registry]]
      prefix = ""
      location = "quay.io/acm-d"
      mirror-by-digest-only = true

      [[registry.mirror]]
        location = "bm-cluster-1-hyper.e2e.bos.redhat.com:5000/rhacm2"

    [[registry]]
      prefix = ""
      location = "quay.io/ocpmetal"
      mirror-by-digest-only = true

      [[registry.mirror]]
        location = "bm-cluster-1-hyper.e2e.bos.redhat.com:5000/ocpmetal"
...
...
```

- **AgentServiceConfig**: This is the Operand, the Assisted Service pod that handles the spoke clusters deployment's.

```yaml
apiVersion: agent-install.openshift.io/v1beta1
kind: AgentServiceConfig
metadata:
  name: agent
  namespace: open-cluster-management
  ### This is the annotation that injects modifications in the Assisted Service pod
  annotations:
    unsupported.agent-install.openshift.io/assisted-service-configmap: "assisted-service-config"
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
  mirrorRegistryRef:
    name: "hyper1-mirror-config"
  osImages:
    - openshiftVersion: "4.8"
      version: "48.84.202106102231-0"
      url: "http://[2620:52:0:1303::1]/rhcos-4.8.0-fc.9-x86_64-live.x86_64.iso"
      rootFSUrl: "http://[2620:52:0:1303::1]/rhcos-live-rootfs.x86_64.img"
```

**NOTE**: Ensure you put the right IP or name of the server you are hosting from the ISO and the RootFS.

Once created all of these manifests we need to wait until a pod similar to `assisted-service-XXxxxXXX-XXXxxxx` is created and in READY state.

From here we will create the manifest that regards the spoke clusters, these above ones are only necessary for the Hub cluster.

### Spoke cluster definition

In the Manifest creation phase we still need to define the relevant CR's that will represent our spoke cluster, said that we will continue with the relevant elements for the managed clusters.

:warning: **The spoke cluster manifests should be located in a NameSpace with the same name as the ClusterName**: so please be very careful here!

First thing we need to do is create a NameSpace that will host the CR's for our spoke cluster, our spoke name will be `mgmt-spoke1` so all the resources will be created there. Let's create the NS in first instance:

```
oc create ns mgmt-spoke1
oc project mgmt-spoke1
```

Now we will begin the CR creation.

:warning: **You need to recreate again the PullSecret** that you created before on the `open-cluster-management` namespace but this time in the Spoke dedicated namespace, so this is how looks like:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: assisted-deployment-pull-secret
  namespace: mgmt-spoke1
stringData:
  .dockerconfigjson: '{"auths":{"registry.ci.openshift.org":{"auth":"dXNlcjiZ3dasdNTSFffsafzJubE80LVYngtMlRGdw=="},"registry.svc.ci.openshift.org":{"auth":"dasdaddjo3b1NwNlpYX2kyVLacctNcU9F"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGGMVlTNkk1NlVQUQ==","lab-installer.lab-net:5000":{"auth":"ZHVtbXk6ZHVtbXk=","email":"jhendrix@karmalabs.com"}}}'
```

- **AgentClusterInstall**: This is one of the most important elements to define, the first thing is to decide which kind of deployment you need to do. If it's SNO versus Multinode is really important here so let's focus in both cases

#### SNO Cluster Definition

For Single Node OpenShift we need to specify the next things:

- `spec.provisionRequirements.controlPlaneAgents`: Set to **1**, this means that we just want a ControlPlane based on 1 Master node.
- `spec.imageSetRef`: This will reference the ClusterImageSet created in previous steps, so ensure that those are related between them using the name.
- `spec.clusterDeploymentRef.name`: This represent the name of our ClusterDeployment, will be created in the next step, so just catch the name and reflect it here.
- `spec.networking.clusterNetwork` and `spec.networking.serviceNetwork`: Are references to internal communication, so ensure that are not overlapped between them.
- `spec.networking.machineNetwork.cidr`: Represents the network range for external communication, so ensure you use the same range as you node will use to communicate with outside.

**NOTE**: We **DON'T** need the API and Ingress VIP for this kind of cluster, Assisted Service will figure it out using the `spec.networking.machineNetwork.cidr` element in the CR.

This is a sample as how should looks like on a IPv6 environment

```yaml
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: mgmt-spoke1
  namespace: mgmt-spoke1
spec:
  clusterDeploymentRef:
    name: mgmt-spoke1
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
  sshPublicKey: "ssh-rsa adasdlkasjdlklaskdjadoipjasdoiasj root@xxxxXXXXxxx"
```

#### Multi Node Cluster Definition

For Multi Node OpenShift we need to specify the next things:

- `spec.provisionRequirements.controlPlaneAgents`: Set to **3**, this means that we just want a ControlPlane based on 3 Master nodes.
- `spec.imageSetRef`: This will reference the ClusterImageSet created in previous steps, so ensure that those are related between them using the name.
- `spec.clusterDeploymentRef.name`: This represent the name of our ClusterDeployment, will be created in the next step, so just catch the name and reflect it here.
- `spec.networking.clusterNetwork` and `spec.networking.serviceNetwork`: Are references to internal communication, so ensure that are not overlapped between them.
- `spec.apiVIP` and `spec.ingressVIP`: These elements reference the API and Ingress addresses for the OCP Spoke cluster, ensure that are not the same as you hub cluster.

**NOTE**: We **DON'T** need the `spec.networking.machineNetwork.cidr` for this kind of cluster, Assisted Service will figure it out using the `spec.apiVIP` and `spec.ingressVIP` elements in the CR.

This is a sample as how should looks like on a IPv6 environment

```yaml
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: mgmt-spoke1
  namespace: mgmt-spoke1
spec:
  clusterDeploymentRef:
    name: mgmt-spoke1
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
  sshPublicKey: "ssh-rsa adasdlkasjdlklaskdjadoipjasdoiasj root@xxxxXXXXxxx"
```

**NOTE**: This is also the CR where you will diagnose the issues in the deployment when you trigger it up, more concretely in the field `status.conditions` are all the relevant fields on the deployment status side.

---

Continuing with the **Spoke cluster definition and deployment** components, the next one is:

- **ClusterDeployment**: This element represent a Cluster as you use to see on the SaaS UI of Assisted Installer, and it's referenced from the `AgentClusterInstall` CR that contains the details regarding addressing, name, nodes, etc... . Also this CR belongs to Hive API as an extension, it will need to have access to a **FeatureGate** mentioned in a past section called `AlphaAgentInstallStrategy`, so be sure that it's already enabled, if not you can do it using this patch:

```sh
oc patch hiveconfig hive --type merge -p '{"spec":{"targetNamespace":"hive","logLevel":"debug","featureGates":{"custom":{"enabled":["AlphaAgentInstallStrategy"]},"featureSet":"Custom"}}}'
```

The most important fields on this CR are the next:

- `spec.baseDomain` and `spec.clusterName`: Which represent the ClusterName and the Domain for it, so in this case for example the API address will be something like `api.lab-spoke.alklabs.com` and the ingress will be represented with something like `*.apps.lab-spoke.alklabs.com`.
- `spec.clusterInstallRef`: Represents the reference to the `AgentClusterInstall` created before, so be sure you are pointing to the right name.
- `spec.pullSecretRef.name`: Points to the PullSecret's name created in the section before this one.

This is a sample as how should looks like on a IPv6 environment

```yaml
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: mgmt-spoke1
  namespace: mgmt-spoke1
spec:
  baseDomain: alklabs.com
  clusterName: mgmt-spoke1
  controlPlaneConfig:
    servingCertificates: {}
  installed: false
  clusterInstallRef:
    group: extensions.hive.openshift.io
    kind: AgentClusterInstall
    name: mgmt-spoke1
    version: v1beta1
  platform:
    agentBareMetal:
      agentSelector:
        matchLabels:
          cluster-name: "mgmt-spoke1"
  pullSecretRef:
    name: assisted-deployment-pull-secret
```

- **KlusterletAddonConfig**: This configuration will contain the enabled Addons that ACM will deploy on that cluster after the creation.

The most important fields on this CR are the next:

- `spec.clusterName` and `spec.clusterNamespace` as it says, it's referencing the cluster's name, we usually set both as the same value.
- `spec.clusterLabels` this field references some labels we want to set.

The addons down bellow only has one field inside of every one, which is `enabled:` `true` or `false`

- `spec.applicationManager`: **Required field**, it is in charge to deploy the addon which manages the Applications on the spoke cluster.
- `spec.certPolicyController`: **Required field**, it is in charge to deploy the addon which manages the Certificates.
- `spec.iamPolicyController`: **Required field**, it is in charge to deploy the addon which manages the Identity and Access Management.
- `spec.policyController`: **Required field**, it is in charge to deploy the addon which manages the Policies.
- `spec.searchCollector`: **Required field**, it is in charge to deploy the addon which manages the component who collect the cluster data and index it for search engine.
- `spec.workManager`: **Optional field**, it is in charge to deploy the addon which manages the workloads on the spoke cluster.

There are more Addons and fields, you can check them with `oc explain KlusterletAddonConfig.spec`. And this is sample of the CR:

```
apiVersion: agent.open-cluster-management.io/v1
kind: KlusterletAddonConfig
metadata:
  name: mgmt-spoke1
  namespace: mgmt-spoke1
spec:
  clusterName: mgmt-spoke1
  clusterNamespace: mgmt-spoke1
  clusterLabels:
    cloud: auto-detect
    vendor: auto-detect
  workManager:
    enabled: true
  applicationManager:
    enabled: false
  certPolicyController:
    enabled: false
  iamPolicyController:
    enabled: false
  policyController:
    enabled: false
  searchCollector:
    enabled: false
```

- **ManagedCluster**: This CR contains some details of the spoke cluster.

The most important fields on this CR are the next:

- `spec.hubAcceptsClient`: **Optional field**, hubAcceptsClient represents that hub accepts the joining of Klusterlet agent on the managed cluster with the hub, mandatory if you want an automatic linked spoke cluster.

There are more fields, you can check them with `oc explain ManagedCluster.spec`. And this is sample of the CR:

```
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: mgmt-spoke1
  namespace: mgmt-spoke1
spec:
  hubAcceptsClient: true
```

- **NMState Config**: This is an **optional** configuration that you want to add when the Network configuration need some adjustments like work with Bonding or use a concrete VLAN or just to declare an Static IP. The NMState it's a generic/standard configuration that could be used in a separated way of Assisted Installer/ACM and the [documentation can be found here](https://github.com/nmstate/nmstate) and [here are some examples](https://nmstate.io/examples.html). One NMState profile will map in a relation of 1-1 to an InfraEnv (we will cover this one later) and this profile should cover all nodes involved on the cluster.

This is a sample as how should looks like a SNO on a IPv6 environment

```yaml
apiVersion: agent-install.openshift.io/v1beta1
kind: NMStateConfig
metadata:
  name: mgmt-spoke1
  namespace: mgmt-spoke1
  labels:
    cluster-name: mgmt-spoke1
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
- `spec.ignitionConfigOverride`: **Optional**, This is important only if you wanna modify something that you want to include it into the Discovery ISO ignition.
- `spec.nmStateConfigLabelSelector`: **Optional**, This will make the relationship between the NMState manifest you had created on the previous step and the InfraEnv that will trigger the ISO creation on the Assisted Service pod.

This is a sample as how should looks like.

```yaml
apiVersion: agent-install.openshift.io/v1beta1
kind: InfraEnv
metadata:
  name: mgmt-spoke1
  namespace: mgmt-spoke1
spec:
  additionalNTPSources:
    - clock.redhat.com
  clusterRef:
    name: mgmt-spoke1
    namespace: mgmt-spoke1
  sshAuthorizedKey: "ssh-rsa adasdlkasjdlklaskdjadoipjasdoiasj root@xxxxXXXXxxx"
  agentLabelSelector:
    matchLabels:
      cluster-name: "mgmt-spoke1"
  pullSecretRef:
    name: assisted-deployment-pull-secret
  ignitionConfigOverride: '{"ignition": {"version": "3.1.0"}, "storage": {"files": [{"path": "/etc/someconfig", "contents": {"source": "data:text/plain;base64,aGVscGltdHJhcHBlZGluYXN3YWdnZXJzcGVj"}}]}}'
  nmStateConfigLabelSelector:
    matchLabels:
      cluster-name: mgmt-spoke1
```

### Spoke cluster deployment

To achieve this part we need to ensure (again) that the Hub cluster it's based on IPI and has the metal3 pods, to validate that just execute this, if the output it's empty this process will follow the manual way of work if not, the process that we will follow it's the real ZTP.

```
oc get pod -A | grep metal3
```

#### Fully Automated ZTP

This first flow will orchestrated from Ironic and Metal3 containers and the CRD involved will be the `BareMetalHost`. As a pre-step we need to ensure that Metal3 pod can check other namespaces and look for BareMetalHost outside of their own one, to allow that, you need to execute this:

```sh
oc patch provisioning provisioning-configuration --type merge -p '{"spec":{"watchAllNamespaces": true}}'
```

Once done we will need to create our new BareMetalHosts on the same Namespace as the Assisted Service is running in order to allow `Bare Metal Agent Controller` to decorate the BMH with the URL of the ISO generated by assisted installer.

First we will need to create a Secret that contains the credentials for the BMC (Baseboard Management Controller), for that we need a secret like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: bmc-secret1
  namespace: mgmt-spoke1
data:
  password: YWxrbm9wZmxlcgo=
  username: YW1vcmdhbnQK
type: Opaque
```

And these are the most important fields into the BareMetalHost CRD:

- `metadata.labels.infraenvs.agent-install.openshift.io`: This needs to point InfraEnv's name of the manifest created in the precious step.
- `metadata.annotations.inspect.metal3.io`: **Mandatory**, This one should be set to `disabled`.
- `metadata.annotations.bmac.agent-install.openshift.io/hostname`: **Optional**, This annotation allows you to set an static hostname for your host.
- `metadata.annotations.bmac.agent-install.openshift.io/role`: **Optional**, This annotation allows you to set an static role for your host.
- `spec.online`: Should be true, in order to allow Ironic to boot the node.
- `spec.automatedCleaningMode`: Should be disabled, this is only relevant on PXE environments.
- `spec.bootMACAddress`: This is the MAC address that will be use to boot the node.
- `spec.bmc.address`: Redfish address that you need to reach to contact with the node's BMC.
- `spec.bmc.credentialsName`: The secret's name that contains the access to the BMC.

So, with that let's take a look to a BareMetalHost CR sample

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: mgmt-spoke1-master0
  namespace: mgmt-spoke1
  labels:
    infraenvs.agent-install.openshift.io: "mgmt-spoke1"
  annotations:
    ## Disable the Introspection
    inspect.metal3.io: disabled
    ## Set Static Hostname
    bmac.agent-install.openshift.io/hostname: "ipv6-spoke1-master0"
    ## Set Static Role
    bmac.agent-install.openshift.io/role: "master"
spec:
  online: true
  bmc:
    address: redfish-virtualmedia+http://[2620:52:0:1302::d7c]:8000/redfish/v1/Systems/3e6f03bb-2301-49c9-a562-ad488dca513c
    credentialsName: bmc-secret1
    disableCertificateVerification: true
  bootMACAddress: ee:bb:aa:ee:1e:1a
  automatedCleaningMode: disabled
```

#### Manual Spoke cluster deployment

This flow is easier but it's fully manual:

1. We need to get the ISO URL from the InfraEnv CR with this command:

```
oc get infraenv mgmt-spoke1 -o jsonpath={.status.isoDownloadURL}
```

2. Then download and host it in a HTTPD server.
3. Access to the BMC and try to mount the ISO hosted
4. Boot the node and wait for it to be self-registered against the Assisted Service.
5. Now we need to check the AgentClusterInstall to verify that on the `.status.conditions` all the requirements are met.

```
oc get agentclusterinstall -o yaml
```

6. Edit the agent/s registered, changing the `hostname` and approving them.
7. The deployment will be self triggered.

---

With that I think we can say that the flow should finish in a right way, but if the deployment does not finishes or maybe we see some issues on the `AgentClusterInstall` CR created, we can take a look to the troubleshooting documentation.
