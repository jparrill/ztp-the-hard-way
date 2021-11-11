# Automation using RHACM and ArgoCD with PolicyGenerator
<!-- TOC -->

- [Architecture and Workflow](#architecture-and-workflow)
- [ArgoCD and PolicyGenerator deployment](#argocd-and-policygenerator-deployment)
    - [GitOps Operator](#gitops-operator)
    - [PolicyGenerator](#policygenerator)
- [How to organize the Automation Templates repository](#how-to-organize-the-automation-templates-repository)
    - [Recommendations](#recommendations)
    - [Considerations](#considerations)
- [RHACM Automated and highly scalable ZTP flow](#rhacm-automated-and-highly-scalable-ztp-flow)
    - [Cluster Deployment Phase](#cluster-deployment-phase)
        - [ Deployment of the CNF Features](#deployment-of-the-cnf-features)
        - [Filling your repo with Policies and Clusters](#filling-your-repo-with-policies-and-clusters)
    - [SNO Clusters Config Phase](#sno-clusters-config-phase)
- [Creating a New Sites](#creating-a-new-sites)
    - [Baking a new Site/Spoke Cluster](#baking-a-new-sitespoke-cluster)
    - [Following a Cluster Deployment](#following-a-cluster-deployment)
- [Creating/Updating policies on the Git repo](#creatingupdating-policies-on-the-git-repo)
    - [Baking a new policyGenTemplate](#baking-a-new-policygentemplate)
    - [Following a Policy Deployment](#following-a-policy-deployment)
- [FAQ](#faq)
    - [Modifying a policy in the repo](#modifying-a-policy-in-the-repo)
    - [Modifying a SNO already deployed](#modifying-a-sno-already-deployed)
    - [Enable the user/pass authentication in the automation](#enable-the-userpass-authentication-in-the-automation)
- [Troubleshooting](#troubleshooting)
    - [Validating a New SNO deployment](#validating-a-new-sno-deployment)
        - [Cheatsheet](#cheatsheet)
    - [Checking the Policies](#checking-the-policies)
- [References](#references)
    - [Troubleshooting](#troubleshooting-1)
    - [Disaster Recovery](#disaster-recovery)

<!-- /TOC -->

Basically this is the path to deploy more than ~250 spoke clusters, as you could know it's more complicated that the standalone Red Hat ACM but the performance in large scales is better.

## Architecture and Workflow

Here we will have some important components:

- RHACM: It will deploy the Spoke clusters and it will execute the Policies over those spoke clusters
- ArgoCD: This piece contains 2 Hooks that pull the automation templates from your repo and parse them with the PolicyGenerator.
- PolicyGenerator: It's a logic piece that parses your Automation templates repo and transform them into real ACM policies

This is the workflow diagram:

![img](../../assets/ztp-policygen-workflow.png)


## ArgoCD and PolicyGenerator deployment

### GitOps Operator

To deploy the GitOps Operator (ArgoCD) is quite simple, we just need to create the proper subscriptions to allow the OLM to start doint their thing:

```
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  config:
    env:
    - name: ARGOCD_CLUSTER_CONFIG_NAMESPACES
      value: openshift-gitops, ztp-clusters 
  channel: "stable"
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  # Modify source name of the catalogsource for isolated network deployments
  source: redhat-operator-index 
  sourceNamespace: openshift-marketplace
```

If you are working on a disconnected environment you will need to sync first the OLM Operator and create the ICSPs on the Hub cluster:

```
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: gitops-operator-icsp
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion1.mgmt-hub-2.hqplan.lan:5000/olm/openshift-gitops-1-tech-preview-gitops-rhel8-operator
    source: registry.redhat.io/openshift-gitops-1-tech-preview/gitops-rhel8-operator
  - mirrors:
    - bastion1.mgmt-hub-2.hqplan.lan:5000/olm/openshift-gitops-1-kam-delivery-rhel8
    source: registry.redhat.io/openshift-gitops-1/kam-delivery-rhel8
...
...
```

> :warning: **NOTE:** We wil put the whole ICSP on the sample folder as others ones.

### PolicyGenerator

We will work with at least 2 main components:

- Our Git repository which contains the Templates for Automation and the other RHACM Policies. We will iterate over this repo to enhance our templates and add more functionality to our automation.
- The [cnf-features-deploy](https://github.com/openshift-kni/cnf-features-deploy) repo, which contains the Hooks, Jobs and any other components to check your templates repo and execute the proper automation.

This templates repo should contain at least 2 separated folders with Clusters and Policies, every folder will contain at least 2 components, the pre- and post- action hooks

- The pre hook will pull the latest revision of your templates repo and the concrete folder and save that revision in a ConfigMap
- The post hook will take consume that ConfigMap and evaluate if there are changes or not,

If there are changes it will take the deltas and will apply them into the Hub cluster, if not the pod will show a message saying “no changes”

The steps to deploy (just once) this hooks and components from this repo are the following (we will give much mmore detail later in other section):

- We need to clone the repo
- Modify the policies-app.yaml and clusters-app.yaml files in order to adapt it to the environment
- Ensure you have a Git repo exposed (Gogs in WC Lab) with the templates code even if the folders are empty just with the hooks Sample here
- Deploy the whole folder using kustomize engine

This action will deploy some objects, the most important one are 2 ArgoCD Applications which handle the pulls from the Git repository to have the policies updated on the Hub and SNOs as you have declared on Git.

![img](../../assets/ztp-argocd-apps.png)


For sure we will revisit this step to provide much more details about the PolicyGenerator deployment, but for now we will focus on how to start creating our Templates repo.

## How to organize the Automation Templates repository

The first things you need to have in mind is simple, the Policies and the Sites could be organized as you want, from in a single file until have a complex hierarchy using different folders, but let me remark the changes you need to do.

If you only have a flat folder inside of your policies folder or sites folder, you just need to ensure you have this field on the ArgoCD application you’ve deployed before (from [cnf-features-deploy](https://github.com/openshift-kni/cnf-features-deploy) repo, on the folder ztp/gitops-subscriptions/argocd/deployment and on the files `clusters-app.yaml` and `policies-app.yaml`:

```
source:
    path: ztp/gitops-subscriptions/argocd/resource-hook-example/siteconfig
    repoURL: https://github.com/openshift-kni/cnf-features-deploy
    targetRevision: master
```

Or if you have a folders hierarchy:

```
 source:
    directory:
      recurse: true   <------ THIS
    path: ztp/gitops-subscriptions/argocd/resource-hook-example/siteconfig
    repoURL: https://github.com/openshift-kni/cnf-features-deploy
    targetRevision: master
```

All of them will use something like virtual groups to assign Policies deployed to Spoke clusters managed by ACM more known as ManagedClusters.

### Recommendations

- We recommend to have a Control Group which will be the one with the production but a small one to ensure all works fine in production without touch production
- Another group which contains the updates that will be loaded in production to ensure all things have been considered before broke something in production
- If something was not captured by the hooks for some reason, just update the required file again with something that does not change nothing relevant, this will force the hook to be reexecuted and get the changes properly.
- Ensure you execute a Dry-Run with the generate-localy.sh script (Sample: ./generate-localy.sh site-policies/common-policies this will not do anything on the hub or spokes, just generate the policy files localy in order to verify that your files are well formed.
- If you wanna reuse a Source template ensure you override ALL the fields involved if not, they will be included in your definition (the previous advice it’s very useful to avoid this kind of issues)
- If you wanna include a new Source template, it’s a bit more difficult but it’s documented [here](https://github.com/openshift-kni/cnf-features-deploy/tree/master/ztp/resource-generator)

### Considerations

Every time you update the policies/sites in the repo, the hook will grab the updates from the respective Git folders and deploy the newest changes on the ACM. In the sites side is more complicated because the only reactive item will be the clusterLabels the other ones will modify the deployed clustersand this is not allowed (for now) on the clusters that already started a deployment.

> :warning: **NOTE:** If you modified something in the Policies directly on the Hub, will be overrided

If you include more templates on your container, please ensure you open a RFE into the [original Git repository](https://github.com/openshift-kni/cnf-features-deploy) because the Dev team will be aware of your new requirements.

## RHACM Automated and highly scalable ZTP flow

This flow will involve some phases:

- Cluster Deployment phase (SNOs)
- SNO Clusters Config Phase

Let’s get into all of them

### Cluster Deployment Phase

This is self-explanatory, in this phase the main purpose is, let ACM to create the proper resources to deploy the different SNO clusters so, the PlacementRule will point always to “local-cluster” because the piece in charge to create those cluster is the Infrastructure Operator.

Let’s take a look to this logic diagram and explain what we see:

![img](../../assets/ztp-policygen-workflow.png)

Going step by step the first thing we need to have in mind is that we will work mainly with 1 repository (this one) and to bootstrap the whole automation and start deploying the things (Only the first time) we will use this other one: https://github.com/openshift-kni/cnf-features-deploy

####  Deployment of the CNF Features

- First thing we need to do is download the mentioned repo https://github.com/openshift-kni/cnf-features-deploy and go to the ztp/gitops-subscriptions/argocd/deployment folder.
- Then we need to modify 2 files:
- clusters-app.yaml and policies-app.yaml, the relevant part in both cases will contain the same changes, this is the sample:

```
# Sample
    path: <path-to-the-clusters-folder>
    repoURL: <repo URL> 
    targetRevision: <Branch> 
```

And this is the real content that should have inside both files:

```
# clusters-app.yaml
  source:
    path: gitops-verizon/site-configs
    repoURL: http://dummy:dummy@bm-cluster-1-hyper.e2e.bos.redhat.com:3000/faredge-ztp/faregde-ztp.git
    targetRevision: rfe/argo_pipeline
```

```
# policies-app.yaml
  source:
    directory:
      recurse: true
    path: gitops-verizon/site-policies
    repoURL: http://dummy:dummy@bm-cluster-1-hyper.e2e.bos.redhat.com:3000/faredge-ztp/faregde-ztp.git
    targetRevision: rfe/argo_pipeline
```

Once you got that you need to, pointing to the hub cluster, execute oc apply -k . in the same folder as you have both files you’ve modified.

This action will deploy the hooks and will monitor the repo and the branch you set above, in order to look for changes in the repo and apply then when make sense. If you have the repo with your clusters already set there, the hook will start deploying the things.

#### Filling your repo with Policies and Clusters

At this moment you will have you repo empty, so let’s fill it up with the right things (let’s ignore for now the pre-reqs and hub-prereqs folders):

```
├── docs
├── gitops-templates
│   ├── hub-prereqs
│   ├── pre-reqs
│   ├── site-configs
│   └── site-policies
└── README.md
```

The site-configs and site-policies folders needs to hold the proper hooks (pre and post) for each folder (each one is different, so beware). You can grab an example from this url.

As you can imagine we already fill them up for you, you can check them in the concrete folders:

```
│   ├── site-configs
│   │   ├── post-sync.yaml
│   │   ├── pre-sync.yaml
│   └── site-policies
│       ├── cluster-specific-policies
│       ├── common-policies
│       ├── group-policies
│       ├── post-sync.yaml
│       ├── pre-sync.yaml
│       └── site-specific-policies
└── README.md`
```

Inside of site-configs they are just the hooks, and inside of site-policies we created a set of folders that will be our hierarchy on the policies execution.

- common-policies - Policies common for all clusters in all locations
- site-specific-policies - Policies for the same site (DU)
- group-policies - Policies that will apply for concrete groups inside of the same DU
- cluster-specific-policies - Policies for concrete clusters/SNOs

```
gitops-templates/site-policies
├── cluster-specific-policies
├── common-policies
│   ├── FE-common-ns.yaml
│   └── FE-common.yaml
├── group-policies
│   ├── FE-cnf-namespace.yaml
│   └── FE-cnf.yaml
├── post-sync.yaml
├── pre-sync.yaml
└── site-specific-policies
    ├── FE-LAB-namespace.yaml
    └── FE-LAB.yaml
```

We’ve separated the NS from the PolicyGen object just because it’s convenient. Now we can focus on the Clusters.

```
gitops-templates/site-configs
├── post-sync.yaml
├── pre-sync.yaml
├── du-namespace.yaml
└── du.yaml
```

This folder will contain the NS also and the SiteConfig object which contains the details for the whole DU, it means that you can put in that file more than one SNO and will stay grouped.

Ok, now it’s time to push our content to our git repo, and the hooks will do the rest:

```
git add -A
git commit -a -m "Adding clusters and policies"
git push gogs
```

The ArgoCD applications will enter in OutOfSync status and 2 pods will appear secuentally:

- The pre hook will pull the content from the repo and it will take the revision from that version and it will create a ConfigMap called rv with the revision. After the pre hook execution, if all ends in a success, the ArgoCD App will change to Synced- After that, the post hook will come in action and will use that revision as a base to get the git changes, parse the PolicyGen and SiteConfig and create/delete/change the proper objects from both sources.

From this point maybe the deployment didn’t started yet, this is normal, you need to ensure that the SNO clusters pre-reqs are filled, they need 3 objects for each SNO you want to deploy, we’ve put a sample of them on the gitops-version/pre-reqs/sno1 folder, you just need to execute an oc apply -k gitops-version/pre-reqs/sno1 against the hub cluster, it will create:

- The SNO Namespace - To store the proper objects for that cluster
- The SNO PullSecret - Credentials to access the InternalRegistry
- The SNO BMH Secret - Credentials to access the BMC of the SNO.

And now the deployment should start.

### SNO Clusters Config Phase

The policies as you’ve seen in a previous step, will be loaded via pre and post hook, and the objects will be created on the Hub cluster. The Policy Controller will wait there until a new cluster joins the managedclusters and contains the labels required to start applying the policies.

This is how should looks like the managed cluster to see the policies reacting and performing changes in the SNO clusters:

```
NAME    HUB ACCEPTED   MANAGED CLUSTER URLS   JOINED   AVAILABLE   AGE
sno-1   true                                  True     True        18h
```

And this are the policies:

![img](../../assets/ztp-rhacm-policies.png)

As you can see, the base policies are stored in 2 places, in the group namespace (which are called as common, group-du-sno and vz-wc-lab-policies) and also in the SNO’s namespace.
All of them, in this case are in Compliant state, so that means that the objects required to be created in Openshift, are there. The usual workflow, is from empty **COMPLIANCE STATE** > `NonCompliant > Compliant`. To stay in `NonCompliant` would means some things:

- The required object cannot be created
- The required object is not in the desired status
- The required object creation is in progress

Eventually the SNO will get rebooted because of the MachineConfigOperator behaviour. Every patch assigned to that operator will reboot the node after apply the new object, modifying the Ignition file of the SNO cluster and being applied after the reboot.

## Creating a New Sites

Ensure you already check the How to organize the repository section on this document before continue.

To update already existant will not redeploy anything, have this in mind, will just update some concete things like (for now) the `clusterLabels` .To create a new site maybe could be challenging but you can copy a sample and modify it as you want.

The current implementation for our Lab is using a DU flat file. This implementation should not be enough for production, but an starting point to start baking the real one.

Every group will be stored in their own namespace:

The site file labels are set on this spec `spec.clusters.*.clusterLabels` field and the policies will match these labels in order to match the policies deployed:

```
...
...
- clusterName: "sno-1"
    clusterType: sno
    clusterProfile: du
    clusterLabels:   <--- THIS
      group-du-sno: ""
      common: true
      siteName : "du-lab"
      infra: "faregde"
...
...
```

One file can contain multiple clusters, and anyone will have their own configuration, so no worries about specific configurations.

Once you have the SiteConfig ready to be pushed, ensure you creates the:

- Namespace for that SNO cluster on the Hub cluster
- The BMH Secret which should contain the User/Password to access the BMC of the server and should match the name you’ve included in the field `spec.clusters.*.nodes.*.bmcCredentialsName.name`
- The pull secret to access the Internal Image registry.

You have a folder with a sample in gitops-templates/pre-reqs/sno-1/ folder on the Git Repository.

> :warning: **NOTE**: We don’t recommend to store the secrets on the Git repo wihtout something like SealedSecrets which have native integration with argocd. (not included in the our Lab)

You can deploy the mentioned objects executing this command, if they are not created when you push things to the repo, no worries you can do it after this, you will see some error logs but the deployment will start after the object creation.:

```
oc apply -k gitops-templates/pre-reqs/sno-1
```

Now after the object creation you can push you things to Git and this will trigger the automation.

### Baking a new Site/Spoke Cluster

To create a new Site file, I recommend to copy a sample one and fill it as it should, all the fields are very relevant.

Let’s take a look to the Common section for all the clusters in this same site:

```
---
apiVersion: ran.openshift.io/v1
kind: SiteConfig
metadata:
  name: "du-alaska"
  namespace: "du-alaska"
spec:
  baseDomain: "faregde.lab"
  pullSecretRef:
    name: "assisted-deployment-pull-secret-sno-1"
  clusterImageSetNameRef: "openshift-v4.8.11"
  sshPublicKey: "ssh-rsa AAAAB3NzaC1yc2...
  clusters:
```

Some fields relevant here are the:

- pullSecretRef.name which points to the Pull Secret name in the SNO namespace
- clusterImageSetNameRef which is the ClusterImageSet object that point to the desired OCP release to be deployed

In the clusters section you will find this:

```
 ## SNO-1
  - clusterName: "sno-1"
    clusterType: sno
    clusterProfile: du
    clusterLabels:
      group-du-sno: ""
      common: true
      siteName : "alaska-du-lab"
      infra: "faregde"
      server: "HP"
      pao: "true"
      sriov: "true"
      sno: "true"
      mcp: "master"
    clusterNetwork:
      - cidr: "fd01::/48"
        hostPrefix: 64
    serviceNetwork:
      - "fd02::/112"
    machineNetwork:
      - cidr: "fd00:4888:2000:1184::/64"
    additionalNTPSources:
      - fd00:4888:2000:1099::11
    nodes:
      - hostName: "master-0.sno-1.faredge.lab"
        bmcAddress: "redfish-virtualmedia://[fd00:4888:2000:1185::26]/redfish/v1/Systems/1"
        bmcCredentialsName:
          name: "sno-1-master0"
        bootMACAddress: "b4:86:11:c3:bb:94"
        bootMode: "UEFI"
        rootDeviceHints:
          deviceName: "/dev/nvme0n1"
        cpuset: "0-2,32-34"
        ignitionConfigOverride: ''
        nodeNetwork:
          interfaces:
            - name: "ens1f0"
              macAddress: b4:86:11:c3:bb:94
          config:
            interfaces:
            - name: ens1f0.304
              type: vlan
              state: up
              vlan:
                base-iface: ens1f0
                id: 304
              'ipv6':
                enabled: true
                address:
                  - ip: fd00:4888:2000:1182::100
                    prefix-length: 64
                dhcp: false
            dns-resolver:
              config:
                server:
                - fd00:4888:2000:1099::11
            routes:
              config:
                - destination: '::/0'
                  next-hop-address: 'fd00:4888:2000:1182::'
                  next-hop-interface: ens1f0.304
```

There are many relevant things here:

- The clusterLabels will be matched by the policies engine to apply the policies in that SNO.
- The clusterNetwork and serviceNetwork should not be overlapped between eachother.
- The machineNetwork.cidr is the network address where the SNO will be deployed
- In the nodes section:
    - The bmcCredentialsName.name is the secret name created in the SNO namespace
    - The ignitionConfigOverride is a String which contains a JSON with the proper ignition customizations like partitioning or any other aspects you wanna change and will be applied in deployment time.
    - The nodeNetwork sections contains an nmstate file which contains the customizations on networking side.

### Following a Cluster Deployment

You can follow the deployment with this script, put that one on the bin path, and will help you:

```
#!/bin/bash
##
# Execution sample:
# ./watch-deployment sno-1
##

DEST_CLUSTER=${1}

if [[ -z ${DEST_CLUSTER} ]];then
  echo "Give me a clustername"
  exit 1
fi

export KUBECONFIG=<PATH TO KUBECONFIG>/kubeconfig
watch -n 5 " 
  echo '=====> BMH:'; \
  oc get bmh -n ${DEST_CLUSTER} ${DEST_CLUSTER}; \
  echo; echo '=====> AgentClusterInstall Messages:'; \
  oc get agentclusterinstall -n ${DEST_CLUSTER} ${DEST_CLUSTER} -o jsonpath={.status.conditions} | jq "." | grep message; \
  echo; echo '=====> ManagedCluster'; \
  oc get managedcluster ${DEST_CLUSTER}; \
"
```

This is the script output:

![img](../../assets/ztp-follow-sno-deployment.png)

## Creating/Updating policies on the Git repo

Ensure you already check the How to organize the repository section on this repo before continue.

To update already existant policies is just matter of change the PolicyGenTemplate and push them to the repo. To create a new maybe could be a bit more difficult but you can copy a sample and modify it as you want.

The current implementation for WC Lab is using a hierarchy for the Policies and a flat file for the Sites, something like a DU file. This implementation should not be enough for production, but an starting point to start baking the real one.

Every group will be stored in their own namespace:

![img](../../assets/ztp-follow-policy-apply.png)

The policies will be propagated to the SNO that matches the label (and copied into the SNO namespace)

![img](../../assets/ztp-follow-policy-apply-01.png)

The group name will be set on the policyTemplate file:

```
---
apiVersion: ran.openshift.io/v1 
kind: PolicyGenTemplate
metadata:
  name: "common"
  namespace: "common"
spec:
  bindingRules:
    common: "true"   <--- THIS
...
...
```

And will match with the site file on this spec `spec.clusters.*.clusterLabels` field:

```
...
...
- clusterName: "sno-1"
    clusterType: sno
    clusterProfile: du
    clusterLabels:   <--- THIS
      group-du-sno: ""
      common: true
      siteName : "vz-wc-lab"
      infra: "faregde"
...
...
```

So ensure that those labels are well set before update production env.

### Baking a new policyGenTemplate

```
---
apiVersion: ran.openshift.io/v1 
kind: PolicyGenTemplate
metadata:
  name: "common"
  namespace: "common"
spec
  bindingRules:
    common: "true"
  sourceFiles:
  ## Using the Source template as it is
    - fileName: StorageNS.yaml
      policyName: "storage-operator-deployment"
  ## Customizing the Source Template
    - fileName: StorageCatSource.yaml
      policyName: "catsources-fe-lab"
      metadata:
        name: redhat-operator-index
        namespace: openshift-marketplace
      spec:
        image: bm-cluster-1-hyper.e2e.bos.redhat.com:5000/olm/olm-index-redhat-operator-index:v4.8
        sourceType: grpc
        displayName: FE Lab - RedHat
        publisher: felab
        updateStrategy:
          registryPoll:
            interval: 30m
...
...
```

As you see there are 2 ways of using the Source templates, just refer to the required one and customizing an existant one. The source templates [are here](https://github.com/openshift-kni/cnf-features-deploy/tree/master/ztp/source-crs).

If you see something like $something is NOT a variable, it’s just a mark which represents that something more needs to be added, if you don’t put nothing on that section of the template, this part will be avoided.

There are some Policy templates already created in the repo using some virtual groups (you can change these group as you want).

> :warning: **NOTE**: (for now) If you delete a policy from the repo, the policy will not be deleted on the Hub cluster, so make sure that the deleted policies are not around after the deletion on the Git repo.

### Following a Policy Deployment

You can monitor the Policy application progress with this helper script:

```
#!/bin/bash
##
# Execution sample:
# ./watch-policies sno-1
##

DEST_CLUSTER=${1}

if [[ -z ${DEST_CLUSTER} ]];then
  echo "Give me a clustername"
  exit 1
fi

watch -n 5 "
  echo '=====> Policies:'; \
  oc get policies -n ${DEST_CLUSTER}; \
  echo; echo '=====> ArgoCD Apps'; \
  oc get applications.argoproj.io -A; \
  echo; echo '=====> Policies Pods:'; \
  oc get pod -n policies-sub; \
  echo; echo '=====> Clusters Pods:'; \
  oc get pod -n clusters-sub; \
"
```

This is the script output:

![img](../../assets/ztp-follow-policy-apply-02.png)

## FAQ

### Modifying a policy in the repo

If you modify a policy in the repo, the policies ArgoCD Application will get that content and it will render the objects in ACM policies, then it will patch the existant policies. With that ACM will try to apply the policies with the newest content.
This also applies for the labels associated to the SNOs already deployed. To check this last one it’s matter of execute this command (pointing to the hub cluster kubeconfig):

```
oc get managedcluster sno-1 -o jsonpath={.metadata.labels} | jq "."
```

Note: If you modify a policy in the ACM directly wihout change nothing in the Git Repo, the next time the hook comes in action, the changes done in the cluster will be overrided

### Modifying a SNO already deployed

You just need to add something like this to the field `spec.clusters.<cluster>.nodes.ignitionConfigOverride`.


To generate the passwordHash you need to execute this command in a shell and get the output:

```
python2 -c 'import crypt; print(crypt.crypt("adrogallop", crypt.mksalt(crypt.METHOD_SHA512)))'
```

Then add it to the proper section in the json, inside of the above mentioned field:

```
{"ignition":{"version":"3.2.0"},"passwd":{"users":[{"name":"core","sshAuthorizedKeys":["KEY1","KEY2","KEY3"]},{"name":"ocatopic","passwordHash":"$6$83VigvSOI2/CLrAN$7HV/BB.n9VPJB7w6dTOcPFxbzyP2AhrEYqXDXfIp8zKTYfsSHN7GkmdHbMsW/ldn1UCwVOnlhi1G4EKhUaXK60","sshAuthorizedKeys":["KEY1"]},{"name":"adrogallop","passwordHash":"$6$WYp587jV3sJriI.D$riK52JhqZTABsmSOD3WoGBF.gqFr62fb.RtA4a7BD4Fymdvt7AW9sPXHBRDSa77OvJdM.BMGNACx9e/5b4E4X.","sshAuthorizedKeys":["KEY1"]}]}}
```

### Enable the user/pass authentication in the automation

You just need to do the same thing as before including your user/password into the proper ignition section, then we need to create a policy to automate the sshd_config file deployment which will include the PasswordAuthentication yes in the file. 

To generate the sshd_config file, you need to execute this command using that file as a base in order to have it in base64:

```
cat sshd_config | base64 -w 0 > sshd_config.b64.txt
```

Then you need to embed the resultant hash into the will be a MC file:

```
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: sshd-full-master
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - path: /etc/ssh/sshd_config
        mode: 0644
        contents:
          source: data:text/plain;charset=utf-8;base64,<base64 content>
```

This can be included in a policy, inside of the PolicyGenTemplate with something like this:

```
- fileName: MachineConfigDummy.yaml 
  policyName: "ssh-user-pass-access"
  metadata:
    labels:
      machineconfiguration.openshift.io/role: master
    name: 98-ssh-user-pass-access
  spec:
    config:
      ignition:
        version: 3.2.0
      storage:
        files:
        - contents:
          source: 'data:text/plain;charset=utf-8;base64,<base64 content>'
          filesystem: root
          mode: 420
          path: /etc/ssh/sshd_config
```

## Troubleshooting

### Validating a New SNO deployment

- To validate a cluster, check the “agentclusterinstall” CR of that one, should show: “Cluster is installed”
- To validate a cluster to be joined to the Hub, check the “managedclusters”, should be Joined
- To validate if the policies were applied, check that ones in the Hub or SNO

#### Cheatsheet

- My cluster has been deployed?

```
oc get agentclusterinstall -n <sno NS> <sno> -o jsonpath={.status.conditions} | jq “.” | grep messages
```

- My spoke cluster joined the Hub to start applying the policies?

```
oc get managedclusters -A #(Check the Available and Joined fields, should be True)
```

- My spoke cluster is in the right groups for policies?

```
oc get policies -n <sno NS>
```

- I don’t see anything weird but my node is not booting up, how to check what is happening?

```
oc get bmh -n <sno NS>
```

### Checking the Policies

- A RHACM Policy can be in 2 states (oc get policies -n <spoke cluster>):
    - Compliant: The policy has created the desired object in the selected spoke cluster
    - NonCompliant: The policy cannot create the Object, the creation is in progress or the policy has changed

- A Compliant policy that creates objects means, that the objects in that policy were created but that DOES NOT means that the final purpose of the policy really worked.
    - E.G: A policy creates an object, which is a subscription. This last one triggers an automation on OCP to allow OLM to create an operator in the cluster. This operator creation can be blocked by external issues like the OperatorGroup does not exists. 
    - The advice here is to create some kind of validation policies to check the final status

## References

### Troubleshooting

- Official troubleshooting documentation: https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.3/html/troubleshooting/index

### Disaster Recovery
- DR Blogpost: https://cloud.redhat.com/blog/backup-and-restore-red-hat-advanced-cluster-management-for-kubernetes
