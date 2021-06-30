#!/bin/bash
export PULL_SECRET_JSON=/home/kni/jparrill/pull_secret_acm.json
export LOCAL_REGISTRY=$(hostname):5000
export SNAPSHOT=2.3.0-DOWNSTREAM-2021-06-16-09-34-33
export ACM_OP_BUNDLE=v2.3.0-127
export IMAGE_INDEX=quay.io/acm-d/acm-custom-registry
export BUILD_FOLDER=./build

# Clean previous tries
rm -rf ${BUILD_FOLDER}

# Copy ACM Custom Registry index and bundle images
echo
echo ">>>>>>>>>>>>>>> Cloning the Index and Bundle images..."
skopeo copy --authfile ${PULL_SECRET_JSON} --all docker://quay.io/acm-d/acm-custom-registry:${SNAPSHOT} docker://bm-cluster-1-hyper.e2e.bos.redhat.com:5000/rhacm2/acm-custom-registry:${SNAPSHOT}
skopeo copy --authfile ${PULL_SECRET_JSON} --all docker://quay.io/acm-d/acm-operator-bundle:${ACM_OP_BUNDLE} docker://bm-cluster-1-hyper.e2e.bos.redhat.com:5000/rhacm2/acm-operator-bundle:${ACM_OP_BUNDLE}

# Generate Mapping.txt
echo
echo ">>>>>>>>>>>>>>> Creating mapping assets..."
oc adm -a ${PULL_SECRET_JSON} catalog mirror ${IMAGE_INDEX}:${SNAPSHOT} ${LOCAL_REGISTRY} --manifests-only --to-manifests=${BUILD_FOLDER}

# Replace the upstream registry by the downstream one
sed -i s#registry.redhat.io/rhacm2/#quay.io/acm-d/# ${BUILD_FOLDER}/mapping.txt

# Mirror the images into your mirror registry.
echo
echo ">>>>>>>>>>>>>>> Mirroring images..."
oc image mirror -f ${BUILD_FOLDER}/mapping.txt -a ${PULL_SECRET_JSON} --filter-by-os=.* --keep-manifest-list --continue-on-error=true

echo
echo "export CUSTOM_REGISTRY_REPO=${LOCAL_REGISTRY}/rhacm2"
echo "export DEFAULT_SNAPSHOT=${SNAPSHOT}"
