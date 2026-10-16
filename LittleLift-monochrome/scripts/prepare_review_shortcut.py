#!/usr/bin/env python3
"""Prepare (not install/run) the three-action native review workflow.

Use the installed bundle/team identifiers, then Apple's `shortcuts sign` CLI.
The model is Ask Each Time: no hidden cloud/provider selection. Parameter names
were inspected in native iOS 27 Shortcuts. Import and model availability still
require verification on the destination device. No workout data is embedded.
"""
import argparse
import plistlib
import uuid
from pathlib import Path

def workflow(bundle, team):
    prepare, model, save = [str(uuid.uuid4()).upper() for _ in range(3)]
    def output(identifier, name):
        return {"Value": {"string": "\ufffc", "attachmentsByRange": {"{0, 1}": {"OutputUUID": identifier, "Type": "ActionOutput", "OutputName": name}}}, "WFSerializationType": "WFTextTokenString"}
    def intent(name, identifier, **parameters):
        return {"WFWorkflowActionIdentifier": bundle + "." + name, "WFWorkflowActionParameters": {
            "AppIntentDescriptor": {"TeamIdentifier": team, "BundleIdentifier": bundle, "Name": "Little Lift", "AppIntentIdentifier": name},
            "UUID": identifier, **parameters}}
    actions = [intent("PrepareWorkoutReviewIntent", prepare), {
        "WFWorkflowActionIdentifier": "is.workflow.actions.askllm", "WFWorkflowActionParameters": {
            "UUID": model, "WFGenerativeResultType": "Text", "WFLLMModel": {"Value": {"Type": "Ask"}, "WFSerializationType": "WFTextTokenAttachment"},
            "WFLLMPrompt": output(prepare, "Prepare Workout Review")}},
        intent("SaveWorkoutReviewIntent", save, reviewJSON=output(model, "Response"))]
    return {"WFWorkflowName": "Little Lift Review", "WFWorkflowActions": actions,
            "WFWorkflowClientVersion": "4013.0.3", "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900", "WFWorkflowIcon": {"WFWorkflowIconStartColor": 0x8E8E93FF, "WFWorkflowIconGlyphNumber": 61440},
            "WFWorkflowTypes": [], "WFWorkflowInputContentItemClasses": [], "WFWorkflowImportQuestions": []}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--team", default="None")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(plistlib.dumps(workflow(args.bundle, args.team)))
    print("Prepared an unsigned review workflow with explicit provider choice. Sign and inspect in Shortcuts before use.")

if __name__ == "__main__": main()
