#!/usr/bin/env python3
"""Build the Sloka Words flashcard deck from the bhakti stotra pages.

Reads sources.json, pulls every `Words:` list from the enabled pages, merges
duplicate words across all sources, adds Devanagari/Telugu spellings and the
Telugu glosses from te_meanings/*.json, and writes:

  app/Sources/SlokaWords/Resources/words.json   the deck bundled into the app
  missing_te.json                               words that still need a Telugu gloss

Usage:
  python3 tools/build_deck.py --repo ~/code/bhakti [--strict] [--out PATH]
"""
import argparse
import glob
import html
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- transliteration

VOWELS = [
    ('ai', 'ऐ', 'ै'), ('au', 'औ', 'ौ'),
    ('ā', 'आ', 'ा'), ('ī', 'ई', 'ी'), ('ū', 'ऊ', 'ू'),
    ('ṝ', 'ॠ', 'ॄ'), ('ṛ', 'ऋ', 'ृ'), ('ḹ', 'ॡ', 'ॣ'), ('ḷ', 'ऌ', 'ॢ'),
    ('ē', 'ए', 'े'), ('ō', 'ओ', 'ो'),
    ('a', 'अ', ''), ('i', 'इ', 'ि'), ('u', 'उ', 'ु'), ('e', 'ए', 'े'), ('o', 'ओ', 'ो'),
]
CONSONANTS = [
    ('kh', 'ख'), ('gh', 'घ'), ('ch', 'छ'), ('jh', 'झ'), ('ṭh', 'ठ'), ('ḍh', 'ढ'),
    ('th', 'थ'), ('dh', 'ध'), ('ph', 'फ'), ('bh', 'भ'),
    ('k', 'क'), ('g', 'ग'), ('ṅ', 'ङ'), ('c', 'च'), ('j', 'ज'), ('ñ', 'ञ'),
    ('ṭ', 'ट'), ('ḍ', 'ड'), ('ṇ', 'ण'), ('t', 'त'), ('d', 'द'), ('n', 'न'),
    ('p', 'प'), ('b', 'ब'), ('m', 'म'), ('y', 'य'), ('r', 'र'), ('l', 'ल'),
    ('v', 'व'), ('ś', 'श'), ('ṣ', 'ष'), ('s', 'स'), ('h', 'ह'), ('ḻ', 'ळ'),
]
MARKS = [('m̐', 'ँ'), ('ṃ', 'ं'), ('ṁ', 'ं'), ('ḥ', 'ः'), ('’', 'ऽ'), ("'", 'ऽ')]
VIRAMA = '्'


def iast_to_deva(text):
    s = unicodedata.normalize('NFC', text.lower())
    out, i, pending = [], 0, False
    while i < len(s):
        for lat, ind, sign in VOWELS:
            if s.startswith(lat, i):
                out.append(sign if pending else ind)
                pending = False
                i += len(lat)
                break
        else:
            for lat, dev in CONSONANTS:
                if s.startswith(lat, i):
                    if pending:
                        out.append(VIRAMA)
                    out.append(dev)
                    pending = True
                    i += len(lat)
                    break
            else:
                if pending:
                    out.append(VIRAMA)
                    pending = False
                for lat, dev in MARKS:
                    if s.startswith(lat, i):
                        out.append(dev)
                        i += len(lat)
                        break
                else:
                    out.append(s[i])
                    i += 1
    if pending:
        out.append(VIRAMA)
    return ''.join(out)


ANUSVARA_RULES = [
    (r'ఙ్(-?)(?=[కఖగఘ])', r'ం\1'),
    (r'ఞ్(-?)(?=[చఛజఝ])', r'ం\1'),
    (r'ణ్(-?)(?=[టఠడఢ])', r'ం\1'),
    (r'న్(-?)(?=[తథదధ])', r'ం\1'),
    (r'మ్(-?)(?=[పఫబభ])', r'ం\1'),
]


def deva_to_telugu(text):
    out = []
    for ch in text:
        c = ord(ch)
        if ch == 'ॐ':
            out.append('ఓం')
        elif 0x0901 <= c <= 0x0963 and ch not in '।॥':
            out.append(chr(c + 0x300))
        else:
            out.append(ch)
    tel = ''.join(out)
    for pat, rep in ANUSVARA_RULES:
        tel = re.sub(pat, rep, tel)
    return tel.replace('ఁ', 'ం')


