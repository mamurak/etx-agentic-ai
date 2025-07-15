#!/bin/bash
set -o pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly ORANGE='\033[38;5;214m'
readonly NC='\033[0m' # No Color

# setup secrets for gitops
# https://eformat.github.io/rainforest-docs/#/2-platform-work/3-secrets

[ -z "$AWS_PROFILE" ] && echo "🕱 Error: must supply AWS_PROFILE in env" && exit 1
[ -z "$BASE_DOMAIN" ] && echo "🕱 Error: must supply BASE_DOMAIN in env" && exit 1
[ -z "$ADMIN_PASSWORD" ] && echo "🕱 Error: must supply ADMIN_PASSWORD in env" && exit 1
[ -z "$CLUSTER_NAME" ] && echo "🕱 Error: must supply CLUSTER_NAME in env" && exit 1
[ -z "$ANSIBLE_VAULT_SECRET" ] && echo "🕱 Error: must supply ANSIBLE_VAULT_SECRET in env" && exit 1

# use login
export KUBECONFIG=~/.kube/config.${AWS_PROFILE}

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
wait_for_openshift_api

login () {
    echo "💥 Login to OpenShift..."
    local i=0
    oc login -u admin -p ${ADMIN_PASSWORD} --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
    until [ "$?" == 0 ]
    do
        echo -e "${GREEN}Waiting for 0 rc from oc commands.${NC}"
        ((i=i+1))
        if [ $i -gt 100 ]; then
            echo -e "🕱${RED}Failed - oc login never ready?.${NC}"
            exit 1
        fi
        sleep 10
        oc login -u admin -p ${ADMIN_PASSWORD} --server=https://api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443
    done
    echo "💥 Login to OpenShift Done"
}
login

wait_for_project() {
    local i=0
    local project="$1"
    STATUS=$(oc get project $project -o=go-template --template='{{ .status.phase }}')
    until [ "$STATUS" == "Active" ]
    do
        echo -e "${GREEN}Waiting for project $project.${NC}"
        sleep 5
        ((i=i+1))
        if [ $i -gt 200 ]; then
            echo -e "🚨${RED}Failed waiting for project $project never Succeeded?.${NC}"
            exit 1
        fi
        STATUS=$(oc get project $project -o=go-template --template='{{ .status.phase }}')
    done
    echo "🌴 wait_for_project $project ran OK"
}
wait_for_project vault

wait_for_vault_pod () {
    echo "💥 Waiting for vault pod ..."
    local i=0
    STATUS=$(oc get pod vault-0 -n vault -o jsonpath='{.status.phase}')
    until [ "$STATUS" == "Running" ]
    do
        echo -e "${GREEN}Waiting for 0 rc from oc commands.${NC}"
        ((i=i+1))
        if [ $i -gt 100 ]; then
            echo -e "🕱${RED}Failed - oc never ready?.${NC}"
            exit 1
        fi
        sleep 5
        STATUS=$(oc get pod vault-0 -n vault -o jsonpath='{.status.phase}')
    done
    echo "💥 Waiting for vault pod ran OK"
}
wait_for_vault_pod

