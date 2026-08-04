"""
Unit tests for the FastAPI routes in main.py.

All Bedrock and DynamoDB calls are mocked - these tests never touch real
AWS, so they run safely in GitHub Actions without credentials.
"""

import os
import sys
from unittest.mock import patch, MagicMock

import pytest

# Env vars main.py/agent.py require at import time - dummy values for CI
os.environ.setdefault("AWS_REGION", "ap-south-1")
os.environ.setdefault("SESSION_HISTORY_TABLE_NAME", "test-conversations")
os.environ.setdefault("KNOWLEDGE_BASE_ID", "TESTKBID123")
os.environ.setdefault("MODEL_ID", "global.anthropic.claude-haiku-4-5-20251001-v1:0")
os.environ.setdefault("ORDERS_TABLE", "test-orders")
os.environ.setdefault("KB_SOURCE_BUCKET", "test-kb-bucket")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))


@pytest.fixture
def client():
    """Import main.py fresh, with boto3 fully mocked before import so
    module-level clients (dynamodb.Table, bedrock clients) never hit AWS."""
    with patch("boto3.resource") as mock_resource, patch("boto3.client"):
        mock_table = MagicMock()
        mock_resource.return_value.Table.return_value = mock_table

        # agent.py builds a ChatBedrockConverse at import time - patch that too
        with patch("langchain_aws.ChatBedrockConverse") as mock_llm_cls:
            mock_llm_cls.return_value.bind_tools.return_value = MagicMock()

            import importlib
            import main as main_module
            importlib.reload(main_module)

            from fastapi.testclient import TestClient
            test_client = TestClient(main_module.app)
            yield test_client, main_module, mock_table


def test_health_endpoint(client):
    test_client, _, _ = client
    resp = test_client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_chat_rejects_empty_message(client):
    test_client, _, _ = client
    resp = test_client.post("/chat", json={"session_id": "s1", "message": ""})
    assert resp.status_code == 422  # pydantic validation failure


def test_chat_rejects_missing_session_id(client):
    test_client, _, _ = client
    resp = test_client.post("/chat", json={"message": "hello"})
    assert resp.status_code == 422


def test_chat_success(client):
    test_client, main_module, mock_table = client
    mock_table.get_item.return_value = {"Item": {"messages": []}}

    usage = {"input_tokens": 120, "output_tokens": 45, "total_tokens": 165}
    with patch.object(main_module, "run_agent", return_value=("Mocked answer", usage)) as mock_run:
        resp = test_client.post(
            "/chat", json={"session_id": "s1", "message": "What is the refund policy?"}
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["answer"] == "Mocked answer"
        assert body["sources"] == []
        mock_run.assert_called_once()


def test_estimate_cost_usd(client):
    _, main_module, _ = client
    # 1M input tokens + 1M output tokens at default $1/$5 per million
    cost = main_module.estimate_cost_usd(1_000_000, 1_000_000)
    assert round(cost, 2) == 6.00


def test_chat_agent_failure_returns_502(client):
    test_client, main_module, mock_table = client
    mock_table.get_item.return_value = {"Item": {"messages": []}}

    with patch.object(main_module, "run_agent", side_effect=RuntimeError("boom")):
        resp = test_client.post(
            "/chat", json={"session_id": "s1", "message": "anything"}
        )
        assert resp.status_code == 502


def test_get_history_returns_empty_on_dynamo_error(client):
    _, main_module, mock_table = client
    from botocore.exceptions import ClientError

    mock_table.get_item.side_effect = ClientError(
        {"Error": {"Code": "ResourceNotFoundException", "Message": "no table"}},
        "GetItem",
    )
    assert main_module.get_history("s1") == []


def test_save_turn_trims_history_to_max_turns(client):
    _, main_module, mock_table = client
    mock_table.get_item.return_value = {
        "Item": {"messages": [{"role": "user", "content": f"msg{i}", "ts": i} for i in range(30)]}
    }

    main_module.save_turn("s1", "new question", "new answer")

    put_call = mock_table.put_item.call_args
    saved_messages = put_call.kwargs["Item"]["messages"]
    assert len(saved_messages) <= main_module.MAX_HISTORY_TURNS * 3