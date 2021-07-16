#!/bin/bash

host_fqdn=$(hostname --long)
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
