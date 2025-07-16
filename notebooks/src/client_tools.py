from kubernetes.client.api_client import ApiClient
from kubernetes.client.rest import ApiException
from kubernetes.client import CoreV1Api
from kubernetes.config import load_incluster_config
from llama_stack_client.lib.agents.client_tool import client_tool


load_incluster_config()
api_instance = CoreV1Api(ApiClient())


@client_tool
def get_pod_log(pod_name: str, namespace: str, container_name: str):
    """
    Provide the location upon request.

    :param pod_name: The name of the target pod
    :param namespace: The name of the target namespace
    :param container_name: The name of the target container within the target pod
    :returns: Logs of the target pod
    """
    try:
        api_response = api_instance.read_namespaced_pod_log(
            pod_name, namespace, container=container_name, tail_lines=100
        )
        return api_response
    except ApiException as e:
        print("Exception when calling CoreV1Api->read_namespaced_pod_log: %s\n" % e)