# ---------------------------------------------------------------- parsing

WORDS_RE = re.compile(r'<div class="word-meaning"><strong>Words:</strong>(.*?)</div>', re.S)
BOX_RE = re.compile(r'<div class="verse-box[^"]*">\s*<strong>(.*?)</strong>', re.S)
H2_RE = re.compile(r'<h2(?: id="([^"]*)")?>(.*?)</h2>', re.S)


def strip_tags(s):
    return html.unescape(re.sub(r'<[^>]+>', '', s)).strip()


def split_top(text):
    """Split at commas/semicolons that are not inside parentheses."""
    items, cur, depth = [], [], 0
    for ch in text:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth = max(0, depth - 1)
        if ch in ',;' and depth == 0:
            items.append(''.join(cur))
            cur = []
        else:
            cur.append(ch)
    items.append(''.join(cur))
    return [i.strip() for i in items if i.strip()]


def parse_item(item):
    """'satata-yuktāḥ (constantly engaged)' -> ('satata-yuktāḥ', 'constantly engaged')."""
    arrow = re.match(r'^([^()→—]+?)\s*→\s*([^()]+?)\.?$', item)
    if arrow:
        return arrow.group(1).strip(), arrow.group(2).strip()
    start = item.find('(')
    if start <= 0 or re.search(r'[—=→:]', item[:start]):
        return None
    depth, end = 0, -1
    for j in range(start, len(item)):
        if item[j] == '(':
            depth += 1
        elif item[j] == ')':
            depth -= 1
            if depth == 0:
                end = j
                break
    if end < 0:
        end = len(item)
    head = item[:start].strip().rstrip('.:')
    meaning = item[start + 1:end].strip().rstrip('.').strip()
    if not head or not meaning:
        return None
    return head, meaning


ITRANS = [
    ('R^i', 'ṛ'), ('R^I', 'ṝ'), ('RRi', 'ṛ'), ('L^i', 'ḷ'), ('~N', 'ṅ'), ('~n', 'ñ'), ('GY', 'jñ'),
    ('chh', '\0'), ('Ch', '\0'), ('ch', 'c'), ('\0', 'ch'),
    ('Sh', 'ṣ'), ('sh', 'ś'),
    ('aa', 'ā'), ('ii', 'ī'), ('uu', 'ū'), ('A', 'ā'), ('I', 'ī'), ('U', 'ū'),
    ('T', 'ṭ'), ('D', 'ḍ'), ('N', 'ṇ'), ('M', 'ṃ'), ('H', 'ḥ'), ('.a', '’'), ('x', 'kṣ'),
]


def itrans_to_iast(s):
    for a, b in ITRANS:
        s = s.replace(a, b)
    # Sanskrit words never end in ह, so a final 'h' is a visarga typed in lower case.
    return re.sub(r'(?<=[aāiīuūeo])h\b', 'ḥ', s)


def itrans_outside_parens(s):
    """Convert the Sanskrit in a 'Words:' line, leaving the English glosses in (...) alone."""
    out, depth, cur = [], 0, []
    for ch in s + '\n':
        if ch == '(' and depth == 0:
            out.append(itrans_to_iast(''.join(cur)))
            cur = []
        if ch == '(':
            depth += 1
        cur.append(ch)
        if ch == ')':
            depth = max(0, depth - 1)
            if depth == 0:
                out.append(''.join(cur))
                cur = []
    out.append(itrans_to_iast(''.join(cur)))
    return ''.join(out).rstrip('\n')


def standard_iast(head, style):
    """Convert source-specific spellings to standard IAST before keying and transliterating."""
    s = unicodedata.normalize('NFC', head).replace('\u0323', '')
    if style == 'itrans':
        s = itrans_to_iast(s)
    if style == 'ch-for-c':
        # 'ch' = च and 'chh' = छ; a 'ch' right after 'c' (icchāmi) is already standard.
        s = s.replace('chh', '\0')
        s = re.sub(r'(?<!c)ch', 'c', s)
        s = s.replace('\0', 'ch')
        s = s.replace('śh', 'ś').replace('ṣh', 'ṣ')
    return s


