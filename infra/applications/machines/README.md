# gpu machineset

Adding a GPU worker node to a Red Hat OpenShift cluster on AWS.

## jq

Create a new MachineSet.

```bash
oc get machineset.machine.openshift.io -A
SOURCE_MACHINESET=sno-5dqmr-worker-us-east-2a
oc -n openshift-machine-api get -o json machineset.machine.openshift.io $SOURCE_MACHINESET  | jq -r > source-machineset.json
NEW_MACHINESET_NAME=${SOURCE_MACHINESET}-gpu

jq -r '.spec.template.spec.providerSpec.value.instanceType = "g5.xlarge"
  | .spec.replicas = 1
  | del(.metadata.selfLink)
  | del(.metadata.uid)
  | del(.metadata.creationTimestamp)
  | del(.metadata.resourceVersion)
  | del(.status)
  ' source-machineset.json > gpu-machineset.json

sed -i "s/$SOURCE_MACHINESET/$NEW_MACHINESET_NAME/g" gpu-machineset.json

diff -Nuar source-machineset.json gpu-machineset.json

oc create -f gpu-machineset.json
```

# envsubst

```bash
export CLUSTER_ID=$(oc get cm config -n openshift-kube-controller-manager -o  'go-template={{index .data "config.yaml"}}' | jq -r '.extendedArguments."cluster-name"[]') # sno-5dqmr
export ROLE=worker
export AWS_AZ=us-east-2a  # must be same az where sno node is
export AWS_DEFAULT_REGION=us-east-2
export INSTANCE_TYPE=g5.xlarge
export VOLUME_SIZE=120
export AWS_AMI=ami-0d4a7b7677c0c883f
export MACHINE_SET_NAME="${CLUSTER_ID}.${INSTANCE_TYPE}.${ROLE}.${AWS_AZ}" # sno-rpvxz-worker-us-east-2b
export SG_NODE="${CLUSTER_ID}"-node                       # sno-rpvxz-node
export SG_LB="${CLUSTER_ID}"-lb                           # sno-rpvxz-lb
export SUBNET_PRIVATE="${CLUSTER_ID}-subnet-private-${AWS_AZ}"  # sno-rpvxz-subnet-private-us-east-2b
export IAM_PROFILE="${CLUSTER_ID}-${ROLE}"-profile        # sno-rpvxz-worker-profile
```

```bash
cat /home/mike/git/rhoai-policy-collection/gitops/applications/machines/machineset.yaml | envsubst | oc apply -f-
```

```bash
oc get machines.machine.openshift.io -A
```
