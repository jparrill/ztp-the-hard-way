Table of contents:

<!-- TOC -->

- [Mirror OLM Marketplace](#mirror-olm-marketplace)
  - [Helpers](#helpers)
    - [OLM Sync Script](#olm-sync-script)

<!-- /TOC -->

# Mirror OLM Marketplace

To Mirror the OLM container images will require SO MUCH space, like 350 - 400G approximately, so ensure you have enough space before you start, if not the process will fail eventually and you will need to restart this process, and it takes some hours to complete.

First thing we need to do, working in a disconnected environment is to disable the default sources which are using Internet resources and will stay on `ImagePullBackOff` state so you just need to execute this:

```
oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
```

After that, the default source pod's will disappear from the `openshift-marketplace` namespace.

In a previous step we already test our PullSecret file against our internal registry, so we need to grab that one and use it for this mirroring phase.

We need to think that there are four catalogs published, each one with their own purpose:

- `certified-operators`
- `redhat-operator`
- `community-operator`
- `redhat-marketplace`

We need to know their names in order to mirror the images that they have in their indexes. To do that we need to raise up (even in local) a container with the index image of that snapshot to mirror against our internal registry:

```sh
# This raises up a container with all the package manifests that the OCP will see as  compatible operators on v4.7 channel
podman run -p50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.7

# Then from other terminal you just need to execute this
grpcurl -plaintext localhost:50051 api.Registry/ListPackages > packages.out
```

The `packages.out` contains the reference to the operators in that snapshot image. Then we need to take note of the ones we wanna include it on the mirroring and put them in a list:

**NOTE**: for private repository, `opm` needs the credentials file located at the default location `~/.docker/config.json`

```sh
opm index prune \
    -f registry.redhat.io/redhat/redhat-operator-index:v4.7 \
    -p advanced-cluster-management,jaeger-product,quay-operator \
    -t <target_registry>:<port>/<namespace>/redhat-operator-index:v4.7
```

And push that operator to your internal registry, ok now we have our index image, so now we need to mirror the bundle which is pointing to:

```sh
oc adm catalog mirror registry.redhat.io/redhat/redhat-operator-index:v4.7 \
    <mirror_registry>:<port>/<namespace> \
    -a ${PULL_SECRET} \
    --insecure
```

**NOTE**: You can also mirror from a `tgz` file if your registry is also disconnected.

This will generate a folder like (sample) `community-operator-index-manifests` that contains the `ImageContentSourcePolicies` and the `CatalogSource` manifests:

- `ImageContentSourcePolicies` (ICSP): This OCP object creates an entry in the `/etc/containers/registries.conf` of every node (that allows user workloads) to use a mirror instead of go the source registry, following that precedence, first the mirror, then the source. After that, the `MachineConfigOperator` will restart the `crio` and the `kubelet` by himself.

**NOTE**: If you modify the `/etc/containers/registries.conf` file by hand, it will only be used by `Crio` when you restart the `crio` and `kubelet` processes. Also if you modify it manually, it will put the `MachineConfigOperator` in `degraded` state.

**NOTE**: Another important thing, the default behavior of applying a ICSP is, that `crio` will only go to pull that image from the Mirror if you are trying to pull an image with the `digest` instead of the `tag`, here you have a sample:

- **tag**: `quay.io/jparrill/busybox:1.28`
- **digest**: `quay.io/jparrill/busybox@sha256:4f0f2624a6e45db32bdf62511fe247af6666cd5689dbd5c43459c1bf765a6a5a`.

This is a sample of an ICSP:

```yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: ztp-disconnected
spec:
  repositoryDigestMirrors:
    - mirrors:
        - bm-cluster-1-hyper.e2e.bos.redhat.com:5000/olm/openshift4-ose-local-storage-static-provisioner
      source: registry.redhat.io/openshift4/ose-local-storage-static-provisioner
    - mirrors:
        - bm-cluster-1-hyper.e2e.bos.redhat.com:5000/olm/openshift4-ose-local-storage-operator-bundle
      source: registry.redhat.io/openshift4/ose-local-storage-operator-bundle
    - mirrors:
        - bm-cluster-1-hyper.e2e.bos.redhat.com:5000/olm/openshift4-ose-local-storage-operator
      source: registry.redhat.io/openshift4/ose-local-storage-operator
```

- `CatalogSources`: This OCP object points to an index container image that has inside references to other images, and are together because you has considered all of them as a group in a previous step (on the `opm index prune` command section.

This is a sample of a `CatalogSource`:

```yaml
# This is a sample from my internal lab.
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: custom-community-operator-catalog-v4-8
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: bm-cluster-1-hyper.e2e.bos.redhat.com:5000/olm-index/community-operator-index:v4.8
  displayName: BM Lab - Community Operator - v4.8
  publisher: BM Lab Registry
  updateStrategy:
    registryPoll:
      interval: 30m
```

When you create this object, the **Operator Lifecycle Manager (OLM)** will parse it and it will create a temporary pod. This pod tries to pull the Bundle which the index is pointing to (and you mirrored previously with the command `oc adm catalog mirror`). After that, you should see new `PackageManifests` created on the cluster:

```console
NAME                          CATALOG                              AGE
advanced-cluster-management                                        7h57m
sriov-network-operator        BM Lab - RH operator - v4.8          9h
ptp-operator                  BM Lab - RH operator - v4.8          9h
local-storage-operator        BM Lab - RH operator - v4.8          9h
performance-addon-operator    BM Lab - RH operator - v4.8          9h
advanced-cluster-management   BM Lab - RH operator - v4.8          9h
ocs-operator                  BM Lab - RH operator - v4.8          9h
hive-operator                 BM Lab - Community Operator - v4.8   9h
```

Every one of them is a "box" with all the images necessary to deploy an operator, for example `local-storage-operator` contains inside all the necessary images to deploy and make the Local Storage Operator work on disconnected environments.

**NOTE**: as you see in the previous shell execution `oc get packagemanifest`, some packages belongs to the same Catalog, that will depend on how many operators did you put on the `opm prune index` command.

Once we have created the `CatalogSource` and the ICSP all should be ok.

**NOTE**: Not all operators support disconnected deployments, so if you check the `packagemanifest` of the desired operator and see that the images are set with tags instead of the digest, will be a problem for your disconnected deployment.

It's technically possible to workaround this situation but (for now) requires manual intervention and it's fully unsupported.

## Helpers

I usually use this script to go through all this process [OLM Sync Script](#olm-sync-script) to use it you just need to modify the variables at first with the needed ones. Once done that, you need to execute this:

```sh
./olm-operator.sh mirror
```

This will mirror the images and create the folder with the ICSP and `CatalogSource`. Now you need to load them to ensure in the next step that all the images are there.

```sh
oc create -f imageContentSourcePolicy.yaml
oc create -f catalogsource.yaml
```

When the nodes gets back into `Ready` state we need to execute the script again in this way:

```sh
./olm-operator.sh mirror-olm
```

This will ensure us that all the images and all the image's layers are there. Sometimes you can see that after perform the mirroring and all the steps in the right way, you have some images without being mirrored, this step is to avoid that issue. And the root cause of this problem it's based in how the image is created for that operator so that will depend on who creates it and how.

### OLM Sync Script

```sh
#!/bin/bash -e
# Disconnected Operator Catalog Mirror and Minor Upgrade
# Variables to set, suit to your installation

export OCP_RELEASE=4.8
export OCP_RELEASE_FULL=$OCP_RELEASE.0
export ARCHITECTURE=x86_64
export SIGNATURE_BASE64_FILE="signature-sha256-$OCP_RELEASE_FULL.yaml"
export OCP_PULLSECRET_AUTHFILE='/root/pull_secret.json'
export LOCAL_REGISTRY=bm-cluster-1-hyper.e2e.bos.redhat.com:5000
export LOCAL_REGISTRY_MIRROR_TAG=/ocp4/openshift4
export LOCAL_REGISTRY_INDEX_TAG=olm-index/redhat-operator-index:v$OCP_RELEASE
export LOCAL_REGISTRY_INDEX_TAG_COMM=olm-index/community-operator-index:v$OCP_RELEASE
export LOCAL_REGISTRY_IMAGE_TAG=olm

# Set these values to true for the catalog and miror to be created
export RH_OP='true'
export CERT_OP='false'
export COMM_OP='true'
export MARKETPLACE_OP='false'

export RH_OP_INDEX="registry.redhat.io/redhat/redhat-operator-index:v${OCP_RELEASE}"
export CERT_OP_INDEX="registry.redhat.io/redhat/certified-operator-index:v${OCP_RELEASE}"
export COMM_OP_INDEX="registry.redhat.io/redhat/community-operator-index:v${OCP_RELEASE}"
export MARKETPLACE_OP_INDEX="registry.redhat.io/redhat-marketplace-index:v${OCP_RELEASE}"
#export RH_OP_PACKAGES='advanced-cluster-management,cluster-logging,kubevirt-hyperconverged,local-storage-operator,ocs-operator,performance-addon-operator,ptp-operator,sriov-network-operator'
export RH_OP_PACKAGES='advanced-cluster-management,local-storage-operator,ocs-operator,performance-addon-operator,ptp-operator,sriov-network-operator'
export COMM_OP_PACKAGES='hive-operator'

if [ $# -lt 1 ]
then
        echo "Usage : $0 mirror|mirror-olm|upgrade"
        exit
fi

mirror () {
# Mirror redhat-operator index image

if [ "${RH_OP}" = true ]
  then
    echo "opm index prune --from-index $RH_OP_INDEX --packages $RH_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG"
    opm index prune --from-index $RH_OP_INDEX --packages $RH_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG
    GODEBUG=x509ignoreCN=0 podman push --tls-verify=false $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG --authfile $OCP_PULLSECRET_AUTHFILE
    GODEBUG=x509ignoreCN=0 oc adm catalog mirror $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG $LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG --registry-config=$OCP_PULLSECRET_AUTHFILE

    cat > redhat-operator-index-manifests/catalogsource.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-operator-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG
  displayName: Temp Lab
  publisher: templab
  updateStrategy:
    registryPoll:
      interval: 30m
EOF

    echo ""
    echo "To apply the Red Hat Operators catalog mirror configuration to your cluster, do the following once per cluster:"
    echo "oc apply -f ./redhat-operator-index-manifests/imageContentSourcePolicy.yaml"
    echo "oc apply -f ./redhat-operator-index-manifests/catalogsource.yaml"
fi

if [ "${CERT_OP}" = true ]
  then
    "echo 1"
fi

if [ "${COMM_OP}" = true ]
  then
    echo "opm index prune --from-index $COMM_OP_INDEX --packages $COMM_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM"
    opm index prune --from-index $COMM_OP_INDEX --packages $COMM_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM
    GODEBUG=x509ignoreCN=0 podman push --tls-verify=false $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM --authfile $OCP_PULLSECRET_AUTHFILE
    GODEBUG=x509ignoreCN=0 oc adm catalog mirror $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM $LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG --registry-config=$OCP_PULLSECRET_AUTHFILE

    cat > community-operator-index-manifests/catalogsource.yaml << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-community-operator-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM
  displayName: Temp Lab
  publisher: templab
  updateStrategy:
    registryPoll:
      interval: 30m
EOF

    echo ""
    echo "To apply the Red Hat Operators catalog mirror configuration to your cluster, do the following once per cluster:"
    echo "oc apply -f ./community-operator-index-manifests/imageContentSourcePolicy.yaml"
    echo "oc apply -f ./community-operator-index-manifests/catalogsource.yaml"

fi

if [ "${MARKETPLACE_OP}" = true ]
  then
    "echo 3"
fi

}

mirror-olm () {
# hack for broken operators

for packagemanifest in $(oc get packagemanifest -n openshift-marketplace -o name) ; do
  for package in $(oc get $packagemanifest -o jsonpath='{.status.channels[*].currentCSVDesc.relatedImages}' | sed "s/ /\n/g" | tr -d '[],' | sed 's/"/ /g') ; do
    echo
    echo "Package: ${package}"
    skopeo copy docker://$package docker://$LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG/openshift4-$(basename $package) --all --authfile $OCP_PULLSECRET_AUTHFILE
  done
done

}

upgrade () {
# output ConfigMap for disconnected upgrade, issue guidance on mirroring

DIGEST="$(oc adm release info quay.io/openshift-release-dev/ocp-release:${OCP_RELEASE_FULL}-${ARCHITECTURE} | sed -n 's/Pull From: .*@//p')"
DIGEST_ALGO="${DIGEST%%:*}"
DIGEST_ENCODED="${DIGEST#*:}"
SIGNATURE_BASE64=$(curl -s "https://mirror.openshift.com/pub/openshift-v4/signatures/openshift/release/${DIGEST_ALGO}=${DIGEST_ENCODED}/signature-1" | base64 -w0 && echo)

cat > $SIGNATURE_BASE64_FILE << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: release-image-${OCP_RELEASE_FULL}
  namespace: openshift-config-managed
  labels:
    release.openshift.io/verification-signatures: ""
binaryData:
  ${DIGEST_ALGO}-${DIGEST_ENCODED}: ${SIGNATURE_BASE64}
EOF

echo ""
echo "To apply the image signature ConfigMap for $OCP_RELEASE_FULL, issue:"
echo "oc apply -f $SIGNATURE_BASE64_FILE"

echo ""
echo "To start mirroring content for OpenShift $OCP_RELEASE_FULL, issue:"
echo "oc adm release mirror --registry-config $OCP_PULLSECRET_AUTHFILE --from=quay.io/openshift-release-dev/ocp-release@$DIGEST --to=$LOCAL_REGISTRY$LOCAL_REGISTRY_MIRROR_TAG --to-release-image=$LOCAL_REGISTRY$LOCAL_REGISTRY_MIRROR_TAG:${OCP_RELEASE_FULL}-${ARCHITECTURE}"

echo ""
echo "To initiate the upgrade on the cluster to $OCP_RELEASE_FULL, issue:"
echo "oc adm upgrade --allow-explicit-upgrade --to-image $LOCAL_REGISTRY$LOCAL_REGISTRY_MIRROR_TAG@$DIGEST"
}

case "$1" in
	mirror)
		mirror
		;;
	mirror-olm)
		mirror-olm
		;;
	upgrade)
		upgrade
		;;
	*)
		echo $"Usage: $0 mirror|mirror-olm|upgrade"
		exit 1
esac

exit 0
```
