Table of contents:

<!-- TOC -->

- [ACM Downstream Deployment Disconnected](#acm-downstream-deployment-disconnected)
  - [Permission for Downstream Repository](#permission-for-downstream-repository)
  - [ACM Downstream Image Mirroring](#acm-downstream-image-mirroring)
  - [ACM Downstream deployment](#acm-downstream-deployment)
  - [ACM Uninstall process](#acm-uninstall-process)
  - [Demo video](https://www.youtube.com/watch?v=JSkPCkuO16s&list=PLaR6Rq6Z4IqecDatkODye7IWMJUc5r6td&index=8)

<!-- /TOC -->

# ACM Downstream Deployment Disconnected

**NOTE**: We are following the same procedure they follow in the `README.md` file from the deployment repository all the things are well explained there, so if you have some doubts that is the right place (even including to [deploy a ACM downstream version](https://github.com/open-cluster-management/deploy#deploying-downstream-builds-snapshots-for-product-quality-engineering) .

## Permission for Downstream Repository

First thing we need to follow the instructions mentioned [here](https://github.com/open-cluster-management/deploy#prepare-to-deploy-open-cluster-management-instance-only-do-once) to request a pull permission for repo **quay.io/acm-d**.

Then you can verify if you have enough permission:

```sh
podman pull --authfile ${PULL_SECRET} quay.io/acm-d/acm-custom-registry:2.3.0-DOWNSTREAM-2021-06-13-16-46-23
```

## ACM Downstream Image Mirroring

To do that, you will need to follow [this steps](https://gist.github.com/cdoan1/c6b83cb30110ef981fbca71e1e04a596) originally written down by `Chris Doan` but here it's an alternative script I've created to help you in a more automated way:

```sh
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

```

This takes like 30 mins maybe less and you need to check this 2 resources to fill the proper variables:

- The ACM Index image which is called `acm-custom-regsitry`: https://quay.io/repository/acm-d/acm-custom-registry?tab=tags
- The ACM Operator Bundle which is called `acm-operator-bundle`: https://quay.io/repository/acm-d/acm-operator-bundle?tag=latest&tab=tags

Check both and get the ones that makes sense for your deployment, a hint to relate between the index and the bundle could be the `LAST MODIFIED` field on `Quay.io`.

Take note of the right tags for both and put them on the script variables.

Also ensure that:

- `PULL_SECRET_JSON` are in place and is the right one
- `LOCAL_REGISTRY` is your internal registry and it's reachable
- `SNAPSHOT` points to the `acm-custom-registry` desired tag
- `ACM_OP_BUNDLE` points to the desired `acm-operator-bundle` desired tag
- You have loaded your `Kubeconfig` file as `KUBECONFIG` environment variable with `export KUBECONFIG=/path/to/the/kubeconfig`

Then after that we can execute the script:

```sh
./acm-image-sync.sh
```

## ACM Downstream deployment

To deploy an ACM Downstream version you will need this repository: **https://github.com/open-cluster-management/deploy**, so clone it and we can continue with the process.

So now we need to follow these steps:

- After cloning it and enter into the `deploy` folder, you need to modify the file called `snapshot.ver` with the version you wanna deploy
- Then ensure you have 3 PVs (at least) available to be bound
- You will need to export some variables to the Environment

  ```sh
  export DEFAULT_SNAPSHOT="<Desired SNAPSHOT version>"
  export KUBECONFIG=<kubeconfig path>
  export CUSTOM_REGISTRY_REPO=<internal_registry>:<port>/rhacm2
  export COMPOSITE_BUNDLE=true
  export DEBUG=true
  ```

  In my case is something like:

  ```sh
  export DEFAULT_SNAPSHOT="2.3.0-DOWNSTREAM-2021-06-16-09-34-33"
  export KUBECONFIG=/home/kni/ipv6/mgmt-hub/auth/kubeconfig
  export CUSTOM_REGISTRY_REPO=bm-cluster-1-hyper.e2e.bos.redhat.com:5000/rhacm2
  export COMPOSITE_BUNDLE=true
  export DEBUG=true
  ```

- Now we just need to execute the deployment script called `start.sh`

- When it finishes, we just need to check that all pods are in running state and the installation process take some time to finish so be patient.

  ```
  oc get pods -n open-cluster-management
  ```

- After the installation has finished you need to double check that the Multi Cluster Hub object has been annotated with your custom registry repo, otherwise the managed cluster won't be able to pull the required images.

  ```sh
  oc annotate mch multiclusterhub mch-imageRepository='bm-cluster-1-hyper.e2e.bos.redhat.com:5000/rhacm2'
  ```

## ACM Uninstall process

In the typical situation, you just need to delete the subscription and that's it but here it's a bit different so be aware.

Using the same deploy repository we've seen before, and with the same variables loaded into the environment we just need to execute the `uninstall.sh` script and eventually it will get uninstalled.
