"""
Phase 6 - Agentic RAG API Service with Observability

FastAPI wrapper around the LangGraph agent defined in agent.py. Adds:
- CloudWatch custom metrics via Embedded Metric Format (EMF) log lines -
  request count, latency, error rate (Phase 6 dashboard requirement)
- Per-request token usage + estimated $ cost logging
- AWS X-Ray tracing across API -> Bedrock -> DynamoDB (boto3 auto-patched)

Conversation history is persisted in DynamoDB, keyed by session_id.
"""

import os
import time
import json
import logging
from typing import List

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field
from starlette.middleware.base import BaseHTTPMiddleware

from aws_xray_sdk.core import xray_recorder, patch_all

from agent import run_agent
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rag-api")

# ---- Configuration (injected as env vars from the deployment manifest) ----
AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")
SESSION_HISTORY_TABLE_NAME = os.environ["SESSION_HISTORY_TABLE_NAME"]
MAX_HISTORY_TURNS = int(os.environ.get("MAX_HISTORY_TURNS", "6"))

# Bedrock pricing (USD per million tokens) - defaults match Claude Haiku 4.5
# on-demand pricing as of mid-2026. Override via env vars if you switch
# models, since Sonnet/Opus are priced differently. Cross-region inference
# profiles (the "global."/"apac." prefix) can add a small premium on top -
# treat these as an estimate, not a billing-accurate figure.
PRICE_PER_MILLION_INPUT_USD = float(os.environ.get("PRICE_PER_MILLION_INPUT_USD", "1.00"))
PRICE_PER_MILLION_OUTPUT_USD = float(os.environ.get("PRICE_PER_MILLION_OUTPUT_USD", "5.00"))

# ---- AWS clients ----
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(SESSION_HISTORY_TABLE_NAME)

# ---- X-Ray: auto-instrument every boto3 call (Bedrock, DynamoDB, S3) so a
# single request's trace shows exactly where time was spent ----
xray_recorder.configure(service="rag-api")
patch_all()

app = FastAPI(title="Agentic RAG API Service", version="3.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # fine for a demo; lock down for anything real
    allow_methods=["*"],
    allow_headers=["*"],
)


class XRayMiddleware(BaseHTTPMiddleware):
    """Wraps each request in an X-Ray segment. The X-Ray daemon sidecar
    (see k8s/deployment.yaml) forwards segments to AWS on UDP 2000."""

    async def dispatch(self, request: Request, call_next):
        segment = xray_recorder.begin_segment(name="rag-api")
        segment.put_http_meta("url", str(request.url))
        segment.put_http_meta("method", request.method)
        try:
            response = await call_next(request)
            segment.put_http_meta("status", response.status_code)
            return response
        except Exception as exc:
            segment.add_exception(exc)
            raise
        finally:
            xray_recorder.end_segment()


app.add_middleware(XRayMiddleware)


def emit_emf(metrics: dict, dimensions: dict | None = None) -> None:
    """Print a CloudWatch Embedded Metric Format log line. Picked up by
    CloudWatch Container Insights / Fluent Bit from container stdout and
    auto-extracted into custom metrics - no cloudwatch:PutMetricData calls,
    no extra IAM permissions, no per-request AWS API latency."""
    dims = dimensions or {"Service": "rag-api"}
    emf = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": "RagApi",
                    "Dimensions": [list(dims.keys())],
                    "Metrics": [{"Name": k, "Unit": _unit_for(k)} for k in metrics],
                }
            ],
        },
        **dims,
        **metrics,
    }
    print(json.dumps(emf))


def _unit_for(metric_name: str) -> str:
    if "Latency" in metric_name:
        return "Milliseconds"
    if "Cost" in metric_name:
        return "None"  # CloudWatch has no USD unit; graph it as a plain number
    return "Count"


class RequestMetricsMiddleware(BaseHTTPMiddleware):
    """Emits RequestCount / Latency / Errors as EMF on every request -
    this is what feeds the CloudWatch dashboard's request count, p50/p99
    latency, and error rate widgets."""

    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        finally:
            elapsed_ms = (time.perf_counter() - start) * 1000
            emit_emf(
                {
                    "RequestCount": 1,
                    "Latency": elapsed_ms,
                    "Errors": 1 if status_code >= 500 else 0,
                },
                dimensions={"Service": "rag-api", "Path": request.url.path},
            )


app.add_middleware(RequestMetricsMiddleware)


class ChatRequest(BaseModel):
    session_id: str = Field(..., min_length=1)
    message: str = Field(..., min_length=1)


class ChatResponse(BaseModel):
    answer: str
    sources: List[str]


def get_history(session_id: str) -> List[dict]:
    try:
        resp = table.get_item(Key={"session_id": session_id})
    except ClientError:
        logger.exception("DynamoDB get_item failed")
        return []
    return resp.get("Item", {}).get("messages", [])


def save_turn(session_id: str, user_message: str, assistant_message: str) -> None:
    history = get_history(session_id)
    history.append({"role": "user", "content": user_message, "ts": int(time.time())})
    history.append(
        {"role": "assistant", "content": assistant_message, "ts": int(time.time())}
    )
    # Keep only the last N turns (2 messages per turn) to bound item size
    history = history[-(MAX_HISTORY_TURNS * 3):]
    try:
        table.put_item(Item={"session_id": session_id, "messages": history})
    except ClientError:
        logger.exception("DynamoDB put_item failed - continuing without persistence")


def estimate_cost_usd(input_tokens: int, output_tokens: int) -> float:
    return (
        input_tokens / 1_000_000 * PRICE_PER_MILLION_INPUT_USD
        + output_tokens / 1_000_000 * PRICE_PER_MILLION_OUTPUT_USD
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    # Tag this trace with session_id so you can filter/search traces in the
    # X-Ray console by session, not just by time range.
    segment = xray_recorder.current_segment()
    if segment:
        segment.put_annotation("session_id", req.session_id)

    history = get_history(req.session_id)

    try:
        # Explicit subsegment around the whole agent call. patch_all()
        # already breaks out the Bedrock/DynamoDB calls *inside* this, so
        # in the trace waterfall you'll see:
        #   run_agent (total)
        #     -> Bedrock Retrieve / Converse subsegments (auto-instrumented)
        #   The gap between run_agent's total and the sum of those
        #   subsegments is LangGraph's own overhead (tool routing, message
        #   building) - not Bedrock latency.
        with xray_recorder.in_subsegment("run_agent"):
            answer, usage = run_agent(history, req.message)
    except Exception as exc:
        logger.exception("Agent invocation failed")
        raise HTTPException(status_code=502, detail="Agent invocation failed") from exc

    cost_usd = estimate_cost_usd(usage["input_tokens"], usage["output_tokens"])
    logger.info(
        "session=%s input_tokens=%d output_tokens=%d estimated_cost_usd=%.6f",
        req.session_id, usage["input_tokens"], usage["output_tokens"], cost_usd,
    )
    emit_emf(
        {
            "InputTokens": usage["input_tokens"],
            "OutputTokens": usage["output_tokens"],
            "EstimatedCostUSD": round(cost_usd, 6),
        },
        dimensions={"Service": "rag-api"},
    )

    save_turn(req.session_id, req.message, answer)
    return ChatResponse(answer=answer, sources=[])