#!/usr/bin/env bash
set -euo pipefail

# Verify the staged change record before a commit. This script is intentionally
# dependency-free so it can run locally, in CI, or from .githooks/pre-commit.

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

failures=0
fail() {
    printf 'change-documentation: ERROR: %s\n' "$1" >&2
    failures=$((failures + 1))
}

staged_files="$(git diff --cached --name-only --diff-filter=ACMRD)"
if [[ -z "$staged_files" ]]; then
    printf '%s\n' 'change-documentation: no staged changes; nothing to verify.'
    exit 0
fi

if ! git diff --cached --check; then
    fail 'staged diff contains whitespace errors.'
fi

# Documentation-only edits do not need a new historical record. Source, tests,
# project configuration, scripts, workflows, and current specs do.
requires_record=0
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    case "$path" in
        AGENTS.md|README.md|CONTRIBUTING.md|docs/*|spec_changes/*)
            ;;
        specs/*|voiceflow/*|voiceflowTests/*|scripts/*|.github/*|*.xcodeproj/*|Package.swift|Package.resolved)
            requires_record=1
            ;;
        *)
            # Treat unknown tracked files conservatively as implementation changes.
            requires_record=1
            ;;
    esac
done <<< "$staged_files"

spec_change_files="$(printf '%s\n' "$staged_files" | grep -E '^spec_changes/[0-9]{3}_[^/]+\.md$' || true)"
if [[ "$requires_record" -eq 1 && -z "$spec_change_files" ]]; then
    fail 'implementation or workflow files are staged without a numbered spec_changes record.'
fi

if [[ -n "$spec_change_files" ]]; then
    highest=0
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        number="${path##*/}"
        number="${number%%_*}"
        (( 10#$number > highest )) && highest=$((10#$number))
    done < <(git ls-tree -r --name-only HEAD -- spec_changes | grep -E '^spec_changes/[0-9]{3}_[^/]+\.md$' || true)
    expected=$((highest + 1))
    expected_prefix="spec_changes/$(printf '%03d' "$expected")_"
    if ! printf '%s\n' "$spec_change_files" | grep -q "^${expected_prefix}"; then
        fail "the next staged spec_changes record should begin with ${expected_prefix}."
    fi

    required_sections=(
        '## Date'
        '## Status'
        '## Reason'
        '## Scope'
        '## Implementation'
        '## Behavior and compatibility'
        '## Tests and verification'
        '## Documentation updated'
        '## Known limitations or follow-up'
    )

    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        [[ -f "$path" ]] || { fail "staged change record is not available at $path"; continue; }
        if ! grep -qE '^# Change [0-9]{3}:' "$path"; then
            fail "$path must start with '# Change NNN: <short title>'."
        fi
        for section in "${required_sections[@]}"; do
            if ! grep -qF "$section" "$path"; then
                fail "$path is missing the required section '$section'."
            fi
        done
    done <<< "$spec_change_files"
fi

# Inspect application, test, specification, and CI changes for semantic
# patterns. Exclude this policy/checker text so it cannot self-trigger.
change_diff="$(git diff --cached -- voiceflow voiceflowTests specs .github '*.xcodeproj' Package.swift Package.resolved 2>/dev/null || true)"

if [[ "$change_diff" =~ [Ff]eature[[:space:]-_]flag|[Rr]ollout|[Kk]ill[[:space:]-_]switch|[Aa]lwaysUseAI|[Ee]nabledKey|[Ff]lag[[:space:]=] ]]; then
    if [[ -z "$spec_change_files" ]]; then
        fail 'feature-flag changes require a spec_changes record with a ## Feature flags section.'
    else
        while IFS= read -r path; do
            [[ -z "$path" ]] && continue
            grep -qF '## Feature flags' "$path" || fail "$path must document feature flags with a ## Feature flags section."
        done <<< "$spec_change_files"
    fi
fi

if [[ "$change_diff" =~ [Mm]igrat|[Ll]egacy|[Ss]chema[[:space:]-_]*version|[Bb]ackfill|[Cc]ompatibility[[:space:]-_]*window ]]; then
    if [[ -z "$spec_change_files" ]]; then
        fail 'migration or compatibility changes require a spec_changes record with a ## Migration section.'
    else
        while IFS= read -r path; do
            [[ -z "$path" ]] && continue
            grep -qF '## Migration' "$path" || fail "$path must document migrations with a ## Migration section."
        done <<< "$spec_change_files"
    fi
fi

if [[ "$failures" -gt 0 ]]; then
    printf 'change-documentation: %d check(s) failed. See docs/change-documentation.md.\n' "$failures" >&2
    exit 1
fi

printf '%s\n' 'change-documentation: staged change satisfies the documentation workflow.'
