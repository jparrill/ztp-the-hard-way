# OpenShift 4 Baremetal disconnected deployment

Ok, if you are here means that you already mirrored all the images of an OpenShift release and also the OLM Marketplace Images, so let's continue with the Hub deployment.

It will be based on IPI deployment on Baremetal, IPv6/Disconnected.

## Downloading RHCOS and OCP Resources

You can use this script to Mirror Images and Download the relevant binaries (`oc` client and `openshift-baremetal-install`)

The script will do four things:

- First is updating the `oc` client extracting it from the release you will pull from external registry.
- Second, extract the `openshift-baremetal-install` binary also from the release image of the external registry
- Third, execute the OCP Mirror release (Maybe you already did this part)
- Fourth, download the associated RHCOS version and host it our HTTPD server. This last step will try to download that RHCOS QEMU and OpenStack images, ensure you take note of the values to put it on the `install-config.yaml` file.

- `ocp_mirror.sh`

```sh
#!/bin/bash

# Variables
export PULL_SECRET_JSON=/home/kni/jparrill/pull_secret.json
export LOCAL_REGISTRY=$(hostname):5000
export LOCAL_REPOSITORY=ocp4
export OCP_RELEASE=4.8.0-fc.9-x86_64
export OCP_REGISTRY=quay.io/openshift-release-dev/ocp-release


# Functional
function ocp_mirror_release() {
  echo "----> Mirroring OCP Release: ${OCP_RELEASE}"
  oc adm -a ${PULL_SECRET_JSON} release mirror \
         --from=${OCP_REGISTRY}:${OCP_RELEASE} \
         --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
         --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}
}

function download_oc_client() {
  echo "----> Downloading OC Client"
  oc adm --registry-config ${PULL_SECRET_JSON} release extract \
        --command=oc \
        --from=${OCP_REGISTRY}:${OCP_RELEASE} \
        --to .

  if [[ ! -f oc ]];then
    echo "OC Client wasn't extracted, exiting..."
    exit 1
  fi

  mv oc /home/kni/bin/oc
}

function download_ipi_installer() {
  echo "----> Downloading IPI Installer"
  oc adm --registry-config ${PULL_SECRET_JSON} release extract \
        --command=openshift-baremetal-install \
        --from=${OCP_REGISTRY}:${OCP_RELEASE} \
        --to .

  if [[ ! -f openshift-baremetal-install ]];then
    echo "OCP Installer wasn't extracted, exiting..."
    exit 1
  fi

  sudo mv openshift-baremetal-install /usr/bin/openshift-baremetal-install
}

function download_rhcos() {
  export RHCOS_VERSION=$(openshift-baremetal-install coreos print-stream-json | jq -r '.["architectures"]["x86_64"]["artifacts"]["metal"]["release"]')
  export RHCOS_ISO_URI=$(openshift-baremetal-install coreos print-stream-json | jq -r '.["architectures"]["x86_64"]["artifacts"]["metal"]["formats"]["iso"]["disk"]["location"]')
  export RHCOS_ROOT_FS=$(openshift-baremetal-install coreos print-stream-json | jq -r '.["architectures"]["x86_64"]["artifacts"]["metal"]["formats"]["pxe"]["rootfs"]["location"]')
  export RHCOS_QEMU_URI=$(openshift-baremetal-install coreos print-stream-json | jq -r '.["architectures"]["x86_64"]["artifacts"]["qemu"]["formats"]["qcow2.gz"]["disk"]["location"]')
  export RHCOS_QEMU_SHA_UNCOMPRESSED=$(openshift-baremetal-install coreos print-stream-json | jq -r '.["architectures"]["x86_64"]["artifacts"]["qemu"]["formats"]["qcow2.gz"]["disk"]["uncompressed-sha256"]')
  export RHCOS_OPENSTACK_URI=$(openshift-baremetal-install coreos print-stream-json | jq -r '.["architectures"]["x86_64"]["artifacts"]["openstack"]["formats"]["qcow2.gz"]["disk"]["location"]')
  export RHCOS_OPENSTACK_SHA_COMPRESSED=$(openshift-baremetal-install coreos print-stream-json | jq -r '.["architectures"]["x86_64"]["artifacts"]["openstack"]["formats"]["qcow2.gz"]["disk"]["sha256"]')
  export OCP_RELEASE_DOWN_PATH=/var/www/html/$OCP_RELEASE

  echo "RHCOS_VERSION: $RHCOS_VERSION"
  echo "RHCOS_OPENSTACK_URI: $RHCOS_OPENSTACK_URI"
  echo "RHCOS_OPENSTACK_SHA_COMPRESSED: ${RHCOS_OPENSTACK_SHA_COMPRESSED}"
  echo "RHCOS_QEMU_URI: $RHCOS_QEMU_URI"
  echo "RHCOS_QEMU_SHA_UNCOMPRESSED: $RHCOS_QEMU_SHA_UNCOMPRESSED"
  echo "RHCOS_ISO_URI: $RHCOS_ISO_URI"
  echo "RHCOS_ROOT_FS: $RHCOS_ROOT_FS"
  echo "Press crtl-c to cancel download"
  read

  if [[ ! -d ${OCP_RELEASE_DOWN_PATH} ]]; then
    echo "----> Downloading RHCOS resources to ${OCP_RELEASE_DOWN_PATH}"
    sudo mkdir -p ${OCP_RELEASE_DOWN_PATH}
    echo "--> Downloading RHCOS resources: RHCOS QEMU Image"
    sudo curl -s -L -o ${OCP_RELEASE_DOWN_PATH}/$(echo $RHCOS_QEMU_URI | xargs basename) ${RHCOS_QEMU_URI}
    echo "--> Downloading RHCOS resources: RHCOS Openstack Image"
    sudo curl -s -L -o ${OCP_RELEASE_DOWN_PATH}/$(echo $RHCOS_OPENSTACK_URI | xargs basename) ${RHCOS_OPENSTACK_URI}
    echo "--> Downloading RHCOS resources: RHCOS ISO"
    sudo curl -s -L -o ${OCP_RELEASE_DOWN_PATH}/$(echo $RHCOS_ISO_URI | xargs basename) ${RHCOS_ISO_URI}
    echo "--> Downloading RHCOS resources: RHCOS RootFS"
    sudo curl -s -L -o ${OCP_RELEASE_DOWN_PATH}/$(echo $RHCOS_ROOT_FS | xargs basename) ${RHCOS_ROOT_FS}
  else
    echo "The folder already exist, so delete it if you want to re-download the RHCOS resources"
  fi
}

download_oc_client
download_ipi_installer
ocp_mirror_release
download_rhcos
```

