"""
Phase 4 - Agent definition

Two tools: search_knowledge_base (RAG over the Bedrock Knowledge Base from
Phase 1/2) and check_order_status (DynamoDB lookup). A small LangGraph
graph lets the model decide per-message which one to call, if any.
"""

import os

import boto3
from langchain_core.messages import HumanMessage, AIMessage
from langchain_core.tools import tool
from langchain_aws import ChatBedrockConverse
from langgraph.graph import StateGraph, END, MessagesState
from langgraph.prebuilt import ToolNode

AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
MODEL_ID = os.environ["MODEL_ID"]
ORDERS_TABLE = os.environ.get("ORDERS_TABLE", "orders")
TOP_K = int(os.environ.get("TOP_K", "3"))

bedrock_agent_rt = boto3.client("bedrock-agent-runtime", region_name=AWS_REGION)
orders_table = boto3.resource("dynamodb", region_name=AWS_REGION).Table(ORDERS_TABLE)


@tool
def check_order_status(order_id: str) -> str:
    """Look up the current status of an order by its order ID."""
    resp = orders_table.get_item(Key={"order_id": order_id})
    item = resp.get("Item")
    if not item:
        return f"No order found with ID {order_id}."
    return f"Order {order_id} status: {item['status']}"


@tool
def search_knowledge_base(query: str) -> str:
    """Search company documents for policy or general-knowledge questions."""
    response = bedrock_agent_rt.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": query},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": TOP_K}},
    )
    chunks = [r["content"]["text"] for r in response.get("retrievalResults", [])]
    return "\n\n".join(chunks) if chunks else "No relevant context found."


llm = ChatBedrockConverse(model=MODEL_ID, region_name=AWS_REGION)
tools = [check_order_status, search_knowledge_base]
llm_with_tools = llm.bind_tools(tools)


def agent_node(state: MessagesState):
    return {"messages": [llm_with_tools.invoke(state["messages"])]}


def should_continue(state: MessagesState):
    return "tools" if state["messages"][-1].tool_calls else END


_graph = StateGraph(MessagesState)
_graph.add_node("agent", agent_node)
_graph.add_node("tools", ToolNode(tools))
_graph.set_entry_point("agent")
_graph.add_conditional_edges("agent", should_continue, {"tools": "tools", END: END})
_graph.add_edge("tools", "agent")
compiled_graph = _graph.compile()


def run_agent(history: list[dict], user_message: str) -> str:
    """history: list of {'role': 'user'|'assistant', 'content': str} from DynamoDB."""
    messages = []
    for turn in history:
        cls = HumanMessage if turn["role"] == "user" else AIMessage
        messages.append(cls(content=turn["content"]))
    messages.append(HumanMessage(content=user_message))

    result = compiled_graph.invoke({"messages": messages})
    return result["messages"][-1].content