def word_key(head):
    s = unicodedata.normalize('NFC', head.lower()).replace('ṁ', 'ṃ').replace('ō', 'o').replace('ē', 'e')
    s = s.replace("'", '’').replace('-', '')
    s = re.sub(r'[^\w’]', '', s)
    s = re.sub(r'ṃ$', 'm', s)
    # Word-final voiced/unvoiced stops are sandhi variants of one word (vedavid / veda-vit).
    return re.sub(r'[dgbḍ]$', lambda m: {'d': 't', 'g': 'k', 'b': 'p', 'ḍ': 'ṭ'}[m.group()], s)


PARTICLES = {'ca', 'eva', 'api', 'hi', 'tu', 'vā'}


def strip_particles(iast):
    """'drupadaḥ ca' -> 'drupadaḥ', 'ye ca api' -> 'ye'; single words are left alone."""
    tokens = iast.split()
    while len(tokens) > 1 and tokens[-1] in PARTICLES:
        tokens.pop()
    while len(tokens) > 1 and tokens[0] in PARTICLES:
        tokens.pop(0)
    return ' '.join(tokens)


def consolidate(words):
    """Merge particle-only phrase variants into their word, then drop phrase cards whose
    words all have cards of their own, moving the phrase's references onto those words."""
    merged = {}
    for w in words.values():
        iast = strip_particles(w['iast'])
        key = word_key(iast)
        tgt = merged.setdefault(key, {'id': key, 'iast': iast, 'en': [], 'refs': []})
        if ' ' in tgt['iast'] and ' ' not in iast:
            tgt['iast'] = iast
        for e in w['en']:
            if e not in tgt['en']:
                tgt['en'].append(e)
        for r in w['refs']:
            if r not in tgt['refs']:
                tgt['refs'].append(r)

    singles = {k for k, w in merged.items() if ' ' not in w['iast']}
    dropped = 0
    for key in [k for k, w in merged.items() if ' ' in w['iast']]:
        parts = [word_key(t) for t in merged[key]['iast'].split()]
        if all(p in singles for p in parts):
            for p in parts:
                for r in merged[key]['refs']:
                    if r not in merged[p]['refs']:
                        merged[p]['refs'].append(r)
            del merged[key]
            dropped += 1
    return merged, dropped


def display_iast(head):
    s = unicodedata.normalize('NFC', head.lower()).replace('ṁ', 'ṃ').replace('ō', 'o').replace('ē', 'e')
    return re.sub(r'\s+', ' ', s).strip()


def verse_label(raw):
    s = strip_tags(re.sub(r'<span class="name-range">.*?</span>', '', raw))
    return re.split(r'\s+[—–-]\s+', s)[0].strip()


def file_title(path, text):
    m = re.search(r'<title>(.*?)</title>', text, re.S)
    title = strip_tags(m.group(1)) if m else os.path.basename(path)
    return re.split(r'\s+[—–-]\s+', title)[-1].strip()


SCRIPTS_RE = re.compile(r'<div class="scripts">', re.S)
MAIN_BOX_RE = re.compile(r'<div class="verse-box">\s*<strong>(.*?)</strong>', re.S)


def first_div(segment, cls):
    m = re.search(rf'<div class="{cls}">(.*?)</div>', segment, re.S)
    return m.group(1) if m else ''


def clean_meaning(raw):
    return re.sub(r'^\s*(Meaning|Words|తెలుగు భావం)\s*:\s*', '', strip_tags(raw)).strip()


def verse_lines(raw, kind):
    if kind == 'te' or re.search(r'<br\s*/?>\s*\S', raw):
        lines = re.split(r'<br\s*/?>', raw)
    elif kind == 'deva':
        lines = re.split(r'(?<=।)\s+', strip_tags(raw))
    else:
        lines = re.split(r'(?<=[^|]\|)\s+(?!\|)', strip_tags(raw))
    return [strip_tags(l) for l in lines if strip_tags(l)]


