#!/usr/bin/env python3
"""Convert success `jsonStruct(20xx, .{ .code = 0, ... })` sites to ctx.ok / ctx.okValue.

Strategy:
- For each file, scan text and find each occurrence of
  `try ctx.jsonStruct(20xx, .{ ... });` where `.code = 0`.
- The data field may span multiple lines and contain nested braces.
- Extract the `.data = EXPR` expression, then replace the whole match with
  `try ctx.ok("null");` or `try ctx.okValue(EXPR);`.

Leaves `code != 0`, 4xx/5xx status, and `sendPaged` alone.
"""
import re
import sys
from pathlib import Path


# Detect `try ctx.jsonStruct(20xx, .{`
START_RE = re.compile(r'try ctx\.jsonStruct\(2\d{2},\s*\.\{')

# After matching the start, capture the status and the indent.
def find_start(text: str, pos: int):
    """Return (start, end, status, indent) or None."""
    m = START_RE.match(text, pos)
    if not m:
        return None
    # status is inside `try ctx.jsonStruct(<status>, .{`
    before = text[:m.start()]
    line_start = before.rfind('\n') + 1
    indent = before[line_start:m.start()]
    # Find status (between `(` and `,`)
    status_match = re.match(r'try ctx\.jsonStruct\((\d+),', text[m.start():])
    if not status_match:
        return None
    status = int(status_match.group(1))
    # Now advance past the `.{` opening. The opening brace is at position m.end() - 1.
    # (i.e., last char of `.\{` is the `{`.) We need to find its matching `}`.
    open_brace_idx = m.end() - 1
    close_brace_idx = find_matching_close(text, open_brace_idx)
    if close_brace_idx == -1:
        return None
    return m.start(), close_brace_idx + 1, status, indent


def find_matching_close(text: str, open_idx: int) -> int:
    """Given `{` at open_idx, return the index of matching `}`, or -1."""
    assert text[open_idx] == '{'
    depth = 0
    i = open_idx
    in_str = False
    str_char = ''
    escape = False
    while i < len(text):
        ch = text[i]
        if in_str:
            if escape:
                escape = False
            elif ch == '\\':
                escape = True
            elif ch == str_char:
                in_str = False
            i += 1
            continue
        if ch in '"\'`':
            in_str = True
            str_char = ch
            i += 1
            continue
        if ch == '/' and i + 1 < len(text):
            nxt = text[i + 1]
            if nxt == '/':
                # line comment — skip to end of line
                nl = text.find('\n', i)
                i = nl + 1 if nl != -1 else len(text)
                continue
            if nxt == '*':
                ed = text.find('*/', i + 2)
                i = ed + 2 if ed != -1 else len(text)
                continue
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def parse_fields(text: str, open_idx: int, close_idx: int) -> dict:
    """Parse `key = value` pairs at top-level depth between open and close."""
    # Walk from open_idx + 1, tracking depth-1 nestedness.
    fields = {}
    i = open_idx + 1
    n = close_idx
    while i < n:
        # skip whitespace
        while i < n and text[i] in ' \t\r\n':
            i += 1
        if i >= n:
            break
        # find `.key = value`
        m = re.match(r'\.([A-Za-z_]\w*)\s*=\s*', text[i:])
        if not m:
            break
        key = m.group(1)
        val_start = i + m.end()
        # walk value: stop at top-level `,` or end of payload
        val_end = walk_value(text, val_start, n)
        value = text[val_start:val_end].rstrip()
        fields[key] = value
        i = val_end
        # skip comma
        while i < n and text[i] in ' \t\r\n':
            i += 1
        if i < n and text[i] == ',':
            i += 1
    return fields


def walk_value(text: str, start: int, end: int) -> int:
    """Walk a top-level value starting at `start`, return end index (at `,` or `}`).

    `start` is at depth 1 inside the payload. Stop when depth returns to 1
    (after possibly going deeper) AND the next char is `,` or `}` — or
    equivalently stop at the first top-level `,` or `}`.
    """
    depth = 1
    i = start
    in_str = False
    str_char = ''
    escape = False
    while i < end:
        ch = text[i]
        if in_str:
            if escape:
                escape = False
            elif ch == '\\':
                escape = True
            elif ch == str_char:
                in_str = False
            i += 1
            continue
        if ch in '"\'`':
            in_str = True
            str_char = ch
            i += 1
            continue
        if ch == '/' and i + 1 < end:
            nxt = text[i + 1]
            if nxt == '/':
                nl = text.find('\n', i)
                i = nl + 1 if nl != -1 else end
                continue
            if nxt == '*':
                ed = text.find('*/', i + 2)
                i = ed + 2 if ed != -1 else end
                continue
        if ch in '{[(':
            depth += 1
        elif ch in '}])':
            depth -= 1
            if depth == 0:
                return i
        elif ch == ',' and depth == 1:
            return i
        i += 1
    return end


