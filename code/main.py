from fastapi import FastAPI
from pydantic import BaseModel


app = FastAPI()


class PipelineFailure(BaseModel):
    pod_name: str
    container_name: str
    namespace: str


@app.post("/report-failure")
async def report_failure(pipeline_failure: PipelineFailure):
    print(f'received report-failure request with payload: '
          f'{pipeline_failure}')
    return pipeline_failure