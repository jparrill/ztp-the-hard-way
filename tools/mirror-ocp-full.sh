#!/bin/bash

# Variables
export PULL_SECRET_JSON=/home/kni/jparrill/pull_secret.json
export LOCAL_REGISTRY=$(hostname):5000
export LOCAL_REPOSITORY=ocp4
export OCP_RELEASE=4.8.12-x86_64
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

	if [[ ! -f oc ]]; then
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

	if [[ ! -f openshift-baremetal-install ]]; then
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
	echo "Press Enter to continue or Ctrl-C to cancel download"
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

function format_images_config() {
	echo """
      Add the following to install-config.yaml

        bootstrapOSImage: http://$(hostname --long)/$OCP_RELEASE/${RHCOS_QEMU_URI##*/}?sha256=$RHCOS_QEMU_SHA_UNCOMPRESSED
        clusterOSImage: http://$(hostname --long)/$OCP_RELEASE/${RHCOS_OPENSTACK_URI##*/}?sha256=$RHCOS_OPENSTACK_SHA_COMPRESSED
     """
}

download_oc_client
download_ipi_installer
ocp_mirror_release
download_rhcos
format_images_config
