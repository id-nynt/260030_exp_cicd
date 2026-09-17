"""Deterministic transformation of the supported pipeline/goal YAML subset.

The parser is deliberately strict. It validates the source configuration before
emitting the workflow model and the project-specific AgentSpeak beliefs.
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


ATOM = re.compile(r"^[a-z_][a-z0-9_]*$")
COMPARISON = re.compile(r"^([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*(==|!=|<=|>=|<|>)\s*([a-z_][a-z0-9_]*|-?[0-9]+(?:\.[0-9]+)?)$")
RECOVERY_IF = re.compile(r"needs\.([a-z_][a-z0-9_]*)\.result\s*==\s*['\"]failure['\"]")
SUPPORTED_STATUS = ["success", "failure", "cancelled", "skipped", "timeout"]
SUPPORTED_PROPERTIES = {"status", "duration", "health", "latency", "error_rate"}


class ModelError(ValueError):
    """Raised for unsupported, malformed, or ambiguous source configuration."""


@dataclass(frozen=True)
class Achievement:
    entity: str
    property: str
    operator: str
    value: str


@dataclass(frozen=True)
class Maintenance:
    entity: str
    property: str
    operator: str
    value: int | float


@dataclass(frozen=True)
class Avoidance:
    entity: str
    required: str


@dataclass(frozen=True)
class Model:
    name: str
    entities: tuple[str, ...]
    dependencies: tuple[tuple[str, str], ...]
    recovery: tuple[tuple[str, str], ...]
    achievements: tuple[Achievement, ...]
    maintenance: tuple[Maintenance, ...]
    avoidance: tuple[Avoidance, ...]
    duration_unit: str
    max_retries: int

    @property
    def final_entity(self) -> str:
        sources = {source for source, _ in self.dependencies}
        targets = {target for _, target in self.dependencies}
        normal = set(self.entities) - {target for _, target in self.recovery}
        sinks = sorted(normal - sources)
        if len(sinks) != 1:
            raise ModelError(f"workflow must have exactly one final normal entity; found {sinks}")
        if targets and sinks[0] not in targets and len(normal) > 1:
            raise ModelError(f"final entity {sinks[0]} is disconnected from dependencies")
        return sinks[0]


def _load(path: Path) -> dict[str, Any]:
    try:
        value = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise ModelError(f"{path}: invalid YAML: {exc}") from exc
    if not isinstance(value, dict):
        raise ModelError(f"{path}: top level must be a mapping")
    return value


def _atom(value: Any, context: str) -> str:
    if not isinstance(value, str) or not ATOM.fullmatch(value):
        raise ModelError(f"{context}: expected lowercase atom, got {value!r}")
    return value


def _list(value: Any, context: str) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return value
    raise ModelError(f"{context}: expected scalar or list")


def _comparison(value: Any, context: str) -> tuple[str, str, str, str]:
    if not isinstance(value, str):
        raise ModelError(f"{context}: expected comparison string")
    match = COMPARISON.fullmatch(value.strip())
    if not match:
        raise ModelError(f"{context}: malformed comparison {value!r}")
    entity, prop, operator, rhs = match.groups()
    return entity, prop, operator, rhs


def parse_pipeline(path: Path) -> tuple[str, tuple[str, ...], tuple[tuple[str, str], ...], tuple[tuple[str, str], ...], int]:
    data = _load(path)
    allowed_root = {"name", "jobs", "execution", "on", True}
    unsupported_root = set(data) - allowed_root
    if unsupported_root:
        raise ModelError(f"{path}: unsupported top-level keys {sorted(map(str, unsupported_root))}")
    jobs = data.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        raise ModelError(f"{path}: jobs must be a non-empty mapping")
    entities = tuple(_atom(name, "pipeline job") for name in jobs)
    entity_set = set(entities)
    dependencies: list[tuple[str, str]] = []
    recovery: list[tuple[str, str]] = []
    recovery_jobs: set[str] = set()
    for entity, config in jobs.items():
        if not isinstance(config, dict):
            raise ModelError(f"job {entity}: expected mapping")
        unsupported_job = set(config) - {"needs", "if", "runs-on", "steps", "timeout-minutes"}
        if unsupported_job:
            raise ModelError(f"job {entity}: unsupported keys {sorted(map(str, unsupported_job))}")
        needs = [_atom(item, f"job {entity}.needs") for item in _list(config.get("needs"), f"job {entity}.needs")]
        unknown = sorted(set(needs) - entity_set)
        if unknown:
            raise ModelError(f"job {entity}: unknown dependency {unknown[0]}")
        condition = config.get("if")
        matches = RECOVERY_IF.findall(condition) if isinstance(condition, str) else []
        if condition is not None and not isinstance(condition, str):
            raise ModelError(f"job {entity}.if: expected string")
        if matches:
            if len(matches) != 1 or len(needs) != 1 or needs[0] != matches[0]:
                raise ModelError(f"job {entity}: recovery condition must identify its single needs target")
            recovery_jobs.add(entity)
            recovery.append((matches[0], entity))
        elif condition is not None and "needs." in condition:
            raise ModelError(f"job {entity}.if: unsupported or ambiguous recovery condition")
        else:
            dependencies.extend((need, entity) for need in needs)
    if len(set(recovery)) != len(recovery):
        raise ModelError("duplicate recovery relationship")
    _check_acyclic(entities, dependencies)
    execution = data.get("execution", {})
    if not isinstance(execution, dict):
        raise ModelError("pipeline.execution: expected mapping")
    retries = execution.get("max_retries")
    if not isinstance(retries, int) or isinstance(retries, bool) or retries < 0:
        raise ModelError("pipeline.execution.max_retries: expected non-negative integer")
    return str(data.get("name", "CI/CD Pipeline")), entities, tuple(dependencies), tuple(recovery), retries


def _check_acyclic(entities: tuple[str, ...], dependencies: list[tuple[str, str]]) -> None:
    graph = {entity: [] for entity in entities}
    for source, target in dependencies:
        graph[source].append(target)
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(node: str) -> None:
        if node in visiting:
            raise ModelError(f"cyclic dependency detected at {node}")
        if node in visited:
            return
        visiting.add(node)
        for child in graph[node]:
            visit(child)
        visiting.remove(node)
        visited.add(node)

    for entity in entities:
        visit(entity)


def parse_goals(path: Path, entities: tuple[str, ...], recovery: tuple[tuple[str, str], ...]) -> tuple[tuple[Achievement, ...], tuple[Maintenance, ...], tuple[tuple[Avoidance, ...], str]]:
    data = _load(path).get("goal")
    if not isinstance(data, dict):
        raise ModelError(f"{path}: goal must be a mapping")
    unsupported_goal = set(data) - {"achieve(A)", "maintain(M)", "avoid(V)", "duration_unit"}
    if unsupported_goal:
        raise ModelError(f"{path}: unsupported goal keys {sorted(map(str, unsupported_goal))}")
    entity_set = set(entities)
    achievements: list[Achievement] = []
    for raw in data.get("achieve(A)", []):
        entity, prop, operator, value = _comparison(raw, "goal.achieve(A)")
        _validate_ref(entity, prop, value, entity_set, "achievement")
        if operator != "==" or prop != "status" or value != "success":
            raise ModelError("achievement supports only entity.status == success")
        achievements.append(Achievement(entity, prop, operator, value))
    maintenance: list[Maintenance] = []
    for raw in data.get("maintain(M)", []):
        entity, prop, operator, value = _comparison(raw, "goal.maintain(M)")
        _validate_ref(entity, prop, value, entity_set, "maintenance")
        if prop != "duration" or operator != "<=" or not re.fullmatch(r"-?[0-9]+", value):
            raise ModelError("maintenance supports only entity.duration <= integer")
        maintenance.append(Maintenance(entity, prop, operator, int(value)))
    duration_unit = data.get("duration_unit", "milliseconds")
    if duration_unit != "milliseconds":
        raise ModelError("goal.duration_unit: only milliseconds is supported")
    avoidance: list[Avoidance] = []
    for index, raw in enumerate(data.get("avoid(V)", [])):
        if not isinstance(raw, dict) or set(raw) != {"condition", "when"}:
            raise ModelError(f"goal.avoid(V)[{index}]: expected condition and when mappings")
        left = _comparison(raw["condition"], f"goal.avoid(V)[{index}].condition")
        right = _comparison(raw["when"], f"goal.avoid(V)[{index}].when")
        le, lp, lo, lv = left
        re_, rp, ro, rv = right
        _validate_ref(le, lp, lv, entity_set, "avoidance condition")
        _validate_ref(re_, rp, rv, entity_set, "avoidance when")
        if (lp, lo, lv) != ("status", "==", "success") or (rp, ro, rv) != ("status", "!=", "success"):
            raise ModelError("avoidance supports success conditioned on a predecessor not succeeding")
        avoidance.append(Avoidance(le, re_))
    for target, recovery_entity in recovery:
        if target not in entity_set or recovery_entity not in entity_set:
            raise ModelError("recovery references unknown entity")
    return tuple(achievements), tuple(maintenance), (tuple(avoidance), duration_unit)


def _validate_ref(entity: str, prop: str, value: str, entities: set[str], context: str) -> None:
    if entity not in entities:
        raise ModelError(f"{context}: unknown entity {entity}")
    if prop not in SUPPORTED_PROPERTIES:
        raise ModelError(f"{context}: unsupported observable property {prop}")
    if prop == "status" and value not in SUPPORTED_STATUS and value != "success":
        raise ModelError(f"{context}: unsupported status value {value}")


def parse_model(pipeline_path: Path, goal_path: Path) -> Model:
    name, entities, dependencies, recovery, retries = parse_pipeline(pipeline_path)
    achievements, maintenance, (avoidance, duration_unit) = parse_goals(goal_path, entities, recovery)
    if not achievements:
        raise ModelError("goal.achieve(A): at least one achievement is required")
    return Model(name, entities, dependencies, recovery, achievements, maintenance, avoidance, duration_unit, retries)


def workflow_yaml(model: Model) -> str:
    observables: dict[str, Any] = {"status": {"values": SUPPORTED_STATUS}, "duration": {"value": "time"}}
    for achievement in model.achievements:
        if achievement.property == "status":
            observables.setdefault("status", {"values": SUPPORTED_STATUS})
    document: dict[str, Any] = {
        "workflow": {
            "name": model.name,
            "entities(E)": list(model.entities),
            "dependencies(D)": [{"from": source, "to": target} for source, target in model.dependencies],
            "observable_properties(O)": observables,
            "recovery(R)": [{"from": source, "to": target} for source, target in model.recovery],
        },
        "execution": {
            "max_retries": model.max_retries,
            "observation_schema": {
                "status": SUPPORTED_STATUS,
                "duration_unit": model.duration_unit,
                "required_for": sorted({item.entity for item in model.maintenance}),
                "attempt_id_required": False,
            },
        },
        "recovery_policy": {
            recovery_entity: {
                "run_after": f"{source}_failure",
                "retryable": False,
                "terminal_on_success": "recovered",
                "terminal_on_failure": "failed",
            }
            for source, recovery_entity in model.recovery
        },
    }
    return "# Generated from 01_pipeline.yaml and 02_goal.yaml\n" + yaml.safe_dump(document, sort_keys=False, default_flow_style=False)


def project_beliefs(model: Model) -> str:
    lines = ["// Generated from 03_workflow_model.yaml; do not edit.", ""]
    lines += [f"entity({entity})." for entity in model.entities]
    lines += [f"recovery_entity({target})." for _, target in model.recovery]
    lines += [""]
    recovery_entities = {target for _, target in model.recovery}
    for entity in model.entities:
        if entity in recovery_entities:
            continue
        requirements = [source for source, target in model.dependencies if target == entity]
        lines.append(f"depends({entity}, [{', '.join(requirements)}]).")
    lines += [""]
    lines += [f"recovery({source}, {target})." for source, target in model.recovery]
    lines.append(f"final_phase({model.final_entity}).")
    lines += [""]
    lines += [f"achievement({item.entity}, {item.value})." for item in model.achievements]
    lines += [f"max_duration({item.entity}, {item.value})." for item in model.maintenance]
    lines += [f"avoid_missing({item.entity}, {item.required})." for item in model.avoidance]
    lines += ["", f"duration_unit({model.duration_unit}).", f"max_retries({model.max_retries}).", ""]
    lines += ["// Controller-derived attempt counters."]
    lines += [f"attempt_count({entity}, 0)." for entity in model.entities]
    return "\n".join(lines) + "\n"


def transform(pipeline: Path, goals: Path, workflow: Path, beliefs: Path,
              agent: Path | None = None, generic: Path | None = None) -> Model:
    model = parse_model(pipeline, goals)
    workflow.write_text(workflow_yaml(model), encoding="utf-8", newline="\n")
    generated_beliefs = project_beliefs(model)
    beliefs.write_text(generated_beliefs, encoding="utf-8", newline="\n")
    if agent is not None:
        if generic is None:
            raise ModelError("agent output requires a generic reasoning template")
        agent.write_text(generated_beliefs + "\n" + generic.read_text(encoding="utf-8"),
                         encoding="utf-8", newline="\n")
    return model


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pipeline", type=Path, default=Path("01_pipeline.yaml"))
    parser.add_argument("--goals", type=Path, default=Path("02_goal.yaml"))
    parser.add_argument("--workflow", type=Path, default=Path("03_workflow_model.yaml"))
    parser.add_argument("--beliefs", type=Path, default=Path("bdi_project.asl"))
    parser.add_argument("--agent", type=Path, default=Path("bdi_agent.asl"))
    parser.add_argument("--generic", type=Path, default=Path("bdi_generic.asl"))
    args = parser.parse_args()
    try:
        model = transform(args.pipeline, args.goals, args.workflow, args.beliefs,
                           args.agent, args.generic)
    except ModelError as exc:
        parser.error(str(exc))
    print(f"generated {args.workflow} and {args.beliefs} ({len(model.entities)} entities)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
