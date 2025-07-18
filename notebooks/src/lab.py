from os import environ

# for communication with Llama Stack
from llama_stack_client import Agent, LlamaStackClient
from llama_stack_client.lib.agents.event_logger import EventLogger
from llama_stack_client.lib.agents.react.agent import ReActAgent
from llama_stack_client.lib.agents.react.tool_parser import ReActOutput

# pretty print of the results returned from the model/agent
import sys
from termcolor import cprint
from dotenv import load_dotenv


load_dotenv('env')
print('loaded environment variables')

model_id = environ.get('LLM_MODEL_ID')
ocp_mcp_url = environ.get("REMOTE_OCP_MCP_URL")
temperature = float(environ.get('TEMPERATURE', 0.0))
if temperature > 0.0:
    top_p = float(environ.get('TOP_P', 0.95))
    strategy = {'type': 'top_p', 'temperature': temperature, 'top_p': top_p}
else:
    strategy = {'type': 'greedy'}

max_tokens = 6000
sampling_params = {
    'strategy': strategy,
    'max_tokens': max_tokens,
}
stream = 'True'


def get_llama_stack_client():
    base_url = environ.get('LLAMA_STACK_URL')
    client = LlamaStackClient(base_url=base_url)

    print('Instantiated Llama Stack client')
    return client


def get_agent(instructions, *tools):
    client = get_llama_stack_client()
    agent = Agent(
        client, 
        model=model_id,
        instructions=instructions,
        tools=list(tools),
        sampling_params=sampling_params
    )

    print('Instantiated agent')
    return agent


def get_react_agent(tools):
    client = get_llama_stack_client()
    agent = ReActAgent(
        client=client,
        model=model_id,
        tools=tools,
        response_format={
            "type": "json_schema",
            "json_schema": ReActOutput.model_json_schema(),
        },
        sampling_params={"max_tokens":512},
    )
    print('Instantiated ReAct agent')
    return agent


def run_session(agent, session_name, user_prompts):
    session_id = agent.create_session(session_name)
    print(f'Created new session {session_name}')
    print(f'Looping over user prompts: {user_prompts}')
    for prompt in user_prompts:
        print("\n"+"="*50)
        cprint(f"Processing user query: {prompt}", "blue")
        print("="*50)
        response = agent.create_turn(
            messages=[
                {
                    "role": "user",
                    "content": prompt,
                }
            ],
            session_id=session_id,
            stream='True'
        )
        for log in EventLogger().log(response):
            log.print()