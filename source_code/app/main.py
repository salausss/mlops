"""
Phase 4 - Agentic RAG API Service

FastAPI wrapper around the LangGraph agent defined in agent.py. The agent
decides per-message whether to search the Knowledge Base or call the
check_order_status tool. Conversation history is persisted in DynamoDB,
keyed by session_id.
"""

import os
import time
import logging
from typing import List

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from agent import run_agent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rag-api")

# ---- Configuration (injected as env vars from the deployment manifest) ----
AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")
SESSION_HISTORY_TABLE_NAME = os.environ["SESSION_HISTORY_TABLE_NAME"]
MAX_HISTORY_TURNS = int(os.environ.get("MAX_HISTORY_TURNS", "6"))

# ---- AWS clients ----
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(SESSION_HISTORY_TABLE_NAME)

app = FastAPI(title="Agentic RAG API Service", version="2.0.0")


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


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    history = get_history(req.session_id)

    try:
        answer = run_agent(history, req.message)
    except Exception as exc:
        logger.exception("Agent invocation failed")
        raise HTTPException(status_code=502, detail="Agent invocation failed") from exc

    save_turn(req.session_id, req.message, answer)
    return ChatResponse(answer=answer, sources=[])