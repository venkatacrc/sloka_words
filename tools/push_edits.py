#!/usr/bin/env python3
"""Push chanting-style verse edits from the app back to both repos.

  1. bhakti:      rewrites the Telugu / Devanagari / IAST lines of each edited verse in its
                  source HTML page, commits those pages and pushes.
  2. sloka_words: merges the edits into verse_edits.json, rebuilds the deck, commits both
                  and pushes.

Only the files this tool writes are committed. Run with --dry-run first to get a JSON
summary of what would change; the app shows it for confirmation.

Usage:
  python3 tools/push_edits.py --repo ~/code/bhakti --edits EDITS.json [--message MSG]
                              [--dry-run] [--no-push]
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_deck  # noqa: E402

ROOT = build_deck.ROOT
DECK = os.path.join('app', 'Sources', 'SlokaWords', 'Resources', 'words.json')
FIELDS = [('te', 'telugu'), ('deva', 'sanskrit'), ('iast', 'english')]

IAST_TO_ITRANS = [
    ('ch', '\0'), ('c', 'ch'), ('\0', 'chh'),
    ('ṝ', 'R^I'), ('ṛ', 'R^i'), ('ḷ', 'L^i'), ('ṅ', '~N'), ('ñ', '~n'),
    ('ṣ', 'Sh'), ('ś', 'sh'), ('ā', 'aa'), ('ī', 'ii'), ('ū', 'uu'),
    ('ṭ', 'T'), ('ḍ', 'D'), ('ṇ', 'N'), ('ṃ', 'M'), ('ṁ', 'M'), ('ḥ', 'H'), ('’', '.a'),
]


def iast_to_itrans(s):
    for a, b in IAST_TO_ITRANS:
        s = s.replace(a, b)
    return s


def lines(text):
    return [l.strip() for l in text.split('\n') if l.strip()]


def git(repo, *args, check=True):
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0')
    r = subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, env=env)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed in {repo}:\n{(r.stderr or r.stdout).strip()}")
    return r.stdout.strip()


def repo_info(repo, files):
    dirty = git(repo, 'status', '--porcelain', '--', *files).splitlines() if files else []
    return {
        'path': repo,
        'branch': git(repo, 'rev-parse', '--abbrev-ref', 'HEAD'),
        'remote': git(repo, 'remote', 'get-url', 'origin', check=False),
        'files': files,
        'other_changes': sorted({l[3:] for l in dirty}),
    }


def joiner(raw):
    if re.search(r'<br\s*/?>\n', raw):
        return '<br>\n'
    if re.search(r'<br\s*/?>', raw):
        return '<br>'
    return ' '


def rewrite_block(text, block, new_fields):
    """Replace the contents of the given divs in the block-th verse of a page."""
    starts = [m.start() for m in build_deck.SCRIPTS_RE.finditer(text)] + [len(text)]
    pos, end = starts[block], starts[block + 1]
    seg = text[pos:end]
    for cls, new_lines in new_fields.items():
        m = re.search(rf'(<div class="{cls}">)(.*?)(</div>)', seg, re.S)
        if not m:
            raise RuntimeError(f'verse block {block} has no <div class="{cls}">')
        body = joiner(m.group(2)).join(html.escape(l, quote=False) for l in new_lines)
        seg = seg[:m.start(2)] + body + seg[m.end(2):]
    return text[:pos] + seg + text[end:]


def default_message(labels):
    shown = ', '.join(labels[:5])
    more = f' and {len(labels) - 5} more' if len(labels) > 5 else ''
    return f'Chanting-style verse edits: {shown}{more}'


def plan(repo, edits):
    sources = json.load(open(os.path.join(ROOT, 'sources.json'), encoding='utf-8'))
    styles = {s['id']: s.get('iast_style') for s in sources}
    _, _, verses, _ = build_deck.build(repo, sources)
    by_id = {v['id']: v for v in verses}

    changed, unchanged, unknown = [], [], []
    for vid in sorted(edits):
        v = by_id.get(vid)
        if not v:
            unknown.append(vid)
            continue
        diff = {}
        for key, _ in FIELDS:
            if key in edits[vid]:
                after = lines(edits[vid][key])
                if after and after != v[key]:
                    diff[key] = {'before': v[key], 'after': after}
        entry = {'id': vid, 'label': v['label'], 'file': v['file'], 'block': v['block'],
                 'itrans': styles.get(v['src']) == 'itrans', 'changes': diff}
        (changed if diff else unchanged).append(entry)
    return changed, unchanged, unknown


def apply_html(repo, changed):
    pages = {}
    for c in changed:
        path = os.path.join(repo, c['file'])
        text = pages.get(path) or open(path, encoding='utf-8').read()
        new_fields = {}
        for key, cls in FIELDS:
            if key in c['changes']:
                after = c['changes'][key]['after']
                if key == 'iast' and c['itrans']:
                    after = [iast_to_itrans(l) for l in after]
                new_fields[cls] = after
        pages[path] = rewrite_block(text, c['block'], new_fields)
    for path, text in pages.items():
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)


def merge_edits(edits):
    path = os.path.join(ROOT, 'verse_edits.json')
    merged = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    merged.update(edits)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(dict(sorted(merged.items())), f, ensure_ascii=False, indent=2)
        f.write('\n')


def commit_and_push(repo, files, message, push, log):
    git(repo, 'add', '--', *files)
    if not git(repo, 'diff', '--cached', '--name-only', '--', *files):
        log.append(f'{os.path.basename(repo)}: nothing to commit')
        return None
    git(repo, 'commit', '-m', message, '--', *files)
    sha = git(repo, 'rev-parse', '--short', 'HEAD')
    log.append(f'{os.path.basename(repo)}: committed {sha} ({len(files)} file(s))')
    if push:
        if git(repo, 'rev-parse', '--abbrev-ref', '@{u}', check=False):
            git(repo, 'push')
        else:
            git(repo, 'push', '-u', 'origin', 'HEAD')
        log.append(f'{os.path.basename(repo)}: pushed to {git(repo, "rev-parse", "--abbrev-ref", "@{u}")}')
    return sha


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--repo', required=True, help='path to the bhakti repo')
    ap.add_argument('--edits', required=True, help="the app's verse_edits.json")
    ap.add_argument('--message', help='commit message (default lists the edited verses)')
    ap.add_argument('--dry-run', action='store_true', help='print what would change and exit')
    ap.add_argument('--no-push', action='store_true', help='commit but do not push')
    args = ap.parse_args()

    result = {'ok': True}
    try:
        repo = os.path.abspath(os.path.expanduser(args.repo))
        edits = json.load(open(os.path.expanduser(args.edits), encoding='utf-8'))
        changed, unchanged, unknown = plan(repo, edits)
        pages = sorted({c['file'] for c in changed})
        message = args.message or default_message([c['label'] for c in changed + unchanged])
        result.update({
            'message': message,
            'verses': changed,
            'unchanged': [c['id'] for c in unchanged],
            'unknown': unknown,
            'bhakti': repo_info(repo, pages),
            'sloka_words': repo_info(ROOT, ['verse_edits.json', DECK]),
        })
        if not args.dry_run:
            known = {k: v for k, v in edits.items() if k not in unknown}
            if not known:
                raise RuntimeError('There are no verse edits to push.')
            log = []
            apply_html(repo, changed)
            if pages:
                commit_and_push(repo, pages, message, not args.no_push, log)
            merge_edits(known)
            build = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'build_deck.py'), '--repo', repo],
                                   capture_output=True, text=True)
            if build.returncode != 0:
                raise RuntimeError(f'build_deck.py failed:\n{build.stderr.strip()}')
            log.append(build.stdout.strip().splitlines()[-2])
            commit_and_push(ROOT, ['verse_edits.json', DECK], message, not args.no_push, log)
            result['log'] = log
            result['deck'] = os.path.join(ROOT, DECK)
    except Exception as e:  # reported to the app as JSON
        result = {**result, 'ok': False, 'error': str(e)}
    json.dump(result, sys.stdout, ensure_ascii=False, indent=1)
    print()
    sys.exit(0 if result['ok'] else 1)


if __name__ == '__main__':
    main()
