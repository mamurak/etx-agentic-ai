#!/bin/bash
set -o pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly ORANGE='\033[38;5;214m'
readonly NC='\033[0m' # No Color

wait_for_openshift_api() {
    local i=0
    HOST=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443/healthz
    until [ $(curl --connect-timeout 3 -k -s -o /dev/null -w %{http_code} ${HOST}) = "200" ]
    do
        echo -e "${GREEN}Waiting for 200 response from openshift api ${HOST}.${NC}"
        sleep 5
        ((i=i+1))
        if [ $i -gt 100 ]; then
            echo -e "🕱${RED}Failed - OpenShift api ${HOST} never ready?.${NC}"
            exit 1
        fi
    done
    echo "🌴 wait_for_openshift_api ran OK"
}

force_argocd_sync() {
    echo "🌴 Running force_argocd_sync..."

    # these apps need vault secrets
    for x in mcp-github-local-cluster policy-collection-sno llama-stack-playground-local-cluster; do
    oc -n openshift-gitops patch applications.argoproj.io $x --type=merge --patch '
operation:
  initiatedBy:
    username: admin
  sync:
    syncStrategy:
      hook: {}
'
    done
    for x in mcp-github-local-cluster policy-collection-sno llama-stack-playground-local-cluster; do
        oc -n openshift-gitops annotate applications.argoproj.io/$x argocd.argoproj.io/refresh="hard"
    done
    echo "🌴 force_argocd_sync ran OK"
}

check_pods_allocatable() {
    echo "🌴 Running check_pods_allocatable..."
    local i=0
    PODS=$(oc get $(oc get node -o name -l node-role.kubernetes.io/master="") -o=jsonpath={.status.allocatable.pods})
    until [ "$PODS" == 500 ]
    do
        echo -e "${GREEN}Waiting for pods $PODS to equal 500.${NC}"
        ((i=i+1))
        if [ $i -gt 300 ]; then
            echo -e "🕱${RED}Failed - node allocatable pods wrong - $PODS?.${NC}"
            exit 1
        fi
        if [ $i -eq 100 ]; then
            echo -e "💀${ORANGE}Warn - check_pods_allocatable, forcing set-max-pods, continuing ${NC}"
            # MC bug, does not always trigger it seems - argocd will recreate this
            oc delete KubeletConfig set-max-pods
        fi
        sleep 10
        PODS=$(oc get $(oc get node -o name -l node-role.kubernetes.io/master="") -o=jsonpath={.status.allocatable.pods})
    done
    echo "🌴 check_pods_allocatable $PODS ran OK"
}

check_gpus_allocatable() {
    echo "🌴 Running check_gpus_allocatable..."
    local i=0
    GPUS=$(oc get $(oc get node -o name -l node-role.kubernetes.io/master="") -o=jsonpath={.status.allocatable.nvidia\\.com\\/gpu})
    until [ "$GPUS" == 8 ]
    do
        echo -e "${GREEN}Waiting for gpus $GPUS to equal 8.${NC}"
        ((i=i+1))
        if [ $i -gt 200 ]; then
            echo -e "🕱${RED}Failed - node allocatable gpus wrong - $GPUS?.${NC}"
            exit 1
        fi
        sleep 10
        # buggy 4.19 - sometimes the image-prune job holds up cluster install completion which holds up gpu operator
        STATUS=$(oc -n openshift-image-registry get jobs 2>&1 | grep Failed | wc -l)
        if [ "$STATUS" -gt 0 ]; then
            oc -n openshift-image-registry delete cronjob image-pruner
        fi
        GPUS=$(oc get $(oc get node -o name -l node-role.kubernetes.io/master="") -o=jsonpath={.status.allocatable.nvidia\\.com\\/gpu})
    done
    echo "🌴 check_gpus_allocatable $GPUS ran OK"
}

check_llm_pods() {
    echo "🌴 Running check_llm_pods..."
    local i=0
    PODS=$(oc get pods -n llama-serving | grep -e Running | wc -l)
    until [ "$PODS" == 2 ]
    do
        echo -e "${GREEN}Waiting for llm pods $PODS to equal 2.${NC}"
        ((i=i+1))
        if [ $i -gt 200 ]; then
            echo -e "🕱${RED}Failed - llm pods wrong - $PODS?.${NC}"
            exit 1
        fi
        sleep 10
        # this is because we need llama to start first before deepseek
        # vllm gpu_memory_utilization is calc on "current available" not actual
        # and we cannot predict who will start up first
        if [ "$PODS" == 1 ]; then
            DEEPSEEK_STATUS=$(oc -n llama-serving get $(oc get pods -n llama-serving -l app=isvc.sno-deepseek-qwen3-vllm-predictor -o name) -o=jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
            LLAMA_STATUS=$(oc -n llama-serving get $(oc get pods -n llama-serving -l app=isvc.llama3-2-3b-predictor -o name) -o=jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
            if [ "$DEEPSEEK_STATUS" == "True" ] && [ "$LLAMA_STATUS" != "True" ]; then
                echo -e "${ORANGE}Killing deepseek pod so llama starts up first.${NC}"
                oc -n llama-serving delete $(oc get pods -n llama-serving -l app=isvc.sno-deepseek-qwen3-vllm-predictor -o name)
            fi
        fi
        PODS=$(oc get pods -n llama-serving | grep -e Running | wc -l)
    done
    echo "🌴 check_llm_pods $PODS ran OK"
}

[ -z "$BASE_DOMAIN" ] && echo "🕱 Error: must supply BASE_DOMAIN in env" && exit 1
[ -z "$CLUSTER_NAME" ] && echo "🕱 Error: must supply CLUSTER_NAME in env" && exit 1

echo "🌴 BASE_DOMAIN set to $BASE_DOMAIN"
echo "🌴 CLUSTER_NAME set to $CLUSTER_NAME"

wait_for_openshift_api
force_argocd_sync
check_pods_allocatable
check_gpus_allocatable
check_llm_pods

echo -e "\n🌻${GREEN}Check Install ended OK.${NC}🌻\n"
exit 0
