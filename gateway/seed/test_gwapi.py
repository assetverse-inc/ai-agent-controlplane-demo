"""Unit tests for the pure helpers in _gwapi (no network)."""

from _gwapi import match_tool_ids, norm


def test_norm_strips_separators_and_lowercases():
    assert norm("Register_MCP-Server") == "registermcpserver"
    assert norm("add_tax") == "addtax"


def test_match_tool_ids_matches_by_normalized_name():
    # longer "sales-tax-add-tax" is listed FIRST: old order-sensitive code would
    # wrongly return "t2" for "add_tax" because its endswith match came first.
    tools = [
        {"name": "sales-tax-add-tax", "id": "t2"},
        {"name": "add_tax", "id": "t1"},
        {"name": "convert", "id": "t3"},
    ]
    # exact-normalized "add_tax" must beat the endswith match on the longer name
    assert match_tool_ids(tools, ["add_tax"]) == ["t1"]
    # "convert" resolves to t3
    assert match_tool_ids(tools, ["convert"]) == ["t3"]


def test_match_tool_ids_skips_unknown_and_dedupes():
    tools = [{"name": "add_tax", "id": "t1"}]
    assert match_tool_ids(tools, ["add_tax", "nope", "add_tax"]) == ["t1"]