## Openshift 4 IPI  Baremetal Deployment

Ok, we already have the `oc` client, the Baremetal-Installer according the OCP release, so now we need to fill our `InstallConfig` file. In a disconnected/IPv6 environment we should have some things in mind but `TL;DR` should be something like this:

```yaml
apiVersion: v1
baseDomain: redhat.com
networking:
  networkType: OVNKubernetes
  machineCIDR: 2120:52:0:0301::/64
  clusterNetwork:
    - cidr: fd01::/48
      hostPrefix: 64
  serviceNetwork:
    - fd02::/112
metadata:
  name: mgmt-hub
compute:
  - name: worker
    replicas: 0
controlPlane:
  name: master
  replicas: 3
  platform:
    baremetal: {}
platform:
  baremetal:
    provisioningNetworkInterface: eno3s1f4
    provisioningNetworkCIDR: 2120:52:0:0302::/64
    provisioningBridge: "prov"
    externalBridge: "baremetal"
    bootstrapProvisioningIP: 2120:52:0:0301::2
    bootstrapOSImage: http://[2120:52:0:0301::1]/rhcos-48.84.202106161818-0-qemu.x86_64.qcow2.gz?sha256=3691572a946ec5c6cdf48b79663adabbb744303f63e7af7c3ff43dfa4ee9f6b2
    clusterOSImage: http://[2120:52:0:0301::1]/rhcos-48.84.202106161818-0-openstack.x86_64.qcow2.gz?sha256=871ebdcafb906ac361ab9685bc806ddfcf6aee9027b81b1b654ac2275f14e4eb
    apiVIP: 2120:52:0:0301::3
    ingressVIP: 2120:52:0:0301::2
    hosts:
      - name: openshift-master-0
        role: master
        bmc:
          address: ipmi://[2120:52:0:0301::81]
          username: user
          password: pa$$w0rd
        bootMACAddress: 18:DE:F2:8C:D8:93
        hardwareProfile: default
      - name: openshift-master-1
        role: master
        bmc:
          address: ipmi://[2120:52:0:0301::82]
          username: user
          password: pa$$w0rd
        bootMACAddress: 18:DE:12:8C:D1:A0
        hardwareProfile: default
      - name: openshift-master-2
        role: master
        bmc:
          address: ipmi://[2120:52:0:0301::83]
          username: user
          password: pa$$w0rd
        bootMACAddress: 18:AB:92:8C:D5:BD
        hardwareProfile: default
imageContentSources:
  - mirrors:
      - bm-cluster-1-hyper.e2e.bos.redhat.com:5000/ocp4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
      - bm-cluster-1-hyper.e2e.bos.redhat.com:5000/ocp4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  MIIGJzCCBA+gAwIBAgIUcuRdl0sEsCZMPWuE44snY/MLgcowDQYJKoZIhvcNAQEL
  ...
  ...
  BQAwgYgxCzAJBgNVBAYTAlVTMRYwFAYDVQQIDA1NYXNzYWNodXNldHRzMREwDwYD
  6Rf1YNZC6XaR2GzJTz8mdiyG4L/cG6um65TigWOjaAOfD5ecei+d0maqmw==
  -----END CERTIFICATE-----
pullSecret: |
  {"auths":{"bm-cluster-1-hyper.e2e.bos.redhat.com:5000":{"auth":"a25pOmtuaQ==","email":"john.doe@redhat.com"}}}
sshKey: |
  ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCaTNKY08frGZjQLyS5hHPqAGRV3kb... kni@bm-cluster-1-hyper.e2e.bos.redhat.com
```