def verse_blocks(text):
    """Yield (h2_id, verse_label, fields) for each verse; short speaker lines are skipped."""
    heads = [(m.start(), m.group(1) or strip_tags(m.group(2))) for m in H2_RE.finditer(text)]
    boxes = [(m.start(), verse_label(m.group(1))) for m in MAIN_BOX_RE.finditer(text)]
    starts = [m.start() for m in SCRIPTS_RE.finditer(text)] + [len(text)]
    for pos, end in zip(starts, starts[1:]):
        seg = text[pos:end]
        deva = first_div(seg, 'sanskrit')
        if not re.search('[।॥]', deva) and len(strip_tags(deva)) < 40:
            continue
        h2 = next((h for p, h in reversed(heads) if p < pos), '')
        label = next((b for p, b in reversed(boxes) if p < pos), '')
        yield h2, label, {
            'deva': verse_lines(deva, 'deva'),
            'te': verse_lines(first_div(seg, 'telugu'), 'te'),
            'iast': verse_lines(first_div(seg, 'english'), 'iast'),
            'te_meaning': clean_meaning(first_div(seg, 'telugu-meaning')),
            'en_meaning': clean_meaning(first_div(seg, 'full-meaning')),
            'words': clean_meaning(first_div(seg, 'word-meaning')),
        }


def blocks(text):
    """Yield (h2_id, verse_label, words_html) for each Words: block."""
    heads = [(m.start(), m.group(1) or strip_tags(m.group(2))) for m in H2_RE.finditer(text)]
    boxes = [(m.start(), verse_label(m.group(1))) for m in BOX_RE.finditer(text)]
    for m in WORDS_RE.finditer(text):
        pos = m.start()
        h2 = next((h for p, h in reversed(heads) if p < pos), '')
        label = next((b for p, b in reversed(boxes) if p < pos), '')
        yield h2, label, m.group(1)


# ---------------------------------------------------------------- build

def build(repo, sources):
    deck_sources, words, warnings = [], {}, []
    verses, verse_ids = [], set()
    for src in sources:
        if not src.get('enabled'):
            continue
        paths = sorted(glob.glob(os.path.join(repo, src['files'])))
        if not paths:
            warnings.append(f"{src['id']}: no files match {src['files']}")
        groups, include = [], src.get('include_groups')
        for path in paths:
            text = open(path, encoding='utf-8').read()
            by = src.get('group_by', 'none')
            if by == 'file':
                n = re.search(r'(\d+)', os.path.basename(path))
                gid = str(int(n.group(1))) if n else os.path.basename(path)
                if include and gid not in include:
                    continue
                label = src.get('group_label', '{title}').format(n=gid, title=file_title(path, text))
                file_groups = {'*': (gid, label)}
            elif by == 'heading':
                file_groups = {h: (g['id'], g['label']) for g in src['groups'] for h in g['headings']}
            else:
                file_groups = {'*': (src['id'], src['title'])}
            found = 0
            for h2, vlabel, raw in blocks(text):
                gid, glabel = file_groups.get(h2) or file_groups.get('*') or (None, None)
                if gid is None:
                    warnings.append(f"{os.path.basename(path)}: heading '{h2}' is not mapped to a group")
                    continue
                if include and gid not in include:
                    continue
                if not any(g['id'] == gid for g in groups):
                    groups.append({'id': gid, 'label': glabel})
                vnum = re.sub(r'^(Verse|Shloka)\s+', '', vlabel)
                ref_label = f"{src.get('short', src['title'])} {gid}.{vnum}" if by == 'file' else f"{src.get('short', src['title'])} · {vlabel}"
                for item in split_top(strip_tags(raw)):
                    parsed = parse_item(item)
                    if not parsed:
                        warnings.append(f"{os.path.basename(path)} {vlabel}: could not parse '{item[:60]}'")
                        continue
                    head, meaning = parsed
                    head = standard_iast(head, src.get('iast_style'))
                    key = word_key(head)
                    if not key:
                        continue
                    found += 1
                    w = words.setdefault(key, {'id': key, 'iast': display_iast(head), 'en': [], 'refs': []})
                    if meaning not in w['en']:
                        w['en'].append(meaning)
                    ref = {'src': src['id'], 'group': gid, 'label': ref_label}
                    if ref not in w['refs']:
                        w['refs'].append(ref)
            if not found and (not include or by != 'file'):
                warnings.append(f"{os.path.basename(path)}: no Words: entries found")
            for h2, vlabel, fields in verse_blocks(text):
                gid, glabel = file_groups.get(h2) or file_groups.get('*') or (None, None)
                if gid is None or (include and gid not in include):
                    continue
                if not any(g['id'] == gid for g in groups):
                    groups.append({'id': gid, 'label': glabel})
                vnum = re.sub(r'^(Verse|Shloka)\s+', '', vlabel)
                short = src.get('short', src['title'])
                ref_label = f"{short} {gid}.{vnum}" if by == 'file' else f"{short} · {vlabel}"
                vid = f"{src['id']}:{gid}:{vnum}"
                n = 2
                while vid in verse_ids:
                    vid = f"{src['id']}:{gid}:{vnum}#{n}"
                    n += 1
                verse_ids.add(vid)
                if src.get('iast_style') == 'itrans':
                    fields['iast'] = [itrans_to_iast(l) for l in fields['iast']]
                    fields['words'] = itrans_outside_parens(fields['words'])
                verses.append({'id': vid, 'src': src['id'], 'group': gid, 'label': ref_label,
                               **fields, 'edited': False})
        deck_sources.append({'id': src['id'], 'title': src['title'], 'lang': src.get('lang', 'sanskrit'), 'groups': groups})

    raw_count = len(words)
    words, dropped = consolidate(words)
    warnings.append(f"merged {raw_count - len(words) - dropped} particle/spelling variants and "
                    f"dropped {dropped} phrase cards covered by single-word cards")
    for w in words.values():
        w['deva'] = iast_to_deva(w['iast'])
        w['te'] = deva_to_telugu(w['deva'])
    return deck_sources, words, verses, warnings


