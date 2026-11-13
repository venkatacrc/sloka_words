#!/usr/bin/env python3
"""Check and bundle the Vishnu Sahasranamam word analysis.

Samsaadhanii has no analysis of the Sahasranamam, so this one is drafted in this repo, one
file per verse in analysis/vs/<slug>.tsv, in the same format as Samsaadhanii's Gita files
(see tools/gita_analysis_index.py). The apps read it from vs_analysis.json.

  python3 tools/vs_analysis.py                    # check every file, then write vs_analysis.json
  python3 tools/vs_analysis.py --check SLUG ...   # check some files only
  python3 tools/vs_analysis.py --prepare OUT.json # verse texts and slugs, for drafting

Columns: index, word, poem, sandhied_word, morph_in_context, kaaraka_sambandha,
english_meaning. The check rebuilds each verse from the sandhied_word column, so every
word of the verse must be there, spelled as in the deck.
"""
import argparse
import glob
import json
import os
import re
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gita_analysis_index import ALIASES, RELATIONS, TAGS, relation_key  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECK = os.path.join(ROOT, 'app', 'Sources', 'SlokaWords', 'Resources', 'words.json')
SRC_DIR = os.path.join(ROOT, 'analysis', 'vs')
OUTPUTS = [
    os.path.join(ROOT, 'web', 'vs_analysis.json'),
    os.path.join(ROOT, 'app', 'Sources', 'SlokaWords', 'Resources', 'vs_analysis.json'),
]
HEADER = ['index', 'word', 'poem', 'sandhied_word', 'morph_in_context', 'kaaraka_sambandha', 'english_meaning']
CREDIT = ('Draft word analysis made for Sloka Words in the style of Samsaadhanii '
          '(University of Hyderabad); it is not from Samsaadhanii and may contain mistakes.')

KNOWN_RELATIONS = {relation_key(sa) for sa, _, _, _ in RELATIONS}
RELATION_KIND = {relation_key(sa): kind for sa, kind, _, _ in RELATIONS}
ALIAS_KEYS = {relation_key(k): relation_key(v) for k, v in ALIASES.items()}
GANAS = {t for t in TAGS if t.endswith('ादिः')}
ID_RE = re.compile(r'^\d+(\.\d+){1,2}$')
MORPH_RE = re.compile(r'^([^{]+)\{(.*)\}$')
DROP = re.compile(r'[\s\u200b\u200c\u200d।॥०-९0-9\-,.;:!?\'"()\[\]]')


def slug(verse_id):
    _, group, label = verse_id.split(':', 2)
    if group == 'stotram' and label.isdigit():
        return f'stotram_{int(label):03d}'
    plain = unicodedata.normalize('NFKD', label).encode('ascii', 'ignore').decode().lower()
    return f'{group}_' + re.sub(r'[^a-z0-9]+', '_', plain).strip('_')


def deck_verses():
    with open(DECK, encoding='utf-8') as f:
        return [v for v in json.load(f)['verses'] if v['src'] == 'vs']


def verse_text(verse):
    return DROP.sub('', unicodedata.normalize('NFC', ''.join(verse['deva'])))


def canonical_relation(name):
    key = relation_key(name)
    return ALIAS_KEYS.get(key, key)


def morph_tags(morph):
    """Tags outside and inside the derivation brackets of a morph string."""
    s = morph.strip()
    if s.startswith('(') and s.endswith(')'):
        s = s[1:-1]
    m = MORPH_RE.match(s)
    if not m:
        return None, [], []
    body = m.group(2)
    inner = ''
    if '(' in body:
        start = body.index('(')
        inner = body[start + 1:body.rindex(')')] if ')' in body else body[start + 1:]
        body = body[:start]
    main = [t.split(':')[-1] for t in body.split(';') if t.strip()]
    deriv = [t.split(':')[-1] for t in inner.split(';') if t.strip()]
    return m.group(1), main, deriv


def unknown_tags(main, deriv):
    bad = []
    expand = lambda t: t.split('_') if '_' in t and all(p in TAGS for p in t.split('_')) else [t]
    tags = [p for t in main for p in expand(t)]
    if any(t in GANAS for t in tags):
        # Finite verb: … pada; dhātupāṭha form; gaṇa. The form before the gaṇa is free text.
        g = max(i for i, t in enumerate(tags) if t in GANAS)
        tags = tags[:g - 1] + tags[g:]
    bad += [t for t in tags if t not in TAGS]
    if deriv:
        rest = [p for t in deriv[1:] for p in expand(t)]
        if any(t in GANAS for t in rest):
            g = max(i for i, t in enumerate(rest) if t in GANAS)
            rest = rest[:g - 1] + rest[g:]
        bad += [t for t in rest if t not in TAGS]
    return bad


