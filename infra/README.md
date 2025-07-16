# rhoai-policy-collection

Showcases OLM v0,1 support for RHOAI Clusters using policy-as-code and Advanced Cluster Manager.

Showcases BYO [ModelCar Catalog](https://github.com/eformat/modelcar-catalog) deployment of popular open-weight models (deepseek-r1-qwen-distillation, granite, granite-vision, llama) using [vLLM](https://github.com/vllm-project/vllm) and [LLama.cpp](https://github.com/ggml-org/llama.cpp) runtimes.

This repo is deployed using [SNO on SPOT](https://github.com/eformat/sno-for-100) in AWS with a g6 NVIDIA instance as an example accelerated infrastructure

> How-to run your GenAI infrastructure - (model as a service, inference as a service) - on the smell of an oily RAG.

## Prerequisite

OpenShift Cluster with cluster-admin access. See [SNO on SPOT](https://github.com/eformat/sno-for-100) using:

```bash
export INSTANCE_TYPE=g6.8xlarge
export ROOT_VOLUME_SIZE=400
export OPENSHIFT_VERSION=4.18.14
```

## Bootstrap

Installs ArgoCD and ACM

```bash
kustomize build --enable-helm bootstrap | oc apply -f-
```

Create CR's

```bash
oc apply -f gitops/bootstrap/setup-cr.yaml
```

We keep Auth, PKI, Storage separate for now as these are Infra specific.

Create htpasswd admin user

```bash
./gitops/bootstrap/users.sh
```

Install LE Certs

```bash
./gitops/bootstrap/certficates.sh
```

Install Extra AWS Storage

```bash
./gitops/bootstrap/storage.sh
```

## Setup app-of-apps storage

With only `storage.yaml` in the app-of-apps folder:

```bash
oc apply -f gitops/app-of-apps/sno-app-of-apps.yaml
```

And set SC default

```bash
oc annotate sc/lvms-vgsno storageclass.kubernetes.io/is-default-class=true
oc annotate sc/gp3-csi storageclass.kubernetes.io/is-default-class-
```

This uses the default storage we setup for LVM

## Vault Secrets

Install `vault.yaml` in the app-of-apps folder.

Setup Vault Auth for ArgoCD

```bash
./gitops/bootstrap/vault-setup.sh
```

## Installs Policy Collection for RHOAI

WIP - base `rhoai` DSC currently.
