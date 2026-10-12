#!/usr/bin/env python3
"""Summarize an already-saved R4 compact audit; never accesses Figma.

Usage: python3 design/tools/summarize-r4-audit.py saved-compact.json
       python3 design/tools/summarize-r4-audit.py saved-compact.json --samples 3 --json

Exit 0 means parsed, not accepted. Exit 2 means input/schema parsing failed.
Missing fields are reported as unknown. Counts remain exact; samples are bounded.
"""

import argparse
import json
from pathlib import Path


THEMES = ("Light", "Dark")
COUNT_FIELDS = (
    "roots", "primaryRoots", "legacyRoots", "visibleRoots", "nodes", "visibleNodes",
    "texts", "visibleTexts", "reactionLayers", "visibleReactionLayers", "reactions",
    "nodeActions", "visibleNodeActions", "closeBackActions",
)
PRIORITY = {
    # P0: establish audit coverage before interpreting product findings.
    "missingSections": 0, "changedSnapshot": 0, "rootNodeBudget": 0,
    # P1: inspect visible sources first; these are candidates, not verdicts.
    "invalidTargets": 1, "hiddenTargets": 1, "legacyTargets": 1,
    "missingHotspotActions": 1, "noExitCandidates": 1, "themeMissing": 1,
    "themeDuplicate": 1, "visibleLegacy": 1, "removedText": 1,
    "themeReactionMismatch": 1,
    # P2: compare paired roots and native screenshots.
    "selfNavigation": 2, "geometryOverflow": 2, "hiddenButtonText": 2,
    "themeTextMismatch": 2, "themeGeometryMismatch": 2,
    # P3: scope/context may explain these; missing entry targets are P1.
    "externalTargets": 3, "invalidOrUnscopedFlowStart": 3,
}


def compact_sample(sample):
    """Retain useful locators; do not reproduce a large arbitrary payload."""
    keys = (
        "rootId", "root", "nodeId", "path", "sourceVisible", "destinationId",
        "navigation", "target", "targetType", "trigger", "transition", "key",
        "lightId", "darkId", "ids", "id", "name", "missing", "reason", "reasons",
        "matches", "text", "clipId", "clip", "axes", "box", "opacity",
        "reachable", "outgoingRootCount", "light", "dark", "lightCount", "darkCount",
    )
    result = {key: sample[key] for key in keys if key in sample}
    for key, value in result.items():
        if isinstance(value, str) and len(value) > 260:
            result[key] = value[:260] + "…"
    return result