check_done() {
    echo "🌴 Running check_done..."
    STATUS=$(oc -n vault get $(oc get pods -n vault -l app.kubernetes.io/instance=vault -o name) -o=jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$STATUS" != "True" ]; then
      echo -e "💀${ORANGE}Warn - check_done not ready for vault, continuing ${NC}"
      return 1
    else
      echo "🌴 check_done ran OK"
    fi
    return 0
}

if check_done; then
    echo -e "\n🌻${GREEN}Vault setup OK.${NC}🌻\n"
    exit 0;
fi

init () {
    echo "💥 Init Vault..."
    local i=0
    oc -n vault exec vault-0 -- vault operator init -key-threshold=1 -key-shares=1 -tls-skip-verify 2>&1 | tee /tmp/vault-init-${AWS_PROFILE}
    until [ "${PIPESTATUS[0]}" == 0 ]
    do
        echo -e "${GREEN}Waiting for 0 rc from oc commands.${NC}"
        ((i=i+1))
        if [ $i -gt 100 ]; then
            echo -e "🕱${RED}Failed - vault init never ready?.${NC}"
            exit 1
        fi
        sleep 10
        oc -n vault exec vault-0 -- vault operator init -key-threshold=1 -key-shares=1 -tls-skip-verify 2>&1 | tee /tmp/vault-init-${AWS_PROFILE}
    done
    echo "💥 Init Vault Done"
}
init

export UNSEAL_KEY=$(cat /tmp/vault-init-${AWS_PROFILE} | grep -e 'Unseal Key 1' | awk '{print $4}')
if [ -z "$UNSEAL_KEY" ]; then
    echo -e "🕱${RED}Failed - to extract unseal key from vault init output${NC}"
    exit 1
fi
export ROOT_TOKEN=$(cat /tmp/vault-init-${AWS_PROFILE} | grep -e 'Initial Root Token' | awk '{print $4}')
if [ -z "$ROOT_TOKEN" ]; then
    echo -e "🕱${RED}Failed - to get root token ?${NC}"
    exit 1
fi
rm -f /tmp/vault-init-${AWS_PROFILE} 2>&1>/dev/null

unseal() {
    echo "💥 Unseal Vault..."
    local i=0
    oc -n vault exec vault-0 -- vault operator unseal -tls-skip-verify $UNSEAL_KEY
    until [ "$?" == 0 ]
    do
        echo -e "${GREEN}Waiting for 0 rc from oc commands.${NC}"
        ((i=i+1))
        if [ $i -gt 20 ]; then
            echo -e "🕱${RED}Failed - to unseal vault ?${NC}"
            exit 1
        fi
        sleep 5
        oc -n vault exec vault-0 -- vault operator unseal -tls-skip-verify $UNSEAL_KEY
    done
    echo "💥 Unseal Vault Done"
}
unseal

export VAULT_ROUTE=vault-vault.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
export VAULT_ADDR=https://${VAULT_ROUTE}
export VAULT_SKIP_VERIFY=true

login() {
    echo "💥 Login Vault..."
    local i=0
    vault login token=${ROOT_TOKEN}
    until [ "$?" == 0 ]
    do
        echo -e "${GREEN}Waiting for 0 rc from oc commands.${NC}"
        ((i=i+1))
        if [ $i -gt 100 ]; then
            echo -e "🕱${RED}Failed - to login to vault ?${NC}"
            exit 1
        fi
        sleep 10
        vault login token=${ROOT_TOKEN}
    done
    echo "💥 Login Vault Done"
}
login

export APP_NAME=vault
export PROJECT_NAME=openshift-gitops
export CLUSTER_DOMAIN=apps.${CLUSTER_NAME}.${BASE_DOMAIN}

vault auth enable -path=$CLUSTER_DOMAIN-${PROJECT_NAME} kubernetes

vault policy write $CLUSTER_DOMAIN-$PROJECT_NAME-kv-read -<< EOF
path "kv/data/ocp/${CLUSTER_NAME}/*" {
capabilities=["read","list"]
}
EOF

vault secrets enable -path=kv/ -version=2 kv

vault write auth/$CLUSTER_DOMAIN-$PROJECT_NAME/role/$APP_NAME \
bound_service_account_names=$APP_NAME \
bound_service_account_namespaces=$PROJECT_NAME \
policies=$CLUSTER_DOMAIN-$PROJECT_NAME-kv-read \
period=120s

CA_CRT=$(openssl s_client -showcerts -connect api.${CLUSTER_NAME}.${BASE_DOMAIN}:6443 2>&1 | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}')

vault write auth/$CLUSTER_DOMAIN-${PROJECT_NAME}/config \
kubernetes_host="$(oc whoami --show-server)" \
kubernetes_ca_cert="$CA_CRT"

ansible-vault decrypt secrets/vault-sno --vault-password-file <(echo "$ANSIBLE_VAULT_SECRET")
sh secrets/vault-sno $ROOT_TOKEN
ansible-vault encrypt secrets/vault-sno --vault-password-file <(echo "$ANSIBLE_VAULT_SECRET")

echo -e "\n🌻${GREEN}Vault setup OK.${NC}🌻\n"
exit 0