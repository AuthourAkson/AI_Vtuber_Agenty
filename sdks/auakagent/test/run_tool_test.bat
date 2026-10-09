@echo off
set TOOL_CALL_LLM=openai
cd D:\project\GitHub\wenzagent
dart test test\llm_tool_calling_test.dart --timeout 180s --chain-stack-traces -r expanded