def summarize(data, sample_limit=2, categories=None):
    if isinstance(data, dict) and isinstance(data.get("pluginMessage"), dict):
        data = data["pluginMessage"]
    if not isinstance(data, dict) or not str(data.get("runId", "")).startswith("r4compact-"):
        raise ValueError("Expected a saved compact audit with runId r4compact-…")
    for key in ("counts", "queues", "issueCounts"):
        if not isinstance(data.get(key), dict):
            raise ValueError("Missing compact audit object: " + key)
    notices = []
    final = data.get("schemaVersion") == 1 and bool(data.get("finished")) and isinstance(data.get("issues"), dict)
    if not final:
        notices.append("Not a final compact/finish report; final comparisons and samples may be absent.")
    if data.get("schemaVersion") not in (None, 1):
        notices.append("Unknown schemaVersion; this tool is written for schema 1.")
    counts, queues = {}, {}
    for theme in THEMES:
        counts[theme] = {key: data["counts"].get(theme, {}).get(key) for key in COUNT_FIELDS}
        queues[theme] = {key: data["queues"].get(theme, {}).get(key) for key in ("processed", "queued", "remaining")}
        q = queues[theme]
        if q["remaining"] != 0:
            notices.append(f"queues.{theme}.remaining={q['remaining']!r}: coverage unfinished or unknown.")
        if all(isinstance(q[key], int) for key in q) and q["queued"] - q["processed"] != q["remaining"]:
            notices.append(f"queues.{theme}: processed/queued/remaining are inconsistent.")
    for key in ("incompleteRoots", "legacyUnscanned"):
        if data.get(key) != 0:
            notices.append(f"{key}={data.get(key)!r}: coverage incomplete or unknown.")
    sections = [{key: row.get(key) for key in ("id", "theme", "role", "name", "childCount", "frameCount", "visibleFrameCount", "primaryRootCount")}
                for row in data.get("sections", [])]
    if len(sections) != 4:
        notices.append(f"sections has {len(sections)} entries; final audit should cover all four scoped sections.")
    for row in sections:
        if row["role"] == "review" and row["visibleFrameCount"] != 44:
            notices.append(f"Review section {row['id']} has visibleFrameCount={row['visibleFrameCount']!r}; expected 44.")

    issues = data.get("issues", {})
    category_rows = []
    all_keys = set(data["issueCounts"]) | set(issues)
    for kind in sorted(all_keys, key=lambda name: (PRIORITY.get(name, 2), name)):
        bucket = issues.get(kind, {})
        total = data["issueCounts"].get(kind, bucket.get("count"))
        if kind in data["issueCounts"] and "count" in bucket and total != bucket["count"]:
            notices.append(f"issueCounts.{kind} differs from issues.{kind}.count.")
        samples = bucket.get("samples", [])
        # The source audit includes hidden-source links. Prefer actionable visible
        # sources without pretending this sample split is a population count.
        selected = sorted(samples, key=lambda row: row.get("sourceVisible") is False)[:sample_limit]
        omitted = bucket.get("omitted")
        if isinstance(total, int) and isinstance(omitted, int) and len(samples) + omitted != total:
            notices.append(f"issues.{kind}: retained samples + omitted does not equal count.")
        if categories and kind not in categories:
            selected = []
        root_ids = []
        for sample in selected:
            for node_id in [sample.get("rootId"), sample.get("lightId"), sample.get("darkId"), *sample.get("ids", [])]:
                if isinstance(node_id, str) and node_id not in root_ids:
                    root_ids.append(node_id)
        priority = PRIORITY.get(kind, 2)
        if kind == "invalidOrUnscopedFlowStart" and any(x.get("reason") == "missing target" for x in samples):
            priority = 1
        category_rows.append({"category": kind, "priority": "P" + str(priority), "count": total,
                              "retainedSampleCount": len(samples) if "samples" in bucket else None,
                              "auditOmitted": omitted, "shownSampleCount": len(selected),
                              "samples": [compact_sample(x) for x in selected],
                              "inspectCommands": ["compact/inspect/" + ",".join(root_ids[i:i+4]) for i in range(0, len(root_ids), 4)]})
    return {
        "acceptance": "Not determined. Static candidates require review and separate actual-click evidence.",
        "runId": data["runId"], "status": data.get("status"), "started": data.get("started"),
        "finished": data.get("finished"), "isFinalReport": final,
        "counts": counts, "queues": queues, "incompleteRoots": data.get("incompleteRoots"),
        "legacyUnscanned": data.get("legacyUnscanned"), "sections": sections,
        "comparison": data.get("comparison"), "graph": data.get("graph"),
        "truncation": data.get("truncation"), "notices": notices, "issues": category_rows,
    }


def render(summary):
    lines = [summary["acceptance"], f"Run: {summary['runId']} | final report: {summary['isFinalReport']}",
             f"Status: {summary['status']}"]
    for theme in THEMES:
        lines.append(f"counts.{theme}: " + json.dumps(summary["counts"][theme], ensure_ascii=False))
        lines.append(f"queues.{theme}: " + json.dumps(summary["queues"][theme], ensure_ascii=False))
    for key in ("incompleteRoots", "legacyUnscanned", "sections", "comparison", "graph", "truncation"):
        lines.append(key + ": " + json.dumps(summary[key], ensure_ascii=False))
    for notice in summary["notices"]:
        lines.append("CHECK: " + notice)
    if not summary["issues"]:
        lines.append("No recorded issue categories. This is not acceptance or click verification.")
    for row in summary["issues"]:
        lines.append(f"{row['priority']} issues.{row['category']}: count={row['count']}, retained={row['retainedSampleCount']}, auditOmitted={row['auditOmitted']}, shown={row['shownSampleCount']}")
        lines.extend("  " + json.dumps(sample, ensure_ascii=False) for sample in row["samples"])
        lines.extend("  locate: " + command for command in row["inspectCommands"])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--samples", type=int, default=2, choices=range(0, 11), metavar="0..10")
    parser.add_argument("--category", action="append", help="Show samples only for this category; repeatable. All counts remain visible.")
    parser.add_argument("--json", action="store_true", help="Emit the compact summary as JSON.")
    args = parser.parse_args()
    try:
        data = json.loads(args.path.read_text(encoding="utf-8"))
        result = summarize(data, args.samples, set(args.category or []))
    except (OSError, ValueError, TypeError, AttributeError) as error:
        parser.exit(2, f"Could not summarize saved audit: {error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2) if args.json else render(result))


if __name__ == "__main__":
    main()
