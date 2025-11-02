#!/usr/bin/env python3
"""Helper utilities for the omarchy-syncd shell rewrite.

Reads bundle metadata and emits normalized configuration data so the surrounding
shell scripts can avoid fragile ad-hoc parsing.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore
except ModuleNotFoundError:  # pragma: no cover - fallback for older interpreters
    import tomli as tomllib  # type: ignore


def load_manifest(root: Path) -> dict:
    bundles_path = root / "data" / "bundles.toml"
    with bundles_path.open("rb") as fh:
        return tomllib.load(fh)


def command_manifest(args: argparse.Namespace) -> int:
    manifest = load_manifest(Path(args.root))
    json.dump(manifest, sys.stdout)
    return 0


def normalize_strings(values: list[str]) -> list[str]:
    unique = {value.strip() for value in values if value.strip()}
    return sorted(unique)


def prune_explicit_paths(bundles: list[str], paths: list[str], manifest: dict) -> list[str]:
    if not bundles:
        return paths
    bundle_paths = set()
    for bundle in manifest.get("bundle", []):
        if bundle["id"] in bundles:
            bundle_paths.update(bundle["paths"])
    return [path for path in paths if path not in bundle_paths]


def command_write(args: argparse.Namespace) -> int:
    root = Path(args.root)
    manifest = load_manifest(root)
    defaults = manifest.get("defaults", {}).get("bundle_ids", [])
    bundle_ids = defaults if args.include_defaults else []
    bundle_ids.extend(args.bundle or [])
    bundle_ids = normalize_strings(bundle_ids)

    known_ids = {bundle["id"] for bundle in manifest.get("bundle", [])}
    unknown = sorted(set(bundle_ids) - known_ids)
    if unknown:
        print(f"error: unknown bundle ids: {', '.join(unknown)}", file=sys.stderr)
        return 1

    explicit_paths = normalize_strings(args.path or [])
    explicit_paths = prune_explicit_paths(bundle_ids, explicit_paths, manifest)

    if not bundle_ids and not explicit_paths:
        print(
            "error: no bundles or explicit paths selected; "
            "provide --bundle, --include-defaults, or --path.",
            file=sys.stderr,
        )
        return 1

    repo_url = args.repo_url.strip()
    if not repo_url:
        print("error: --repo-url must not be empty", file=sys.stderr)
        return 1

    branch = args.branch.strip() or "master"

    def q(value: str) -> str:
        return json.dumps(value)

    def emit_array(values: list[str]) -> str:
        body = ",\n".join(f"  {q(v)}" for v in values)
        return "[\n" + body + ("\n" if values else "") + "]"

    toml_lines = [
        "[repo]",
        f"url = {q(repo_url)}",
        f"branch = {q(branch)}",
        "",
        "[files]",
        f"paths = {emit_array(explicit_paths)}",
        f"bundles = {emit_array(bundle_ids)}",
        "",
    ]
    sys.stdout.write("\n".join(toml_lines))
    return 0


def resolve_bundle_paths(bundle_ids: list[str], manifest: dict) -> list[str]:
    id_set = set(bundle_ids)
    paths = []
    for bundle in manifest.get("bundle", []):
        if bundle["id"] in id_set:
            paths.extend(bundle.get("paths", []))
    return paths


def command_read_config(args: argparse.Namespace) -> int:
    root = Path(args.root)
    manifest = load_manifest(root)
    config_path = Path(args.config_path)
    with config_path.open("rb") as fh:
        config = tomllib.load(fh)

    repo = config.get("repo", {})
    files = config.get("files", {})

    repo_url = repo.get("url", "").strip()
    branch = repo.get("branch", "master").strip() or "master"

    bundles = normalize_strings(files.get("bundles", []))
    explicit_paths = normalize_strings(files.get("paths", []))

    known_ids = {bundle["id"] for bundle in manifest.get("bundle", [])}
    unknown = sorted(set(bundles) - known_ids)
    if unknown:
        print(f"error: unknown bundle ids in config: {', '.join(unknown)}", file=sys.stderr)
        return 1

    bundle_paths = normalize_strings(resolve_bundle_paths(bundles, manifest))
    resolved_paths = normalize_strings(explicit_paths + bundle_paths)

    result = {
        "repo": {"url": repo_url, "branch": branch},
        "bundles": bundles,
        "explicit_paths": explicit_paths,
        "resolved_paths": resolved_paths,
        "bundle_options": manifest.get("bundle", []),
        "default_bundle_ids": manifest.get("defaults", {}).get("bundle_ids", []),
    }

    if args.field:
        data = result
        for part in args.field.split("."):
            if isinstance(data, dict):
                data = data.get(part)
            else:
                data = None
                break
        if isinstance(data, list):
            for item in data:
                print(item)
        elif isinstance(data, dict):
            json.dump(data, sys.stdout)
        elif data is None:
            return 0
        else:
            print(data)
        return 0

    json.dump(result, sys.stdout)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, help="Project root directory")
    sub = parser.add_subparsers(dest="command", required=True)

    manifest = sub.add_parser("manifest", help="Emit bundle manifest as JSON")
    manifest.set_defaults(func=command_manifest)

    write = sub.add_parser("write", help="Generate TOML configuration")
    write.add_argument("--repo-url", required=True)
    write.add_argument("--branch", default="master")
    write.add_argument("--bundle", action="append")
    write.add_argument("--path", action="append")
    write.add_argument("--include-defaults", action="store_true")
    write.set_defaults(func=command_write)

    read_config = sub.add_parser("read-config", help="Read existing configuration and emit JSON")
    read_config.add_argument("--config-path", required=True)
    read_config.add_argument("--field", help="Emit only the requested field")
    read_config.set_defaults(func=command_read_config)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