def apply_verse_edits(verses):
    """Apply chanting-style edits exported from the app (verse_edits.json)."""
    path = os.path.join(ROOT, 'verse_edits.json')
    if not os.path.exists(path):
        return 0
    edits = json.load(open(path, encoding='utf-8'))
    by_id = {v['id']: v for v in verses}
    applied = 0
    for vid, fields in edits.items():
        v = by_id.get(vid)
        if not v:
            print(f"warning: verse_edits.json: unknown verse id {vid}", file=sys.stderr)
            continue
        for k in ('te', 'deva', 'iast'):
            if k in fields:
                v[k] = [l.strip() for l in fields[k].split('\n') if l.strip()]
        v['edited'] = True
        applied += 1
    return applied


def load_glosses():
    glosses = {}
    for path in sorted(glob.glob(os.path.join(ROOT, 'te_meanings', '*.json'))):
        for k, v in json.load(open(path, encoding='utf-8')).items():
            glosses[word_key(k)] = v
    return glosses


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--repo', required=True, help='path to the bhakti repo')
    ap.add_argument('--out', default=os.path.join(ROOT, 'app', 'Sources', 'SlokaWords', 'Resources', 'words.json'))
    ap.add_argument('--strict', action='store_true', help='fail if any word lacks a Telugu gloss')
    args = ap.parse_args()

    sources = json.load(open(os.path.join(ROOT, 'sources.json'), encoding='utf-8'))
    deck_sources, words, verses, warnings = build(os.path.expanduser(args.repo), sources)
    edited = apply_verse_edits(verses)
    glosses = load_glosses()

    missing = {}
    ordered = []
    for key, w in words.items():
        w['te_meaning'] = glosses.get(key, '')
        if not w['te_meaning']:
            missing[w['iast']] = {'en': w['en'], 'refs': [r['label'] for r in w['refs']]}
        ordered.append({k: w[k] for k in ('id', 'iast', 'deva', 'te', 'en', 'te_meaning', 'refs')})

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump({'sources': deck_sources, 'words': ordered, 'verses': verses}, f, ensure_ascii=False, indent=1)
    with open(os.path.join(ROOT, 'missing_te.json'), 'w', encoding='utf-8') as f:
        json.dump(missing, f, ensure_ascii=False, indent=1)

    for w in warnings:
        print('warning:', w, file=sys.stderr)
    for s in deck_sources:
        n = sum(1 for w in ordered if any(r['src'] == s['id'] for r in w['refs']))
        print(f"{s['title']}: {n} words in {len(s['groups'])} group(s)")
    print(f"unique words: {len(ordered)}, missing Telugu gloss: {len(missing)}")
    print(f"verses: {len(verses)} ({edited} with chanting-style edits from verse_edits.json)")
    print(f"wrote {args.out}")
    if args.strict and missing:
        sys.exit(f"--strict: {len(missing)} words need a Telugu gloss (see missing_te.json)")


if __name__ == '__main__':
    main()