**NOTE**: Ensure you have checked all the MAC Addresses, BMC IPs and so on, if you have any doubt about any of the steps, you have here a [great explanation about this process](https://openshift-kni.github.io/baremetal-deploy/), pick the right version and take a look.

Then we should have a folder structure similar to this one:

```console
ocp
├── deploy.sh
├── install-config_hub.yaml
└── ocp_mirror.sh
```

And now we just need to execute this script, which is the `deploy.sh`:

```sh
#!/bin/bash
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="bm-cluster-1-hyper.e2e.bos.redhat.com:5000/ocp4:4.8.0-fc.9-x86_64"
export CLUSTER=mgmt-hub

rm -rf $CLUSTER
mkdir -p $CLUSTER/openshift
cp install-config_hub.yaml $CLUSTER/install-config.yaml
openshift-baremetal-install --dir $CLUSTER --log-level debug create cluster
```

After the script execution we will see a big trace about how the installation it's going, so be patient until the deployment finishes...

![](/assets/8-hours-later.jpg)

This should be the typical output of this execution:

```console
DEBUG Still waiting for the cluster to initialize: Working towards 4.8.0-fc.8: 20 of 676 done (2% complete)
DEBUG Still waiting for the cluster to initialize: Working towards 4.8.0-fc.8: 32 of 676 done (4% complete)
DEBUG Still waiting for the cluster to initialize: Working towards 4.8.0-fc.8: 35 of 676 done (5% complete)
DEBUG Still waiting for the cluster to initialize: Working towards 4.8.0-fc.8: 526 of 676 done (77% complete)
DEBUG Cluster is initialized
INFO Waiting up to 10m0s for the openshift-console route to be created...
DEBUG Route found in openshift-console namespace: console
DEBUG OpenShift console route is admitted
INFO Install complete!
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/jdoe/ocp/mgmt-hub/auth/kubeconfig'
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.mgmt-hub.redhat.com
INFO Login to the console with user: "kubeadmin", and password: "zhkf6-5a5th-f567lq-609r5f"
DEBUG Time elapsed per stage:
DEBUG     Infrastructure: 28m8s
DEBUG Bootstrap Complete: 14m48s
DEBUG                API: 40s
DEBUG  Bootstrap Destroy: 14s
DEBUG  Cluster Operators: 17m54s
INFO Time elapsed: 1h1m9s
```


## Side scenarios

### I have my HUB with provisioning network but the spokes cannot reach the ISO served by Ironic

Ok. this situation happens when you Hub cluster has configured Provisioning network and your spokes doesn't. The ISO will be served from that provisioning network by Ironic and the BMC are capable to reach that URLs (always that those Prov networks are not routable between them).

To solve that situation we need to modify our Hub cluster configuration:

```sh
oc edit provisioning provisioning-configuration
```

Something like this will appear:

```yaml
spec:
  provisioningDHCPRange: 2620:52:0:1307::a,2620:52:0:1307:ffff:ffff:ffff:fffe
  provisioningIP: 2620:52:0:1307::3
  provisioningInterface: enp3s0f1
  provisioningNetwork: Managed
  provisioningNetworkCIDR: 2620:52:0:1307::/64
  provisioningOSDownloadURL: http://[2620:52:0:1302::1]/4.8.0-rc.1-x86_64/rhcos-48.84.202106091622-0-openstack.x86_64.qcow2.gz?sha256=6ab5c6413f275277ea90f7dfc66424ef14993941ba3a9f3a43955ab268e7d76d
  watchAllNamespaces: true
```

So now we need to modify it to match this configuration:

```yaml

spec:
  provisioningNetwork: Disabled
  provisioningOSDownloadURL: http://[2620:52:0:1302::1]/4.8.0-rc.1-x86_64/rhcos-48.84.202106091622-0-openstack.x86_64.qcow2.gz?sha256=6ab5c6413f275277ea90f7dfc66424ef14993941ba3a9f3a43955ab268e7d76d
  watchAllNamespaces: true
```

Then the Metal3 pod will be recreated. From this point we need to delete the current manifests for our Spoke cluster, including the ACI, CD, NMState, etc...