def check_file(path, verse):
    """Returns a list of problems; empty when the file is fine."""
    problems = []
    with open(path, encoding='utf-8') as f:
        lines = [l.rstrip('\r') for l in f.read().split('\n')]
    if not lines or lines[0].split('\t') != HEADER:
        return [f'header must be: {chr(9).join(HEADER)}']
    rows = []
    for n, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        cells = line.split('\t')
        if len(cells) > len(HEADER) or len(cells) < len(HEADER) - 2:
            problems.append(f'line {n}: {len(cells)} columns, expected {len(HEADER)}')
            continue
        cells += [''] * (len(HEADER) - len(cells))
        rows.append((n, dict(zip(HEADER, [c.strip() for c in cells]))))
    if not rows:
        return problems + ['no rows']

    ids = {}
    words = {}
    order = []
    for n, r in rows:
        rid = r['index']
        if not ID_RE.match(rid):
            problems.append(f'line {n}: bad index {rid!r}')
            continue
        if rid in ids:
            problems.append(f'line {n}: index {rid} repeated')
        ids[rid] = r
        parts = rid.split('.')
        supplied = len(parts) == 3
        wid = rid if supplied else parts[0]
        if wid not in words:
            words[wid] = []
            order.append(wid)
        words[wid].append((n, r))
        word = r['word']
        if supplied != (word.startswith('(') and word.endswith(')')):
            problems.append(f'line {n}: understood words (N.k.m) and only they go in brackets: {word}')
        if supplied and r['sandhied_word']:
            problems.append(f'line {n}: an understood word has no sandhied_word')

    # Compounds: members N.1, N.2 … in order; all but the last end with "-".
    poems = []
    for wid in order:
        members = words[wid]
        if '.' not in wid:
            ks = [int(r['index'].split('.')[1]) for _, r in members]
            if ks != list(range(1, len(ks) + 1)):
                problems.append(f'word {wid}: members must be {wid}.1, {wid}.2, … in order')
        for i, (n, r) in enumerate(members):
            last = i == len(members) - 1
            if last == r['word'].endswith('-'):
                problems.append(f'line {n}: {"only non-final compound members end" if last else "a non-final compound member must end"} with "-": {r["word"]}')
            if i == 0:
                try:
                    poems.append(float(r['poem']))
                except ValueError:
                    problems.append(f'line {n}: poem must be the prose-order number, got {r["poem"]!r}')
            elif r['poem'] not in ('-', ''):
                problems.append(f'line {n}: poem of a later compound member must be "-"')
            if i > 0 and r['sandhied_word'] not in ('', '-'):
                problems.append(f'line {n}: sandhied_word goes on the first member of a compound only')
    if len(set(poems)) != len(poems):
        problems.append('poem numbers repeat')

    def resolve(target):
        if target in ids and len(target.split('.')) == 3:
            return target
        head = target.split('.')[0]
        return head if head in words else None

    parent = {}
    for wid in order:
        members = words[wid]
        for i, (n, r) in enumerate(members):
            last = i == len(members) - 1
            rel = r['kaaraka_sambandha']
            if rel in ('', '-'):
                if not last:
                    problems.append(f'line {n}: a compound member needs its samāsa relation to the next member')
                continue
            first = rel.split(';')[0].split('#')[0]
            if ',' not in first:
                problems.append(f'line {n}: relation must be "name,target": {rel}')
                continue
            name, target = (s.strip() for s in first.split(',', 1))
            key = canonical_relation(name)
            if key not in KNOWN_RELATIONS:
                problems.append(f'line {n}: unknown relation {name!r}')
            kind = RELATION_KIND.get(key)
            if not last:
                nxt = members[i + 1][1]['index']
                if kind != 'samasa':
                    problems.append(f'line {n}: a non-final compound member takes a samāsa relation, got {name}')
                elif target != nxt and resolve(target) != wid:
                    problems.append(f'line {n}: samāsa relation should point to the next member {nxt}')
                continue
            if kind == 'samasa':
                problems.append(f'line {n}: the last member carries the word\'s relation, not a samāsa type')
            t = resolve(target)
            if t is None:
                problems.append(f'line {n}: relation target {target} is not a word in this file')
            elif t == wid:
                problems.append(f'line {n}: relation points to its own word')
            elif kind != 'verb':
                parent[wid] = t
    for wid in order:
        seen, p = {wid}, parent.get(wid)
        while p is not None:
            if p in seen:
                problems.append(f'word {wid}: relations form a loop')
                break
            seen.add(p)
            p = parent.get(p)

    for wid in order:
        for n, r in words[wid]:
            morph = r['morph_in_context']
            if not morph:
                problems.append(f'line {n}: morph_in_context is empty')
                continue
            stem, main, deriv = morph_tags(morph)
            if stem is None:
                if not r['word'].endswith('-'):
                    problems.append(f'line {n}: morph must be stem{{tags}}: {morph}')
                continue
            bad = unknown_tags(main, deriv)
            if bad:
                problems.append(f'line {n}: unknown tags {bad} in {morph}')

    joined = DROP.sub('', unicodedata.normalize('NFC', ''.join(
        r['sandhied_word'] for _, r in rows if len(r['index'].split('.')) == 2 and r['sandhied_word'] != '-')))
    expected = verse_text(verse)
    if joined != expected:
        i = next((k for k in range(min(len(joined), len(expected))) if joined[k] != expected[k]),
                 min(len(joined), len(expected)))
        problems.append('sandhied_word column does not rebuild the verse; first difference at '
                        f'…{expected[max(0, i - 8):i + 12]}… (verse) vs …{joined[max(0, i - 8):i + 12]}… (file)')
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--check', nargs='*', metavar='SLUG', help='check only these files (no bundle)')
    ap.add_argument('--prepare', metavar='OUT', help='write verse texts and slugs as JSON')
    args = ap.parse_args()
    verses = deck_verses()
    by_slug = {slug(v['id']): v for v in verses}
    if len(by_slug) != len(verses):
        sys.exit('two verses share a slug')

    if args.prepare:
        items = [{'slug': slug(v['id']), 'id': v['id'], 'label': v['label'], 'deva': v['deva'],
                  'iast': v['iast'], 'words': v['words'], 'en_meaning': v['en_meaning']} for v in verses]
        with open(args.prepare, 'w', encoding='utf-8') as f:
            json.dump(items, f, ensure_ascii=False, indent=1)
        print(f'wrote {len(items)} verses to {args.prepare}')
        return

    wanted = args.check if args.check else list(by_slug)
    failed = 0
    missing = []
    for s in wanted:
        if s not in by_slug:
            print(f'{s}: not a Vishnu Sahasranamam verse slug')
            failed += 1
            continue
        path = os.path.join(SRC_DIR, s + '.tsv')
        if not os.path.exists(path):
            missing.append(s)
            continue
        problems = check_file(path, by_slug[s])
        if problems:
            failed += 1
            print(f'{s}:')
            for p in problems:
                print(f'  {p}')
    extra = sorted(set(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(SRC_DIR, '*.tsv'))) - set(by_slug))
    if extra:
        print('files with no matching verse:', ', '.join(extra))
    if missing:
        print(f'{len(missing)} verses have no file yet: {", ".join(missing[:12])}{" …" if len(missing) > 12 else ""}')
    checked = len(wanted) - len(missing)
    print(f'{checked - failed} of {checked} files OK')
    if args.check is not None:
        sys.exit(1 if failed else 0)
    if failed:
        sys.exit('not writing vs_analysis.json until every file passes')

    bundle = {
        'source': {'name': 'Sloka Words (draft)', 'credit': CREDIT, 'draft': True},
        'verses': {},
    }
    for v in verses:
        path = os.path.join(SRC_DIR, slug(v['id']) + '.tsv')
        if os.path.exists(path):
            with open(path, encoding='utf-8') as f:
                bundle['verses'][v['id']] = f.read()
    text = json.dumps(bundle, ensure_ascii=False, separators=(',', ':'))
    for out in OUTPUTS:
        with open(out, 'w', encoding='utf-8') as f:
            f.write(text)
    print(f'wrote {len(bundle["verses"])} verses ({len(text.encode()) // 1024} KB) to', ', '.join(os.path.relpath(o, ROOT) for o in OUTPUTS))


if __name__ == '__main__':
    main()
