"""Word-separated ("shloka break") verse lines for printing.

Adds `split: {deva, te, iast}` to each verse in the deck: the same lines with a space at every
word boundary, so the Devanagari top line breaks cleanly between words, while the sound stays
exactly as chanted. A consonant that sandhi joins to the next word keeps its virama:

    विश्वं विष्णुर्वषट्कारो भूतभव्यभवत्प्रभुः।  →  विश्वं विष्णुर् वषट्कारो भूत भव्य भवत् प्रभुः ।

Added breaks are thin spaces (U+2009); the verse's own spaces stay ordinary spaces, so the
apps can print them wider. A consonant joined to the next word's vowel is written out with its
virama and the vowel in full: वह्निरनिलो → वह्निर् अनिलो.

Word boundaries come from the verse's IAST line (spaces and hyphens, already in chanting form)
and from the hyphenated compounds of its word-by-word meanings. The Devanagari and Telugu lines
are lined up with the IAST letter by letter and split where both agree. Vowel sandhi
(भूतात्मा) can't be split without changing the sound, so those words stay joined.

  python3 tools/verse_split.py [--deck PATH]     # updates the deck in place
"""

import argparse
import difflib
import json
import os
import re
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECK = os.path.join(ROOT, 'app', 'Sources', 'SlokaWords', 'Resources', 'words.json')

VOWELS = ['a', 'ā', 'i', 'ī', 'u', 'ū', 'ṛ', 'ṝ', 'ḷ', 'ḹ', 'e', 'ai', 'o', 'au']
INDEPENDENT = dict(zip(VOWELS, 'अआइईउऊऋॠऌॡएऐओऔ'))
MATRA = dict(zip(VOWELS, ['', 'ा', 'ि', 'ी', 'ु', 'ू', 'ृ', 'ॄ', 'ॢ', 'ॣ', 'े', 'ै', 'ो', 'ौ']))
VOWEL_OF = {**{c: v for v, c in INDEPENDENT.items()}, **{c: v for v, c in MATRA.items() if c}}
VIRAMA = '्'
NUKTA = '़'
MARKS = {'ं', 'ः', 'ँ'}
AVAGRAHA = 'ऽ'
# Breaks added here use a thin space, so they read differently from the verse's own spaces.
THIN = '\u2009'

CONSONANTS_IAST = [
    ('kh', 'ख'), ('gh', 'घ'), ('ch', 'छ'), ('jh', 'झ'), ('ṭh', 'ठ'), ('ḍh', 'ढ'), ('th', 'थ'), ('dh', 'ध'),
    ('ph', 'फ'), ('bh', 'भ'), ('k', 'क'), ('g', 'ग'), ('ṅ', 'ङ'), ('c', 'च'), ('j', 'ज'), ('ñ', 'ञ'),
    ('ṭ', 'ट'), ('ḍ', 'ड'), ('ṇ', 'ण'), ('t', 'त'), ('d', 'द'), ('n', 'न'), ('p', 'प'), ('b', 'ब'),
    ('m', 'म'), ('y', 'य'), ('r', 'र'), ('l', 'ल'), ('v', 'व'), ('ś', 'श'), ('ṣ', 'ष'), ('s', 'स'),
    ('h', 'ह'), ('ḻ', 'ळ'),
]
VOWELS_IAST = [('ai', 'ai'), ('au', 'au'), ('ā', 'ā'), ('ī', 'ī'), ('ū', 'ū'), ('ṝ', 'ṝ'), ('ṛ', 'ṛ'),
               ('r̥', 'ṛ'), ('ḹ', 'ḹ'), ('ḷ', 'ḷ'), ('a', 'a'), ('i', 'i'), ('u', 'u'), ('e', 'e'), ('o', 'o')]
MARKS_IAST = [('ṃ', 'ं'), ('ṁ', 'ं'), ('m̐', 'ँ'), ('ḥ', 'ः'), ('’', AVAGRAHA), ("'", AVAGRAHA)]


# ---- Devanagari ⇄ tokens ----
# A token is ('C', consonant), ('V', vowel), ('M', mark or avagraha) or ('P', anything else).
# The conversion back reproduces the original text exactly, apart from inserted breaks.

def deva_tokens(text):
    tokens = []
    i = 0
    while i < len(text):
        ch = text[i]
        if '\u0915' <= ch <= '\u0939' or '\u0958' <= ch <= '\u095F':
            cons = ch
            if i + 1 < len(text) and text[i + 1] == NUKTA:
                cons += NUKTA
                i += 1
            tokens.append(('C', cons))
            nxt = text[i + 1] if i + 1 < len(text) else ''
            if nxt == VIRAMA:
                i += 1
            elif nxt in VOWEL_OF and nxt in MATRA.values():
                tokens.append(('V', VOWEL_OF[nxt]))
                i += 1
            else:
                tokens.append(('V', 'a'))
        elif ch in INDEPENDENT.values():
            tokens.append(('V', VOWEL_OF[ch]))
        elif ch in MARKS or ch == AVAGRAHA:
            tokens.append(('M', ch))
        else:
            tokens.append(('P', ch))
        i += 1
    return tokens


