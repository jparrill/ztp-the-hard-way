#!/bin/bash

## Variables
export PULL_SECRET_JSON=$(pwd)/pull_secret.json
export LOCAL_REGISTRY=$(hostname):5000
export LOCAL_REPOSITORY=ocp4
export OCP_RELEASE=4.8.0-rc.1-x86_64
export OCP_REGISTRY=quay.io/openshift-release-dev/ocp-release

## Functional
function ocp_mirror_release() {
	oc adm -a ${PULL_SECRET_JSON} release mirror \
		--from=${OCP_REGISTRY}:${OCP_RELEASE} \
		--to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
		--to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}
}

function download_oc_client() {
	oc adm --registry-config ${PULL_SECRET_JSON} release extract \
		--command=oc \
		--from=${OCP_REGISTRY}:${OCP_RELEASE} \
		--to .

	if [[ ! -f oc ]]; then
		echo "OC Client wasn't extracted, exiting..."
		exit 1
	fi

	mv oc /home/kni/bin/oc
}

download_oc_client
ocp_mirror_release
