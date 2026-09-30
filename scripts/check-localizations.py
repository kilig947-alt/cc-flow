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


def main():
    errors = []
    catalogs = {}
    for language in ['en', 'zh-Hans']:
        path = ROOT / f'CCFlow/Resources/{language}.lproj/Localizable.strings'
        entries = ENTRY.findall(path.read_text())
        for key, count in Counter(key for key, _ in entries).items():
            if count > 1:
                errors.append(f'{language}: duplicate key: {key}')
        catalogs[language] = dict(entries)
    english, chinese = catalogs['en'], catalogs['zh-Hans']
    for key in english.keys() ^ chinese.keys():
        errors.append(f'Catalog key mismatch: {key}')
    for key, value in english.items():
        if HAN.search(value):
            errors.append(f'English value still contains Chinese: {key}')
        if sorted(PLACEHOLDER.findall(key)) != sorted(PLACEHOLDER.findall(value)):
            errors.append(f'Format argument mismatch: {key}')
    for path in sorted((ROOT / 'CCFlow/UI').rglob('*.swift')):
        source = path.read_text()
        for offset, key in strings(source):
            if not HAN.search(key) or key in english:
                continue
            if key.startswith(('[ccFlowHint]', '[MineradioLogin]')):
                continue
            line = source.count('\n', 0, offset) + 1
            errors.append(f'{path.relative_to(ROOT)}:{line}: missing translation: {key}')
    if errors:
        print('\n'.join(errors))
        return 1
    print(f'Localization check passed: {len(english)} matching keys; no missing Chinese UI literals or format mismatches.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
