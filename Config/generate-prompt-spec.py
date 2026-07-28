#!/usr/bin/env python3
"""Validate canonical PromptSpec JSON and generate its Swift representation."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SOURCE = REPOSITORY_ROOT / "prompt-studio" / "lib" / "prompt-spec.json"
TARGET = (
    REPOSITORY_ROOT
    / "KirolePackage"
    / "Sources"
    / "KiroleFeature"
    / "Core"
    / "Network"
    / "PromptSpec.generated.swift"
)

EXPECTED_CHARACTERS = {"joy", "silas", "nova"}
EXPECTED_INTIMACY = {"acquaintance", "familiar", "closeFriend"}
EXPECTED_SCENES = {
    "morningGreeting",
    "companionPhrase",
    "taskEncouragement",
    "scheduleReminder",
    "settlementSummary",
    "smartReminder",
    "settlementQuoteCelebration",
    "settlementQuoteOverloaded",
}
EXPECTED_TOOLS = {
    "haiku",
    "screensaver",
    "taskOverview",
    "daySummary",
    "settlementReview",
    "eventClassification",
    "translation",
}
REQUIRED_TOOL_TEMPLATES = {
    "haiku": {"default"},
    "screensaver": {"resting", "postcard"},
    "taskOverview": {"default"},
    "daySummary": {"empty", "events"},
    "settlementReview": {"default"},
    "eventClassification": {"default"},
    "translation": {"default"},
}
EXPECTED_OUTPUT_BYTES = {
    "morningGreeting": 120,
    "companionPhrase": 120,
    "taskEncouragement": 120,
    "scheduleReminder": 120,
    "settlementSummary": 120,
    "smartReminder": 120,
    "settlementQuoteCelebration": 120,
    "settlementQuoteOverloaded": 120,
    "screensaver": 180,
    "taskOverview": 100,
    "daySummary": 180,
    "settlementReview": 180,
}


def ids(items: list[dict]) -> set[str]:
    return {item["id"] for item in items}


def validate(document: dict) -> None:
    errors: list[str] = []
    if document.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    if not document.get("eventCategoryDefinitions"):
        errors.append("eventCategoryDefinitions must not be empty")
    if ids(document.get("characters", [])) != EXPECTED_CHARACTERS:
        errors.append("characters must be exactly joy, silas, and nova")
    if ids(document.get("intimacyStages", [])) != EXPECTED_INTIMACY:
        errors.append("intimacyStages must contain the three production stages")
    if ids(document.get("personaScenes", [])) != EXPECTED_SCENES:
        errors.append("personaScenes must contain the eight active production scenes")
    if ids(document.get("toolPrompts", [])) != EXPECTED_TOOLS:
        errors.append("toolPrompts must contain the seven independent prompts")

    for collection_name in ("characters", "personaScenes", "toolPrompts"):
        item_ids = [item.get("id") for item in document.get(collection_name, [])]
        if len(item_ids) != len(set(item_ids)):
            errors.append(f"{collection_name} contains duplicate ids")

    required_non_active = {
        "dailySummaryPersonaEnum",
        "fallbackTextPools",
        "focusLocalPhrases",
        "settlementEncouragementMessage",
    }
    if not required_non_active.issubset(ids(document.get("nonActivePaths", []))):
        errors.append("nonActivePaths is missing a required legacy/fixed/invisible path")

    expected_system_placeholders = {
        "petName", "characterPrompt", "intimacyPrompt", "personaPrompt", "schedule", "toneHint"
    }
    actual_system_placeholders = set(re.findall(
        r"\{\{([A-Za-z][A-Za-z0-9]*)\}\}",
        document.get("companionSystemTemplate", ""),
    ))
    if actual_system_placeholders != expected_system_placeholders:
        errors.append("companionSystemTemplate placeholders do not match the Swift compiler")

    for character in document.get("characters", []):
        if not character.get("personaPrompt") or not character.get("characterPrompt"):
            errors.append(f"character {character.get('id')} has an empty prompt")

    parameterized_items = (
        document.get("personaScenes", [])
        + document.get("toolPrompts", [])
    )
    for item in parameterized_items:
        parameters = item.get("parameters", {})
        temperature = parameters.get("temperature")
        max_tokens = parameters.get("maxTokens")
        if not isinstance(temperature, (int, float)) or not 0 <= temperature <= 2:
            errors.append(f"{item.get('id')} temperature must be between 0 and 2")
        if not isinstance(max_tokens, int) or max_tokens <= 0:
            errors.append(f"{item.get('id')} maxTokens must be a positive integer")
        expected_bytes = EXPECTED_OUTPUT_BYTES.get(item.get("id"))
        if expected_bytes is not None and item.get("outputMaxBytes") != expected_bytes:
            errors.append(
                f"{item.get('id')} outputMaxBytes must be {expected_bytes}"
            )

    tools_by_id = {item.get("id"): item for item in document.get("toolPrompts", [])}
    for tool_id, template_names in REQUIRED_TOOL_TEMPLATES.items():
        tool = tools_by_id.get(tool_id, {})
        if not tool.get("systemPromptTemplate"):
            errors.append(f"{tool_id} systemPromptTemplate must not be empty")
        templates = tool.get("userPromptTemplates", {})
        for template_name in template_names:
            if not templates.get(template_name):
                errors.append(f"{tool_id}.{template_name} template must not be empty")

    daily_summary = next(
        (item for item in document.get("nonActivePaths", [])
         if item.get("id") == "dailySummaryPersonaEnum"),
        {},
    )
    if not daily_summary.get("promptTemplate") or not daily_summary.get("parameters"):
        errors.append("dailySummaryPersonaEnum requires promptTemplate and parameters")

    if errors:
        raise ValueError("\n".join(errors))


def swift_source(source_data: bytes) -> str:
    encoded = base64.b64encode(source_data).decode("ascii")
    digest = hashlib.sha256(source_data).hexdigest()
    return f'''// Generated by Config/generate-prompt-spec.py from prompt-studio/lib/prompt-spec.json.
// Do not edit this file directly. Edit the canonical JSON and rerun the generator.

import Foundation

public struct PromptSpecDocument: Codable, Sendable {{
    public let schemaVersion: Int
    public let version: String
    public let securityInstruction: String
    public let eventCategoryDefinitions: String
    public let model: PromptModelSpec
    public let limits: PromptLimitsSpec
    public let globalRules: [String]
    public let companionSystemTemplate: String
    public let characters: [PromptCharacterSpec]
    public let intimacyStages: [PromptIntimacySpec]
    public let personaScenes: [PromptSceneSpec]
    public let toolPrompts: [PromptToolSpec]
    public let nonActivePaths: [PromptNonActivePathSpec]
}}

public struct PromptModelSpec: Codable, Sendable {{
    public let provider: String
    public let primaryModelEnvironmentKey: String
    public let fallbackModel: String
    public let reasoning: PromptReasoningSpec
    public let requireParameters: Bool
    public let reasoningTokenHeadroom: Int
    public let requestTimeoutSeconds: Int
}}

public struct PromptReasoningSpec: Codable, Sendable {{
    public let effort: String
    public let exclude: Bool
}}

public struct PromptLimitsSpec: Codable, Sendable {{
    public let defaultHardwareBytes: Int
    public let hardwareEncoding: String
    public let bubbleLines: Int
    public let userContentTag: String
    public let recentOutputCount: Int
    public let scheduleTaskCount: Int
    public let scheduleEventCount: Int
    public let deadlineTitleCount: Int
    public let eventCategoryMin: Int
    public let eventCategoryMax: Int
}}

public struct PromptWordLimitsSpec: Codable, Sendable {{
    public let `default`: Int
    public let primaryMode: Int
    public let secondaryMode: Int
}}

public struct PromptCharacterSpec: Codable, Sendable {{
    public let id: String
    public let displayName: String
    public let displayNameZh: String
    public let virtue: String
    public let characterPrompt: String
    public let personaPrompt: String
    public let wordLimits: PromptWordLimitsSpec
}}

public struct PromptIntimacySpec: Codable, Sendable {{
    public let id: String
    public let displayName: String
    public let displayNameZh: String
    public let minimumBindingDays: Int
    public let prompt: String
}}

public struct PromptParametersSpec: Codable, Sendable {{
    public let temperature: Double
    public let maxTokens: Int
}}

public struct PromptSceneSpec: Codable, Sendable {{
    public let id: String
    public let group: String
    public let titleZh: String
    public let titleEn: String
    public let status: String
    public let userPromptTemplate: String
    public let variables: [String]
    public let parameters: PromptParametersSpec
    public let outputMaxBytes: Int?
}}

public struct PromptToolSpec: Codable, Sendable {{
    public let id: String
    public let group: String
    public let titleZh: String
    public let titleEn: String
    public let status: String
    public let systemPromptTemplate: String
    public let userPromptTemplates: [String: String]
    public let variables: [String]
    public let parameters: PromptParametersSpec
    public let outputMaxBytes: Int?
    public let outputRules: [String]
}}

public struct PromptNonActivePathSpec: Codable, Sendable {{
    public let id: String
    public let kind: String
    public let titleZh: String
    public let note: String
    public let promptTemplate: String?
    public let parameters: PromptParametersSpec?
}}

public enum KirolePromptSpec {{
    public static let contentHash = "sha256:{digest}"
    private static let encodedSource = "{encoded}"

    public static let sourceJSONData: Data = {{
        guard let data = Data(base64Encoded: encodedSource) else {{
            preconditionFailure("Generated PromptSpec base64 is invalid")
        }}
        return data
    }}()

    public static let document: PromptSpecDocument = {{
        do {{
            return try JSONDecoder().decode(PromptSpecDocument.self, from: sourceJSONData)
        }} catch {{
            preconditionFailure("Generated PromptSpec JSON is invalid: \\(error)")
        }}
    }}()

    public static func character(_ id: String) -> PromptCharacterSpec? {{
        document.characters.first {{ $0.id == id }}
    }}

    public static func intimacy(_ id: String) -> PromptIntimacySpec? {{
        document.intimacyStages.first {{ $0.id == id }}
    }}

    public static func scene(_ id: String) -> PromptSceneSpec? {{
        document.personaScenes.first {{ $0.id == id }}
    }}

    public static func tool(_ id: String) -> PromptToolSpec? {{
        document.toolPrompts.first {{ $0.id == id }}
    }}

    public static func nonActivePath(_ id: String) -> PromptNonActivePathSpec? {{
        document.nonActivePaths.first {{ $0.id == id }}
    }}

    public static func parameters(for id: String) -> PromptParametersSpec? {{
        scene(id)?.parameters ?? tool(id)?.parameters ?? nonActivePath(id)?.parameters
    }}

    public static func render(_ template: String, values: [String: String]) -> String {{
        var result = ""
        var cursor = template.startIndex

        while let opening = template.range(
            of: "{{{{",
            range: cursor..<template.endIndex
        ), let closing = template.range(
            of: "}}}}",
            range: opening.upperBound..<template.endIndex
        ) {{
            result += template[cursor..<opening.lowerBound]
            let key = String(template[opening.upperBound..<closing.lowerBound])
            if let value = values[key] {{
                result += value
            }} else {{
                result += template[opening.lowerBound..<closing.upperBound]
            }}
            cursor = closing.upperBound
        }}

        result += template[cursor..<template.endIndex]
        return result
    }}
}}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero when the generated Swift file is stale",
    )
    args = parser.parse_args()

    source_data = SOURCE.read_bytes()
    document = json.loads(source_data)
    validate(document)
    expected = swift_source(source_data)

    if args.check:
        if not TARGET.exists() or TARGET.read_text() != expected:
            print(
                "PromptSpec Swift is stale. Run Config/generate-prompt-spec.py",
                file=sys.stderr,
            )
            return 1
        print(f"PromptSpec is valid and current: {SOURCE}")
        return 0

    TARGET.write_text(expected)
    print(f"Generated {TARGET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
