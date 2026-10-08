#!/usr/bin/env python3
"""Check shipped UI localization coverage without changing source or resources.

Run: python3 scripts/check-localizations.py
Prompts, regex payloads, comments and diagnostic logs are not UI translations.
"""
from collections import Counter
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
HAN = re.compile(r"[\u4e00-\u9fff]")
ENTRY = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";', re.M)
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|u|@|(?:\.\d+)?f)")


def string_end(source, start):
    cursor = start + 1
    while cursor < len(source):
        if source.startswith('\\(', cursor):
            depth = 1
            cursor += 2
            while cursor < len(source) and depth:
                if source[cursor] == '"':
                    cursor = string_end(source, cursor)
                elif source[cursor] == '(':
                    depth += 1
                    cursor += 1
                elif source[cursor] == ')':
                    depth -= 1
                    cursor += 1
                else:
                    cursor += 1
        elif source[cursor] == '\\':
            cursor += 2
        elif source[cursor] == '"':
            return cursor + 1
        else:
            cursor += 1
    return cursor


def strings(source):
    cursor = 0
    while cursor < len(source):
        if source.startswith('//', cursor):
            end = source.find('\n', cursor)
            cursor = len(source) if end < 0 else end
        elif source.startswith('/*', cursor):
            end = source.find('*/', cursor + 2)
            cursor = len(source) if end < 0 else end + 2
        elif source.startswith('"""', cursor):
            # Multiline literals in these views are generation prompts, not labels.
            end = source.find('"""', cursor + 3)
            cursor = len(source) if end < 0 else end + 3
        elif source[cursor] == '"':
            end = string_end(source, cursor)
            # Raw literals hold regular-expression payloads.
            if cursor == 0 or source[cursor - 1] != '#':
                yield cursor, source[cursor + 1:end - 1]
            cursor = end
        else:
            cursor += 1


# Inspect localization entry points rather than treating all Chinese data as UI.
# User-editable presets, protocol payloads and parser fixtures may contain Chinese.
LOCALIZED_CALL = re.compile(
    r'(?:AppLocalization\.(?:string|format|runtimeString|runtimeFormat)\(\s*'
    r'|Text\(appLocalized:\s*'
    r'|\b(?:Text|Button|Label|Toggle|Picker|Section|GroupBox|Menu|TextField|SecureField|ContentUnavailableView)\(\s*'
    r'|\.(?:help|alert|confirmationDialog|navigationTitle|accessibilityLabel|accessibilityHint)\(\s*)$'
)
# These dotted strings are protocol names / SF Symbols / view identifiers, not UI keys.
DATA_IDENTIFIERS = {
    "session.start", "session.idle", "music.note", "music.note.tv", "music.mic",
    "clipboard.read", "clipboard.write", "island.hint.show", "island.hint.clear",
    "island.presentation", "calendar.badge.exclamationmark", "calendar.badge.clock",
    "settings.root", "settings.window",
}
STABLE_KEY = re.compile(r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+')


def source_errors(source, catalog, namespaces):
    errors = []
    for offset, text in strings(source):
        before = source[max(0, offset - 180):offset]
        localized = LOCALIZED_CALL.search(before)
        stable_reference = STABLE_KEY.fullmatch(text) and (localized or text.split('.', 1)[0] in namespaces)
        if stable_reference and text not in catalog and (localized or text not in DATA_IDENTIFIERS):
            message = f'unknown localization key: {text}'
        elif localized and HAN.search(text):
            message = f'localized UI text must use a stable key: {text}'
        else:
            continue
        errors.append((source.count('\n', 0, offset) + 1, message))
    return errors


def main():
    errors = []
    catalogs = {}
    for language in ['en', 'zh-Hans']:
        path = ROOT / f'CCFlow/Resources/{language}.lproj/Localizable.strings'
        entries = ENTRY.findall(path.read_text())
        for key, count in Counter(key for key, _ in entries).items():
            if count > 1:
                errors.append(f'{language}: duplicate key: {key}')
        for key, _ in entries:
            if not re.fullmatch(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+", key):
                errors.append(f"{language}: expected a stable localization key: {key}")
        catalogs[language] = dict(entries)
    english, chinese = catalogs['en'], catalogs['zh-Hans']
    for key in english.keys() ^ chinese.keys():
        errors.append(f'Catalog key mismatch: {key}')
    for key, value in english.items():
        if HAN.search(value):
            errors.append(f'English value still contains Chinese: {key}')
        if sorted(PLACEHOLDER.findall(chinese.get(key, ""))) != sorted(PLACEHOLDER.findall(value)):
            errors.append(f'Format argument mismatch: {key}')
    namespaces = {key.split(".", 1)[0] for key in english}
    for path in sorted((ROOT / 'CCFlow').rglob('*.swift')):
        source = path.read_text()
        errors.extend(f'{path.relative_to(ROOT)}:{line}: {message}'
                      for line, message in source_errors(source, english, namespaces))
    if errors:
        print('\n'.join(errors))
        return 1
    print(f'Localization check passed: {len(english)} matching keys; stable keys and format arguments validated.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