def render_deva(tokens, gap=' '):
    out = []
    for k, (kind, value) in enumerate(tokens):
        nxt = tokens[k + 1] if k + 1 < len(tokens) else ('P', '')
        if kind == 'C':
            out.append(value + ('' if nxt[0] == 'V' else VIRAMA))
        elif kind == 'V':
            prev = tokens[k - 1] if k else ('P', '')
            out.append(MATRA[value] if prev[0] == 'C' else INDEPENDENT[value])
        elif kind == 'B':
            out.append(gap)
        else:
            out.append(value)
    return ''.join(out)


def te_to_deva(text):
    return ''.join(chr(ord(c) - 0x300) if '\u0C00' <= c <= '\u0C7F' else c for c in text)


def deva_to_te(text):
    def shift(c):
        o = ord(c)
        if 0x0900 <= o <= 0x094F or 0x0955 <= o <= 0x0963 or 0x0966 <= o <= 0x096F:
            return chr(o + 0x300)
        return c
    return ''.join(shift(c) for c in text)


# ---- IAST ----

def iast_letters(text, soft=None):
    """Letter tokens of an IAST string, the offset of each in the string, and the indices of
    letters that start a new word (after a space or hyphen). Starts after a hyphen that follows
    a vowel are compound members, and are also added to `soft`."""
    s = unicodedata.normalize('NFC', text).lower()
    letters, offsets, starts = [], [], set()
    pending = False
    hyphen = False
    i = 0
    table = [(k, ('M', v)) for k, v in MARKS_IAST] + [(k, ('C', v)) for k, v in CONSONANTS_IAST] \
        + [(k, ('V', v)) for k, v in VOWELS_IAST]
    table.sort(key=lambda kv: -len(kv[0]))
    while i < len(s):
        if s[i] in ' -\u2010\u2011':
            hyphen = s[i] != ' ' and not pending
            pending = True
            i += 1
            continue
        for key, token in table:
            if s.startswith(key, i):
                if pending and letters:
                    starts.add(len(letters))
                    if hyphen and soft is not None and letters[-1][0] in 'VM':
                        soft.add(len(letters))
                pending = hyphen = False
                letters.append(token)
                offsets.append(i)
                i += len(key)
                break
        else:
            if s[i] in '|.,;।॥' or s[i].isdigit():
                pending = True
                hyphen = False
            i += 1
    return letters, offsets, starts


def heads(words):
    """The Sanskrit words of a word-by-word meaning: 'evam (thus), satata-yuktāḥ (…)'."""
    text = words
    while True:
        stripped = re.sub(r'\([^()]*\)', ' ', text)
        if stripped == text:
            break
        text = stripped
    return [w for part in re.split(r'[,;:]', text) for w in part.split()]


def compound_starts(letters, words):
    """Member boundaries of the hyphenated compounds in the word-by-word meanings, located in
    the verse's IAST letters."""
    starts = set()
    for head in heads(words):
        if '-' not in head:
            continue
        wl, _, ws = iast_letters(head)
        if not ws:
            continue
        need = min(len(wl), max(ws) + 2)
        if need < 4:
            continue
        probe = wl[:need]
        for at in range(len(letters) - need + 1):
            if letters[at:at + need] == probe:
                starts.update(at + b for b in ws)
    return starts


# ---- Splitting ----

def telugu_breaks(te_lines):
    """Letters of the Telugu lines (as Devanagari tokens) and the word starts its hyphens mark
    after a consonant, as in పాండవాశ్-చైవ."""
    letters, starts = [], set()
    for line in te_lines:
        tokens = deva_tokens(te_to_deva(line))
        for k, t in enumerate(tokens):
            if t[0] in 'CVM':
                if k >= 2 and tokens[k - 1] == ('P', '-') and tokens[k - 2][0] == 'C':
                    starts.add(len(letters))
                letters.append(t)
    return letters, starts


