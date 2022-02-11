#!/bin/bash
export PULL_SECRET_JSON=~/pull-secret.json
export LOCAL_REGISTRY=$(hostname):5000
export SNAPSHOT=2.3.0-DOWNSTREAM-2021-06-16-09-34-33
export ACM_OP_BUNDLE=v2.3.0-127
export IMAGE_INDEX=quay.io/acm-d/acm-custom-registry
export BUILD_FOLDER=./build
export REMOTE_REGISTRY=quay.io:443/acm-d 

# Clean previous tries
rm -rf ${BUILD_FOLDER}

# Copy ACM Custom Registry index and bundle images
echo
echo ">>>>>>>>>>>>>>> Cloning the Index and Bundle images..."
skopeo copy --authfile ${PULL_SECRET_JSON} docker://quay.io/acm-d/acm-custom-registry:${SNAPSHOT} docker://${LOCAL_REGISTRY}/rhacm2/acm-custom-registry:${SNAPSHOT} --all
skopeo copy --authfile ${PULL_SECRET_JSON} docker://quay.io/acm-d/acm-operator-bundle:${ACM_OP_BUNDLE} docker://${LOCAL_REGISTRY}/rhacm2/acm-operator-bundle:${ACM_OP_BUNDLE} --all

# Generate Mapping.txt
echo
echo ">>>>>>>>>>>>>>> Creating mapping assets..."
oc adm -a ${PULL_SECRET_JSON} catalog mirror ${IMAGE_INDEX}:${SNAPSHOT} ${LOCAL_REGISTRY} --manifests-only --to-manifests=${BUILD_FOLDER}

# Replace the upstream registry by the downstream one
sed -i s#registry.redhat.io/rhacm2/#${REMOTE_REGISTRY}/# ${BUILD_FOLDER}/mapping.txt

# Mirror the images into your mirror registry.
echo
echo ">>>>>>>>>>>>>>> Mirroring images..."
oc image mirror -f ${BUILD_FOLDER}/mapping.txt -a ${PULL_SECRET_JSON} --filter-by-os=.* --keep-manifest-list --continue-on-error=true

echo ">>>>>>>>>>>>>>> Copying images via skopeo..."
for image in $(cat ${BUILD_FOLDER}/mapping.txt)
do
    IFS='='
    declare -a FIELDS=($image)
    echo "skopeo copy --authfile ${PULL_SECRET_JSON} docker://${FIELDS[0]} docker://${FIELDS[1]} --all"
    skopeo copy --authfile ${PULL_SECRET_JSON} docker://${FIELDS[0]} docker://${FIELDS[1]} --all
done

echo
echo "export CUSTOM_REGISTRY_REPO=${LOCAL_REGISTRY}/rhacm2"
echo "export DEFAULT_SNAPSHOT=${SNAPSHOT}"

