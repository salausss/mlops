"""
Phase 3 - RAG API Service

Retrieves context from the Bedrock Knowledge Base built in Phase 1/2,
sends it + the user's question to Claude via the Bedrock Converse API,
and returns a grounded answer with source citations.

Conversation history is persisted in DynamoDB, keyed by session_id.
"""

import os
import time
import logging
from typing import List

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rag-api")

# ---- Configuration (injected as env vars from the ECS task definition) ----
AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
# Use whichever Claude model you already validated during Phase 1/2 KB
# testing. Newer Claude models on Bedrock are addressed via cross-region
# inference profile IDs, e.g. "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
# rather than a bare "anthropic.claude-..." model ID - check what your KB
# test script used and reuse it here for consistency.
MODEL_ID = os.environ["MODEL_ID"]
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
TOP_K = int(os.environ.get("TOP_K", "3"))
MAX_HISTORY_TURNS = int(os.environ.get("MAX_HISTORY_TURNS", "6"))

# ---- AWS clients ----
bedrock_agent_rt = boto3.client("bedrock-agent-runtime", region_name=AWS_REGION)
bedrock_rt = boto3.client("bedrock-runtime", region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(DYNAMODB_TABLE)

app = FastAPI(title="RAG API Service", version="1.0.0")

SYSTEM_PROMPT = (
    "You are a helpful assistant. Answer the user's question using ONLY the "
    "context provided below. If the context does not contain the answer, "
    "say you don't have enough information. Always be concise and cite the "
    "source document(s) you used."
)


class ChatRequest(BaseModel):
    session_id: str = Field(..., min_length=1)
    message: str = Field(..., min_length=1)


class ChatResponse(BaseModel):
    answer: str
    sources: List[str]


def retrieve_context(query: str) -> List[dict]:
    """Pull the top-K chunks from the Bedrock Knowledge Base for this query."""
    try:
        response = bedrock_agent_rt.retrieve(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            retrievalQuery={"text": query},
            retrievalConfiguration={
                "vectorSearchConfiguration": {"numberOfResults": TOP_K}
            },
        )
    except ClientError as exc:
        logger.exception("Knowledge Base retrieve failed")
        raise HTTPException(status_code=502, detail="Retrieval failed") from exc

    chunks = []
    for result in response.get("retrievalResults", []):
        text = result.get("content", {}).get("text", "")
        uri = result.get("location", {}).get("s3Location", {}).get("uri", "unknown")
        chunks.append({"text": text, "source": uri})
    return chunks


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
    history = history[-(MAX_HISTORY_TURNS * 2):]
    try:
        table.put_item(Item={"session_id": session_id, "messages": history})
    except ClientError:
        logger.exception("DynamoDB put_item failed - continuing without persistence")


def build_converse_messages(history: List[dict], context: str, question: str) -> List[dict]:
    messages = []
    for turn in history:
        messages.append({"role": turn["role"], "content": [{"text": turn["content"]}]})
    user_turn = f"Context:\n{context}\n\nQuestion: {question}"
    messages.append({"role": "user", "content": [{"text": user_turn}]})
    return messages


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    chunks = retrieve_context(req.message)
    if not chunks:
        context = "No relevant context was found."
        sources: List[str] = []
    else:
        context = "\n\n".join(c["text"] for c in chunks)
        sources = sorted({c["source"] for c in chunks})

    history = get_history(req.session_id)
    messages = build_converse_messages(history, context, req.message)

    try:
        response = bedrock_rt.converse(
            modelId=MODEL_ID,
            messages=messages,
            system=[{"text": SYSTEM_PROMPT}],
            inferenceConfig={"maxTokens": 1024, "temperature": 0.2},
        )
    except ClientError as exc:
        logger.exception("Bedrock Converse call failed")
        raise HTTPException(status_code=502, detail="Model invocation failed") from exc

    answer = response["output"]["message"]["content"][0]["text"]
    save_turn(req.session_id, req.message, answer)

    return ChatResponse(answer=answer, sources=sources)
