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
export RH_OP_PACKAGES='advanced-cluster-management,local-storage-operator,ocs-operator,performance-addon-operator,ptp-operator,sriov-network-operator'
export COMM_OP_PACKAGES='hive-operator'
export CERT_OP_PACKAGES=""

if [ $# -lt 1 ]; then
	echo "Usage : $0 mirror|mirror-olm|upgrade"
	exit
fi

# Apply the ISV GPG key as specified in https://access.redhat.com/solutions/6542281
setup-gpg-if-needed() {
	if [ ! -f /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-isv ]; then
	    echo "WARNING: GPG key for certified operators not found. setting it up now..."
		sudo curl -s -o /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-isv https://www.redhat.com/security/data/55A34A82.txt
		sudo cp /etc/containers/policy.json /etc/containers/policy.json_bck
		jq '.transports.docker."registry.redhat.io/redhat/certified-operator-index" += [{"type": "signedBy","keyType": "GPGKeys","keyPath": "/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-isv"}]' /etc/containers/policy.json >> temp-policy.json
        sudo mv temp-policy.json /etc/containers/policy.json
	fi
}

mirror() {
	# Check for credentials for OPM
	if [ ! -f ~/.docker/config.json ]; then
		echo "ERROR: missing ~/.docker/config.json config"
		exit 1
	fi

	# Mirror redhat-operator index image
	if [ "${RH_OP}" = true ]; then
		echo "opm index prune --from-index $RH_OP_INDEX --packages $RH_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG"
		opm index prune --from-index $RH_OP_INDEX --packages $RH_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG
		GODEBUG=x509ignoreCN=0 podman push --tls-verify=false $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG --authfile $OCP_PULLSECRET_AUTHFILE
		GODEBUG=x509ignoreCN=0 oc adm catalog mirror $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG $LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG --registry-config=$OCP_PULLSECRET_AUTHFILE

		cat >redhat-operator-index-manifests/catalogsource.yaml <<EOF
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

	if [ "${CERT_OP}" = true ]; then
		echo "opm index prune --from-index $CERT_OP_INDEX --packages $CERT_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG"
		opm index prune --from-index $CERT_OP_INDEX --packages $CERT_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG
		GODEBUG=x509ignoreCN=0 podman push --tls-verify=false $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG --authfile $OCP_PULLSECRET_AUTHFILE
		GODEBUG=x509ignoreCN=0 oc adm catalog mirror $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG $LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG --registry-config=$OCP_PULLSECRET_AUTHFILE

		cat >certified-operator-index-manifests/catalogsource.yaml <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-certified-operator-catalog
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
		echo "oc apply -f ./certified-operator-index-manifests/imageContentSourcePolicy.yaml"
		echo "oc apply -f ./certified-operator-index-manifests/catalogsource.yaml"
	fi

	if [ "${COMM_OP}" = true ]; then
		echo "opm index prune --from-index $COMM_OP_INDEX --packages $COMM_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM"
		opm index prune --from-index $COMM_OP_INDEX --packages $COMM_OP_PACKAGES --tag $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM
		GODEBUG=x509ignoreCN=0 podman push --tls-verify=false $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM --authfile $OCP_PULLSECRET_AUTHFILE
		GODEBUG=x509ignoreCN=0 oc adm catalog mirror $LOCAL_REGISTRY/$LOCAL_REGISTRY_INDEX_TAG_COMM $LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG --registry-config=$OCP_PULLSECRET_AUTHFILE

		cat >community-operator-index-manifests/catalogsource.yaml <<EOF
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

	if [ "${MARKETPLACE_OP}" = true ]; then
		"echo 3"
	fi

}

mirror-olm() {
	# hack for broken operators

	for packagemanifest in $(oc get packagemanifest -n openshift-marketplace -o name); do
		for package in $(oc get $packagemanifest -o jsonpath='{.status.channels[*].currentCSVDesc.relatedImages}' | sed "s/ /\n/g" | tr -d '[],' | sed 's/"/ /g'); do
			echo
			echo "Package: ${package}"
			skopeo copy docker://$package docker://$LOCAL_REGISTRY/$LOCAL_REGISTRY_IMAGE_TAG/$(echo $package | awk -F'/' '{print $2}')-$(basename $package) --all --authfile $OCP_PULLSECRET_AUTHFILE
		done
	done

}

upgrade() {
	# output ConfigMap for disconnected upgrade, issue guidance on mirroring

	DIGEST="$(oc adm release info quay.io/openshift-release-dev/ocp-release:${OCP_RELEASE_FULL}-${ARCHITECTURE} | sed -n 's/Pull From: .*@//p')"
	DIGEST_ALGO="${DIGEST%%:*}"
	DIGEST_ENCODED="${DIGEST#*:}"
	SIGNATURE_BASE64=$(curl -s "https://mirror.openshift.com/pub/openshift-v4/signatures/openshift/release/${DIGEST_ALGO}=${DIGEST_ENCODED}/signature-1" | base64 -w0 && echo)

	cat >$SIGNATURE_BASE64_FILE <<EOF
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
    setup-gpg-if-needed
	mirror
	;;
mirror-olm)
    setup-gpg-if-needed
	mirror-olm
	;;
upgrade)
    setup-gpg-if-needed
	upgrade
	;;
*)
	echo $"Usage: $0 mirror|mirror-olm|upgrade"
	exit 1
	;;
esac

exit 0
