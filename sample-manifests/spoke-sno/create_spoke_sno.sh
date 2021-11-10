export CLUSTER_NAME=mgmt-spoke1

oc create ns ${CLUSTER_NAME}
oc project ${CLUSTER_NAME}
oc patch hiveconfig hive --type merge -p '{"spec":{"targetNamespace":"hive","logLevel":"debug","featureGates":{"custom":{"enabled":["AlphaAgentInstallStrategy"]},"featureSet":"Custom"}}}'
sleep 30
oc create -f 01_AI-pull-secret.yaml -f 02_AgentClusterInstall.yaml -f 03_ClusterDeployment.yaml -f 04_KlusterletAddonConfig.yaml -f 05_ManagedCluster.yaml
sleep 5
oc create -f 06_InfraEnv.yaml

for i in {1..10}; do
	sleep 5
	ISO_URL=$(oc get infraenv ${CLUSTER_NAME} -o jsonpath='{.status.isoDownloadURL}')
	if [[ ! -z ${ISO_URL} ]]; then
		oc create -f 07_BMH-sno.yaml
		echo "Done"
		break
	elif [[ -z ${ISO_URL} ]] && [[ ${i} -gt 10 ]]; then
		echo "ERROR: No InfraEnv URL field on the K8s object"
		exit 1
	fi
done
