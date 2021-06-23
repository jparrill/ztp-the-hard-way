Table of contents:

<!-- TOC depthfrom:1 orderedlist:false -->

- [Host Internal resources](#host-internal-resources)
  - [HTTPD Server deployment and Configuration](#httpd-server-deployment-and-configuration)
  - [Internal Registry Deployment and Configuration](#internal-registry-deployment-and-configuration)
  - [Download the desired OpenShift ISO and RootFS](#download-the-desired-openshift-iso-and-rootfs)

<!-- /TOC -->

# Host Internal resources

In this section we will cover:

- HTTPD Server deployment and Configuration
- Internal Registry Deployment and Configuration
- Download the desired OpenShift ISOs and host them

## HTTPD Server deployment and Configuration

For that it's a quite easy step, we just need to install the HTTPD server and raise up the service:

```sh
sudo dnf install httpd -y
systemctl enable --now httpd
firewall-cmd --add-service http --permanent
firewall-cmd --reload
```

## Internal Registry Deployment and Configuration

For this task, we need to create the certificate for our Internal Registry, to do that we just need to fill the variables on this script and execute it:

```sh
#!/bin/bash

## Variables to fill
host_fqdn=$( hostname --long )
path=$(pwd)/registry
cert_c="ES"            # Country Name (C, 2 letter code)
cert_s="Spain"         # Certificate State (S)
cert_l="Madrid"        # Certificate Locality (L)
cert_o="adrogallop SL" # Certificate Organization (O)
cert_ou="infra"        # Certificate Organizational Unit (OU)
cert_cn="${host_fqdn}" # Certificate Common Name (CN)

## Functional part of the script
mkdir -p ${path}/{auth,certs,data}

openssl req \
  -newkey rsa:4096 \
  -nodes \
  -sha256 \
  -keyout ${path}/certs/domain.key \
  -x509 \
  -days 3650 \
  -out ${path}/certs/domain.crt \
  -addext "subjectAltName = DNS:${host_fqdn}" \
  -subj "/C=${cert_c}/ST=${cert_s}/L=${cert_l}/O=${cert_o}/OU=${cert_ou}/CN=${cert_cn}"

sudo cp ${path}/certs/domain.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract
htpasswd -bBc ${path}/auth/htpasswd dummy dummy
```

This execution will create a certificate and load it into our host `ca-trust` bundle, in order to trust it as a CA, then it will create the htpasswd file with the user password `dummy` that will be the authentication needed on your Pull Secret to access the registry.

Now we will create the registry configuration, for that we will use something this one:

```
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
compatibility:
  schema1:
    enabled: true
```

**NOTE**: One of the most important parts it's the scheme compatibility, without that, the mirroring process will not work.

After that we need to create our podman registry container to host the OCP and OLM Container Images, to do that we need to execute this script:

```sh
#!/bin/bash

host_fqdn=$( hostname --long )
path=$(pwd)/registry

podman create \
  --name ocpdiscon-registry \
  -p 5000:5000 \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry" \
  -e "REGISTRY_HTTP_SECRET=ALongRandomSecretForRegistry" \
  -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
  -e "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt" \
  -e "REGISTRY_HTTP_TLS_KEY=/certs/domain.key" \
  -e "REGISTRY_COMPATIBILITY_SCHEMA1_ENABLED=true" \
  -v ${path}/data:/var/lib/registry:z \
  -v ${path}/auth:/auth:z \
  -v ${path}/certs:/certs:z \
  -v ${path}/conf/config.yml:/etc/docker/registry/config.yml:z \
  docker.io/library/registry:2

podman start ocpdiscon-registry
```

After executing that we need to ensure we have the Firewall opened:

```
firewall-cmd --add-port 5000/tcp --permanent
firewall-cmd --reload
```

To check that the registry it's up and running, we need to write down the `pull_secret.json`:

```
{
  "auths": {
    "xenomorph.localdomain:5000": {
      "auth": "ZHVtbXk6ZHVtbXk="
    }
  }
}
```

**NOTE**: Ensure you change the `hostname`.

then try to mirror an image manually using `skopeo`:

```sh
skopeo copy --authfile ${PULL_SECRET_JSON} --all docker://quay.io/jparrill/busybox:1.28 docker://xenomorph.localdomain:5000/jparrill/busybox:1.28
```

The image it's a sample and public one and we need to change the `${PULL_SECRET_JSON}` by our PullSecret file path.

## Download the desired OpenShift ISO and RootFS

To download the right ISO and RootFS we just need to go to the published versions of OpenShift:

- Here for Internal Builds: https://openshift-release.apps.ci.l2s4.p1.openshiftapps.com/
- Here for External and Public builds: https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/pre-release/

So with that just download them into the right folder

```sh
sudo wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/pre-release/latest-4.8/rhcos-4.8.0-fc.9-x86_64-live-rootfs.x86_64.img -O /var/www/html/rhcos-4.8.0-fc.9-x86_64-live-rootfs.x86_64.img
sudo wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/pre-release/latest-4.8/rhcos-4.8.0-fc.9-x86_64-live.x86_64.iso -O /var/www/html/rhcos-4.8.0-fc.9-x86_64-live.x86_64.iso
```

That should be it, you can check it with a curl command:

```sh
curl http://$(hostname)/rhcos-4.8.0-fc.9-x86_64-live-rootfs.x86_64.img
```

And the output should be something like:

```console
Warning: Binary output can mess up your terminal. Use "--output -" to tell
Warning: curl to output it to your terminal anyway, or consider "--output
Warning: <FILE>" to save to a file.
```