def split_lines(lines, iast, telugu):
    """Insert breaks into Devanagari `lines` at the word starts of the IAST and Telugu
    (letters, starts) pairs. A Telugu break counts only near an IAST boundary, since a stray
    hyphen in the Telugu (భోగైశ్-వర్య) would otherwise split a word."""
    tokens = []
    for n, line in enumerate(lines):
        if n:
            tokens.append(('P', '\n'))
        tokens.extend(deva_tokens(line))
    deva_idx = [k for k, t in enumerate(tokens) if t[0] in 'CVM']
    deva_letters = [tokens[k] for k in deva_idx]

    def mapped(letters):
        mapping = {}
        for a, b, size in difflib.SequenceMatcher(None, letters, deva_letters, autojunk=False).get_matching_blocks():
            for d in range(size):
                mapping[a + d] = b + d
        return mapping

    def exact(mapping, starts):
        return {mapping[i] for i in starts
                if i in mapping and i - 1 in mapping and mapping[i - 1] == mapping[i] - 1}

    iast_map = mapped(iast[0])
    near = set()
    for i in iast[1]:
        for d in (0, -1, 1, -2, 2):
            if i + d in iast_map:
                near.update(range(iast_map[i + d] - d - 2, iast_map[i + d] - d + 3))
                break
    te_map = mapped(telugu[0])
    candidates = exact(iast_map, iast[1]) | (exact(te_map, telugu[1]) & near)
    breaks = set()
    for j in candidates:
        k = deva_idx[j]
        if tokens[k][0] == 'M' or tokens[k - 1][0] == 'P':
            continue
        breaks.add(k)
    out = []
    for k, t in enumerate(tokens):
        if k in breaks:
            out.append(('B', THIN))
        out.append(t)
    text = render_deva(out, THIN)
    text = re.sub(r'(?<=\S)([।॥])', r' \1', text)
    text = re.sub(r' {2,}', ' ', text)
    return [line.strip() for line in text.split('\n')]


def split_iast(lines, starts, letters_by_line):
    out = []
    for line, (letters, offsets, own) in zip(lines, letters_by_line):
        cut = sorted({offsets[i] for i in starts if 0 < i < len(offsets)}, reverse=True)
        s = unicodedata.normalize('NFC', line)
        for at in cut:
            if s[at - 1] == '-':
                s = s[:at - 1] + THIN + s[at:]
            elif s[at - 1] != ' ':
                s = s[:at] + THIN + s[at:]
        out.append(re.sub(r' {2,}', ' ', s).strip())
    return out


# Compounds shorter than this many letters (भूतभावनः, धर्मक्षेत्रे) read easily as one word.
LONG_COMPOUND = 12


def split_verse(verse):
    softs = []
    per_line = []
    for line in verse.get('iast', []):
        soft = set()
        per_line.append(iast_letters(line, soft))
        softs.append(soft)
    letters, starts, soft, base = [], set(), set(), 0
    for (line_letters, _, own), line_soft in zip(per_line, softs):
        letters.extend(line_letters)
        starts.update(base + i for i in own)
        soft.update(base + i for i in line_soft)
        if base:
            starts.add(base)
        base += len(line_letters)
    hard = sorted((starts - soft) | {0, len(letters)})
    soft |= compound_starts(letters, verse.get('words', '')) - set(hard)
    # Keep a compound-member break only inside a long word.
    for i in sorted(soft):
        left = max(h for h in hard if h <= i)
        right = min(h for h in hard if h > i)
        if right - left >= LONG_COMPOUND:
            starts.add(i)
        else:
            starts.discard(i)
    line_starts, base = [], 0
    for line_letters, _, _ in per_line:
        line_starts.append({i - base for i in starts if base <= i < base + len(line_letters)})
        base += len(line_letters)
    te_plain = [re.sub(r'(?<=\S)-(?=\S)', '', line) for line in verse.get('te', [])]
    iast, telugu = (letters, starts), telugu_breaks(verse.get('te', []))
    return {
        'deva': split_lines(verse.get('deva', []), iast, telugu),
        'te': [deva_to_te(line) for line in split_lines([te_to_deva(l) for l in te_plain], iast, telugu)],
        'iast': [split_iast([line], s, [pl])[0] for line, s, pl in zip(verse.get('iast', []), line_starts, per_line)],
    }


def add_splits(verses):
    for verse in verses:
        verse['split'] = split_verse(verse)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--deck', default=DECK)
    ap.add_argument('--show', help='print the split lines of one verse id instead of saving')
    args = ap.parse_args()
    with open(args.deck, encoding='utf-8') as f:
        deck = json.load(f)
    if args.show:
        verse = next(v for v in deck['verses'] if v['id'] == args.show)
        for key, lines in split_verse(verse).items():
            print(key, *lines, sep='\n  ')
        return
    add_splits(deck['verses'])
    with open(args.deck, 'w', encoding='utf-8') as f:
        json.dump(deck, f, ensure_ascii=False, indent=1)
    print(f'split {len(deck["verses"])} verses in {os.path.relpath(args.deck, ROOT)}')


if __name__ == '__main__':
    main()
