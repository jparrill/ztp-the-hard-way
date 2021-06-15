# Mirror the OCP Release

I think you already did this for the Hub cluster deployment but let's review it.

**Remember** This is a supported step and it's officially documented here: https://docs.openshift.com/container-platform/4.7/installing/installing-mirroring-installation-images.html#installing-mirroring-installation-images

Said that let's go through the process.

First thing we need it's the `oc` client, to best way to do it's downloading from [here](https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/oc/), but if you have already one even if it's outdated, you can use this script:

```
#!/bin/bash

## Variables
export PULL_SECRET_JSON=$(pwd)/pull_secret.json
export LOCAL_REGISTRY=$(hostname):5000
export LOCAL_REPOSITORY=ocp4
export OCP_RELEASE=4.8.0-fc.9-x86_64
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

  if [[ ! -f oc ]];then
    echo "OC Client wasn't extracted, exiting..."
    exit 1
  fi

  mv oc /home/kni/bin/oc
}

download_oc_client
ocp_mirror_release
```

Executing this script should be ok to download and update the `oc` client and also mirror the Openshift Release, so ensure you add the relevant ImageContentSourcePolicies to your InstallConfig for the Hub deployment and also for the Spoke deployments that we will explain in a later section.
