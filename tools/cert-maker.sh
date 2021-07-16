#!/bin/bash

## Variables to fill
host_fqdn=$(hostname --long)
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
