"""Grammar cards from a bhakti study page such as Study/sanskrit_via_telugu_starter.html.

Each table row becomes a card: its first meaningful cell is the prompt, and the other cells,
with their column headings, are the answer. Practice drills and dialogue lines become
Sanskrit → Telugu cards. Every card keeps its lesson (h3) and sub-heading (h4) as context.
"""
import html
import os
import re

H3_RE = re.compile(r'<h3(?:\s+id="([^"]*)")?[^>]*>(.*?)</h3>', re.S)
BLOCK_RE = re.compile(
    r'<h4[^>]*>(?P<h4>.*?)</h4>'
    r'|<table[^>]*>(?P<table>.*?)</table>'
    r'|<div class="drill">(?P<drill>.*?)</div>'
    r'|<div class="line [^"]*">(?P<line>.*?<div class="te-line">.*?</div>)\s*</div>', re.S)
ROW_RE = re.compile(r'<tr[^>]*>(.*?)</tr>', re.S)
CELL_RE = re.compile(r'<t([dh])[^>]*>(.*?)</t[dh]>', re.S)
DEVA_RE = re.compile('[\u0900-\u097F]')
FILLER = {'', '—', '-', '–', '#'}


def text(raw):
    raw = re.sub(r'<br\s*/?>', ' ', raw)
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', raw))).strip()


def cell(head, raw, to_telugu):
    t = text(raw)
    c = {'head': head, 'text': t}
    if DEVA_RE.search(t):
        c['te'] = to_telugu(t)
    return c


def table_cards(table, to_telugu):
    headers, cards = [], []
    for row in ROW_RE.findall(table):
        cells = CELL_RE.findall(row)
        if cells and all(kind == 'h' for kind, _ in cells):
            headers = [text(c) for _, c in cells]
            continue
        values = [c for _, c in cells]
        heads = headers + [''] * (len(values) - len(headers))
        first = next((i for i, v in enumerate(values)
                      if text(v) not in FILLER and not text(v).isdigit()), None)
        if first is None:
            continue
        prompt = cell(heads[first], values[first], to_telugu)
        answer = [cell(heads[i], v, to_telugu) for i, v in enumerate(values)
                  if i != first and text(v) not in FILLER]
        if answer:
            cards.append((prompt, answer))
    return cards


def drill_card(raw, to_telugu):
    body = re.sub(r'<strong>.*?</strong>', '', raw, count=1, flags=re.S)
    if '→' not in body:
        return None
    sa, te = body.split('→', 1)
    return cell('సంస్కృతం', sa, to_telugu), [cell('తెలుగు', te, to_telugu)]


def line_card(raw, to_telugu):
    sa = re.sub(r'<div class="te-line">.*', '', raw, flags=re.S)
    sa = re.sub(r'<span class="label">.*?</span>', '', sa, flags=re.S)
    te = re.search(r'<div class="te-line">(.*?)</div>', raw, re.S).group(1)
    return cell('సంస్కృతం', sa, to_telugu), [cell('తెలుగు', te, to_telugu)]


def build_lessons(repo, src, to_telugu):
    """Return (deck source, cards) for a `"type": "lessons"` entry in sources.json."""
    path = os.path.join(repo, src['files'])
    page = open(path, encoding='utf-8').read()
    link = src['files']
    sections = list(H3_RE.finditer(page))
    groups, cards, ids = [], [], set()
    for i, m in enumerate(sections):
        end = sections[i + 1].start() if i + 1 < len(sections) else len(page)
        next_h2 = page.find('<h2', m.end(), end)
        body = page[m.end():next_h2 if next_h2 != -1 else end]
        title = text(m.group(2))
        number = re.match(r'[\d.]+', title)
        gid = number.group(0).rstrip('.') if number else (m.group(1) or f's{i}')
        context, found = '', []
        for b in BLOCK_RE.finditer(body):
            if b.group('h4') is not None:
                context = text(b.group('h4'))
            elif b.group('table') is not None:
                found += [(context, p, a) for p, a in table_cards(b.group('table'), to_telugu)]
            elif b.group('drill') is not None:
                card = drill_card(b.group('drill'), to_telugu)
                if card:
                    found.append(('అభ్యాసం', *card))
            else:
                found.append((context, *line_card(b.group('line'), to_telugu)))
        if not found:
            continue
        groups.append({'id': gid, 'label': title})
        for ctx, prompt, answer in found:
            cid = f"{src['id']}:{gid}:{prompt['text'][:48]}"
            n, base = 2, cid
            while cid in ids:
                cid = f'{base}#{n}'
                n += 1
            ids.add(cid)
            cards.append({
                'id': cid, 'src': src['id'], 'group': gid, 'label': title, 'context': ctx,
                'prompt': prompt, 'answer': answer,
                'link': f"{link}#{m.group(1)}" if m.group(1) else link,
            })
    source = {'id': src['id'], 'title': src['title'], 'lang': src.get('lang', 'sanskrit'),
              'kind': 'grammar', 'groups': groups}
    return source, cards
