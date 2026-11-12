#!/usr/bin/env python3
"""Wrap every user-visible string literal inside log_msg()/floater() calls in tr().

Rules:
- top-level literals in the call's argument list get wrapped
- literals inside [] (dict/index lookups like sk["name"]) are NOT wrapped
- inside {} dict literals only VALUE-position strings (prev sig char ':') wrap
- literals already inside tr() are skipped
- emits wrapped files + keys.txt of every wrapped literal
"""
import re, sys, os

VERBS = ("log_msg(", "floater(")
keys = []

def scan(line, start):
    """Return (new_line, next_index) wrapping literals in the call at `start`."""
    i = start
    out = line[:i]
    depth = 0            # paren depth relative to call
    stack = []           # '[', '{', or 's' for nested call parens we treat as neutral
    n = len(line)
    prev_sig = ''        # previous significant char (for ':'-value detection)
    while i < n:
        c = line[i]
        if c == '"':
            # parse the string token
            j = i + 1
            while j < n:
                if line[j] == '\\':
                    j += 2
                    continue
                if line[j] == '"':
                    break
                j += 1
            tok = line[i:j + 1]
            wrap = False
            if depth == 0 and not stack:
                wrap = True                       # top-level arg literal
            elif stack and stack[-1] == '{' and prev_sig == ':':
                wrap = True                       # dict value position
            if wrap and not out.rstrip().endswith('tr('):
                lit = tok[1:-1]
                keys.append(lit)
                out += 'tr(' + tok + ')'
            else:
                out += tok
            prev_sig = 'x'
            i = j + 1
            continue
        if c == '(':
            depth += 1
            stack.append('(')
        elif c == ')':
            if depth == 0 and not stack:
                out += c
                return out + line[i + 1:], i + 1
            if stack and stack[-1] == '(':
                stack.pop()
            depth -= 1
        elif c == '[':
            stack.append('[')
        elif c == ']':
            if stack and stack[-1] == '[':
                stack.pop()
        elif c == '{':
            stack.append('{')
        elif c == '}':
            if stack and stack[-1] == '{':
                stack.pop()
        if not c.isspace():
            prev_sig = c
        out += c
        i += 1
    return out + line[i:], i

def process(path):
    src = open(path).read()
    lines = src.split('\n')
    changed = False
    for li, line in enumerate(lines):
        for v in VERBS:
            idx = 0
            while True:
                k = line.find(v, idx)
                if k < 0:
                    break
                # already inside tr( ?  log_msg( tr( ... ) )
                line, end = scan(line, k + len(v))
                idx = end
        lines[li] = line
    new = '\n'.join(lines)
    if new != src:
        open(path, 'w').write(new)
        changed = True
    return changed

def main():
    files = [os.path.join('src', f) for f in os.listdir('src') if f.endswith('.gd')]
    files += [os.path.join('src/data', f) for f in os.listdir('src/data') if f.endswith('.gd')]
    for f in files:
        if process(f):
            print('wrapped:', f)
    seen = set()
    uniq = [k for k in keys if not (k in seen or seen.add(k))]
    with open('/tmp/plg_i18n_keys.txt', 'w') as fh:
        fh.write('\n'.join(uniq) + '\n')
    print('keys:', len(uniq))

main()
