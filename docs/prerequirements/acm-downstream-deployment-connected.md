Table of contents:

<!-- TOC depthfrom:1 orderedlist:false -->

- [ACM Downstream Deployment Connected](#acm-downstream-deployment-connected)
  - [Permission for downstream repo](#permission-for-downstream-repo)
  - [ACM Downstream deployment](#acm-downstream-deployment)
  - [ACM Uninstall process](#acm-uninstall-process)

<!-- /TOC -->

# ACM Downstream Deployment Connected

**NOTE**: We are following the same procedure they follow in the `README.md` file from the deployment repository all the things are well explained there, so if you have some doubts that is the right place (even including to [deploy a ACM downstream version](https://github.com/open-cluster-management/deploy#deploying-downstream-builds-snapshots-for-product-quality-engineering) .

## Permission for Downstream Repo

First thing we need to follow the instructions mentioned [here](https://github.com/open-cluster-management/deploy#prepare-to-deploy-open-cluster-management-instance-only-do-once) to request a pull permission for repo **quay.io/acm-d**. 

Then you can verify if you have enough permission:

```sh
podman pull --authfile ${PULL_SECRET} quay.io/acm-d/acm-custom-registry:2.3.0-DOWNSTREAM-2021-06-13-16-46-23
```

## ACM Downstream Deployment

To deploy an ACM Downstream version in a connected environment, you will need this repository: **https://github.com/open-cluster-management/deploy**, so clone it and we can continue with the process.

After you clone the repo above, we need to follow these steps:

- Go to the deploy folder, modify file `snapshot.ver` with the snapshot version you want to deploy
- Then ensure you have 3 PVs (at least) available to be bound
- Follow these [steps](https://github.com/open-cluster-management/deploy#prepare-to-deploy-open-cluster-management-instance-only-do-once) to prepare the pull-secret.yaml under prereqs folder
- You will need to export some variables to the Environment

	```sh
	export KUBECONFIG=<kubeconfig path>
	export CUSTOM_REGISTRY_REPO=quay.io:443/acm-d
	export COMPOSITE_BUNDLE=true
	export DEBUG=true
	```

	In my case is something like:

	```sh
	export KUBECONFIG=/home/kni/ipv6/mgmt-hub/auth/kubeconfig
	export CUSTOM_REGISTRY_REPO=quay.io:443/acm-d
	export COMPOSITE_BUNDLE=true
	export DEBUG=true
	```

- Now we just need to execute the deployment script `start.sh`

	```sh
	./start.sh --watch
	```

- When it finishes, we just need to check that all pods are in running state and the installation process take some time to finish so be patient.

	```
	oc get pods -n open-cluster-management
	```

- After the installation has finished you need to double-check that the MultiClusterHub object has been annotated with your custom registry repo, otherwise the managed cluster won't be able to pull the required images.

	```sh
	oc annotate mch multiclusterhub mch-imageRepository='quay.io:443/acm-d'
	```

## ACM Uninstall Process

In the typical situation, you just need to delete the subscription and that's it but here it's a bit different so be aware.

Using the same deploy repository we've seen before, and with the same variables loaded into the environment we just need to execute the `uninstall.sh` script and eventually it will get uninstalled.