def find_close_after(text: str, start: int) -> int:
    """Find index of `});` matching the `try ctx.jsonStruct(<status>, .{` open.
    `start` is index just after the open `{` of the payload.
    """
    # We already know the matching `}`. Now find the next `)` and `;` after it.
    # Use the open_idx + matching close logic. But we need the open_idx.
    return -1


def transform_text(text: str) -> tuple[str, int, list[str]]:
    """Return (new_text, count, warnings)."""
    out: list[str] = []
    pos = 0
    count = 0
    warnings: list[str] = []
    while pos < len(text):
        m = START_RE.search(text, pos)
        if not m:
            out.append(text[pos:])
            break
        # Append everything up to this match
        out.append(text[pos:m.start()])
        # Get status and indent
        status_match = re.match(r'try ctx\.jsonStruct\((\d+),', text[m.start():])
        status = int(status_match.group(1))
        line_start = text.rfind('\n', 0, m.start()) + 1
        indent = text[line_start:m.start()]

        # Open brace is at m.end() - 1 (last char of `.\{`)
        open_idx = m.end() - 1
        close_idx = find_matching_close(text, open_idx)
        if close_idx == -1:
            warnings.append(f'pos {m.start()}: unbalanced braces')
            out.append(text[m.start():m.end()])
            pos = m.end()
            continue

        # Find `});` after close_idx
        j = close_idx + 1
        while j < len(text) and text[j] in ' \t\r\n':
            j += 1
        if j >= len(text) or text[j] != ')':
            warnings.append(f'pos {m.start()}: expected `)` after close brace')
            out.append(text[m.start():j])
            pos = j
            continue
        j += 1
        while j < len(text) and text[j] in ' \t\r\n':
            j += 1
        if j >= len(text) or text[j] != ';':
            warnings.append(f'pos {m.start()}: expected `;` after `)`')
            out.append(text[m.start():j])
            pos = j
            continue
        end_idx = j + 1

        # Parse fields between open_idx and close_idx
        fields = parse_fields(text, open_idx, close_idx)
        code = fields.get('code', '').strip()
        data_expr = fields.get('data', '').strip()
        if code != '0':
            # Not a success site; skip
            out.append(text[m.start():end_idx])
            pos = end_idx
            continue

        # Build replacement — NO indent here, because `text[pos:m.start()]`
        # already includes the line's leading whitespace.
        if data_expr == 'null':
            replacement = f'try ctx.ok("null");'
        else:
            replacement = f'try ctx.okValue({data_expr});'

        # Preserve trailing newline if there is one in the source
        if end_idx < len(text) and text[end_idx] == '\n':
            replacement += '\n'
            end_idx += 1
        elif end_idx < len(text) and text[end_idx] == '\r':
            replacement += '\r'
            end_idx += 1
            if end_idx < len(text) and text[end_idx] == '\n':
                replacement += '\n'
                end_idx += 1

        out.append(replacement)
        pos = end_idx
        count += 1

    return ''.join(out), count, warnings


def transform_file(path: Path) -> tuple[int, list[str]]:
    src = path.read_text()
    new_src, count, warnings = transform_text(src)
    if new_src != src:
        path.write_text(new_src)
    return count, warnings


def main(argv: list[str]) -> int:
    if not argv:
        print('usage: envelope_migrate.py <file> [...]', file=sys.stderr)
        return 2
    total = 0
    all_warnings: list[str] = []
    for arg in argv:
        p = Path(arg)
        c, w = transform_file(p)
        total += c
        all_warnings.extend(w)
        if c:
            print(f'{p}: {c}')
    print(f'TOTAL: {total}')
    if all_warnings:
        print('WARNINGS:', file=sys.stderr)
        for w in all_warnings:
            print(f'  {w}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))