from __future__ import annotations

import asyncio
import importlib.util
import json
import pathlib
import sys
import unittest
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, call, patch

SRC = pathlib.Path(__file__).parents[1]
sys.path.insert(0, str(SRC))

fake_settings = SimpleNamespace(
    chat_deployment="gpt-5",
    feature_healthcheck=True,
    feature_memory_cosmos=False,
    feature_kb_search=False,
    feature_kv_secret=False,
    feature_blob=False,
    feature_smb_files=False,
    container_registry_name=None,
    agent_image_uri=None,
)
fake_config = ModuleType("config")
fake_config.settings = fake_settings
fake_tools = ModuleType("tools")
fake_tools.ToolEntry = dict
fake_tools.registered_map = lambda: {}
fake_tools.registered_tools = lambda: []
sys.modules["config"] = fake_config
sys.modules["tools"] = fake_tools

import orchestration

healthcheck_spec = importlib.util.spec_from_file_location(
    "healthcheck_under_test", SRC / "tools" / "healthcheck.py"
)
healthcheck = importlib.util.module_from_spec(healthcheck_spec)
healthcheck_spec.loader.exec_module(healthcheck)


def entry(name, invoke):
    return {"name": name, "spec": {"type": "function", "function": {"name": name}}, "invoke": invoke}


def payload(text):
    assert text.startswith(orchestration.SMOKE_PREFIX)
    return json.loads(text.removeprefix(orchestration.SMOKE_PREFIX))


class SmokeTests(unittest.IsolatedAsyncioTestCase):
    async def test_memory_round_trip_passes(self):
        calls = []

        async def invoke(args):
            calls.append(args)
            if args["action"] == "recall":
                return {"facts": [{"key": "favoriteColor", "value": "teal"}]}
            return {"ok": True}

        result = payload(await orchestration.run_smoke("SMOKE:memory", {"memory": entry("memory", invoke)}))
        self.assertEqual("PASS", result["status"])
        self.assertEqual(["remember", "recall"], [call["action"] for call in calls])

    async def test_disabled_tool_skips(self):
        result = payload(await orchestration.run_smoke("SMOKE:blob", {}))
        self.assertEqual("SKIP", result["status"])

    async def test_kv_value_is_redacted(self):
        async def invoke(_args):
            return {"name": "demo-flag", "value": "super-secret"}

        text = await orchestration.run_smoke("SMOKE:kv", {"kv": entry("kv", invoke)})
        self.assertNotIn("super-secret", text)
        self.assertEqual({"name": "demo-flag", "value_present": True}, payload(text)["result"])

    async def test_semantic_failure_is_reported(self):
        async def invoke(_args):
            return {"blobs": []}

        result = payload(await orchestration.run_smoke("SMOKE:blob", {"blob": entry("blob", invoke)}))
        self.assertEqual("FAIL", result["status"])
        self.assertEqual("semantic smoke assertion failed", result["error"])

    async def test_dependency_exception_is_reported(self):
        async def invoke(_args):
            raise RuntimeError("service unavailable")

        result = payload(await orchestration.run_smoke("SMOKE:kb", {"kb": entry("kb", invoke)}))
        self.assertEqual("FAIL", result["status"])
        self.assertIn("service unavailable", result["error"])


class InteractiveTests(unittest.IsolatedAsyncioTestCase):
    async def test_model_tool_round_trip(self):
        async def invoke(args):
            return {"echo": args["value"]}

        tool_call = SimpleNamespace(
            id="call-1",
            function=SimpleNamespace(name="demo", arguments='{"value":"ok"}'),
            model_dump=lambda: {
                "id": "call-1",
                "type": "function",
                "function": {"name": "demo", "arguments": '{"value":"ok"}'},
            },
        )
        responses = [
            SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=None, tool_calls=[tool_call]))]),
            SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content="done", tool_calls=[]))]),
        ]
        fake_entry = entry("demo", invoke)

        with patch.object(orchestration, "registered_tools", return_value=[fake_entry]), patch.object(
            orchestration, "_complete", side_effect=responses
        ):
            result = await orchestration.run_interactive("test", asyncio.Event())

        self.assertEqual("done", result)

    async def test_cancelled_request_does_not_call_model(self):
        signal = asyncio.Event()
        signal.set()
        with patch.object(orchestration, "_complete") as complete:
            result = await orchestration.run_interactive("test", signal)
        self.assertEqual("Request cancelled.", result)
        complete.assert_not_called()


class HealthcheckTests(unittest.IsolatedAsyncioTestCase):
    def test_foundry_check_retries_transient_failure(self):
        openai_client = Mock()
        completion = openai_client.return_value.chat.completions.create
        completion.side_effect = [
            RuntimeError("not propagated"),
            RuntimeError("still propagating"),
            [],
        ]
        fake_clients = ModuleType("clients")
        fake_clients.openai_client = openai_client
        with patch.dict(sys.modules, {"clients": fake_clients}), patch.object(
            healthcheck.time, "sleep"
        ) as sleep:

            healthcheck._check_foundry()

        self.assertEqual(3, completion.call_count)
        self.assertEqual("gpt-5", completion.call_args.kwargs["model"])
        self.assertEqual(16, completion.call_args.kwargs["max_completion_tokens"])
        self.assertEqual([call(1), call(2)], sleep.call_args_list)

    async def test_disabled_dependencies_are_skipped(self):
        with patch.object(healthcheck, "_check_foundry", return_value=None), patch.object(
            healthcheck.settings, "feature_memory_cosmos", False
        ), patch.object(healthcheck.settings, "feature_kb_search", False), patch.object(
            healthcheck.settings, "feature_kv_secret", False
        ), patch.object(healthcheck.settings, "feature_blob", False), patch.object(
            healthcheck.settings, "feature_smb_files", False
        ), patch.object(healthcheck, "_check_acr", return_value=("SKIP", 0, "not configured")):
            result = await healthcheck.invoke({})

        self.assertEqual(1, result["summary"]["pass"])
        self.assertEqual(0, result["summary"]["fail"])
        self.assertEqual(6, result["summary"]["skip"])


if __name__ == "__main__":
    unittest.main()