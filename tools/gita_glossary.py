#!/usr/bin/env python3
"""Printable word list of the Bhagavad Gita, built from the Samsaadhanii word analysis.

Every word of the padacchedam (compound members counted separately) is reduced to its stem
or root, so the inflected forms of a word are listed together. Epithets of the same person
(Pārtha, Kaunteya, Dhanañjaya … → Arjuna) and synonyms (deha, śarīra … → body) are merged
into one entry, entries are grouped by theme, and a second part lists them by frequency.

  python3 tools/gita_glossary.py --local ~/ereaders          # build/gita_glossary.html
  python3 tools/gita_glossary.py --local ~/ereaders --pdf    # also build/gita_glossary.pdf

The Telugu and English glosses, themes and synonym groups are edited by hand in
analysis/gita_glossary.tsv. Headwords that are not in it yet are appended with empty
glosses; until they are filled in, the page shows the Samsaadhanii and deck meanings in grey.
The output stays in build/ (not published): it is derived from the Samsaadhanii data.
"""

import argparse
import collections
import glob
import html
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gita_analysis_index as gai  # noqa: E402
from build_deck import deva_to_telugu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECK = os.path.join(ROOT, 'app', 'Sources', 'SlokaWords', 'Resources', 'words.json')
GLOSSES = os.path.join(ROOT, 'analysis', 'gita_glossary.tsv')
OUT_HTML = os.path.join(ROOT, 'build', 'gita_glossary.html')
OUT_PDF = os.path.join(ROOT, 'build', 'gita_glossary.pdf')
COLUMNS = ['lemma', 'kind', 'count', 'te', 'en', 'theme', 'group']

THEMES = [
    ('people', 'వ్యక్తులు, సంబోధనలు', 'People and their epithets'),
    ('divine', 'భగవంతుడు, దేవతలు', 'God and the gods'),
    ('self', 'ఆత్మ, బ్రహ్మం', 'The Self and Brahman'),
    ('senses', 'ఇంద్రియాలు, గ్రహించడం', 'Senses and perception (see, hear, touch …)'),
    ('mind', 'మనస్సు, బుద్ధి, ఆలోచన', 'Mind, intellect and thought'),
    ('knowledge', 'జ్ఞానం, తెలియడం', 'Knowledge and knowing'),
    ('emotion', 'భావాలు, కోరికలు', 'Emotions, desire and aversion'),
    ('pleasure', 'సుఖదుఃఖాలు', 'Pleasure and pain'),
    ('action', 'కర్మ, చేయడం', 'Action and work'),
    ('yoga', 'యోగం, సాధన, సన్న్యాసం', 'Yoga, practice and renunciation'),
    ('worship', 'యజ్ఞం, భక్తి, దానం, తపస్సు', 'Sacrifice, devotion, gifts and austerity'),
    ('virtue', 'సద్గుణాలు', 'Virtues'),
    ('vice', 'దుర్గుణాలు, దోషాలు', 'Vices and faults'),
    ('dharma', 'ధర్మం, పాపపుణ్యాలు', 'Dharma, sin and merit'),
    ('guna', 'ప్రకృతి, త్రిగుణాలు', 'Prakṛti and the three guṇas'),
    ('liberation', 'బంధం, మోక్షం', 'Bondage and liberation'),
    ('life', 'జననం, మరణం, జీవితం', 'Birth, death and life'),
    ('being', 'ఉండటం, అవ్వటం', 'Being and becoming'),
    ('body', 'శరీరం', 'The body'),
    ('speech', 'మాట, శబ్దం', 'Speech and sound'),
    ('motion', 'కదలిక, నిలకడ', 'Going, coming and staying'),
    ('getting', 'పొందడం, ఇవ్వడం, ధరించడం', 'Getting, giving and holding'),
    ('war', 'యుద్ధం, సేన, ఆయుధాలు', 'War, armies and weapons'),
    ('family', 'కుటుంబం, సమాజం', 'Family and society'),
    ('world', 'లోకాలు, ప్రదేశాలు', 'Worlds and places'),
    ('nature', 'పంచభూతాలు, ప్రకృతి, జీవులు', 'Elements, nature and creatures'),
    ('time', 'కాలం', 'Time'),
    ('measure', 'వర్ణనలు, పరిమాణం, సంఖ్య', 'Description, size and number'),
    ('function', 'సర్వనామాలు, అవ్యయాలు', 'Pronouns and particles'),
    ('other', 'ఇతర పదాలు', 'Other words'),
]
THEME_IDS = [t[0] for t in THEMES]

# Synonym groups: lemmas with the same group id are printed as one entry.
GROUPS = {
    'krishna': ('people', 'శ్రీకృష్ణుడు', 'Śrī Kṛṣṇa'),
    'arjuna': ('people', 'అర్జునుడు', 'Arjuna'),
    'dhritarashtra': ('people', 'ధృతరాష్ట్రుడు', 'Dhṛtarāṣṭra'),
    'sanjaya': ('people', 'సంజయుడు', 'Sañjaya'),
    'drona': ('people', 'ద్రోణుడు', 'Droṇa'),
    'bhishma': ('people', 'భీష్ముడు', 'Bhīṣma'),
    'body': ('body', 'శరీరం', 'body'),
    'mind': ('mind', 'మనస్సు', 'mind'),
    'see': ('senses', 'చూడటం', 'seeing'),
    'hear': ('senses', 'వినడం', 'hearing'),
    'speak': ('speech', 'చెప్పడం, మాట్లాడటం', 'speaking'),
    'know': ('knowledge', 'తెలుసుకోవడం', 'knowing'),
    'go': ('motion', 'వెళ్ళడం, పొందడం', 'going, reaching'),
    'desire': ('emotion', 'కోరిక', 'desire'),
    'anger': ('emotion', 'కోపం', 'anger'),
    'fear': ('emotion', 'భయం', 'fear'),
    'joy': ('pleasure', 'ఆనందం', 'joy, delight'),
    'grief': ('pleasure', 'దుఃఖం, శోకం', 'grief, sorrow'),
    'delusion': ('mind', 'మోహం, భ్రమ', 'delusion'),
    'peace': ('virtue', 'శాంతి', 'peace, calm'),
    'battle': ('war', 'యుద్ధం', 'battle'),
    'army': ('war', 'సేన', 'army'),
    'weapon': ('war', 'ఆయుధం', 'weapon'),
    'conch': ('war', 'శంఖం', 'conch'),
    'king': ('family', 'రాజు', 'king'),
    'gods': ('divine', 'దేవతలు', 'gods'),
    'demons': ('divine', 'రాక్షసులు', 'demons'),
    'lord': ('divine', 'ప్రభువు, ఈశ్వరుడు', 'lord, ruler'),
    'world': ('world', 'లోకం, జగత్తు', 'world'),
    'earth': ('nature', 'భూమి', 'earth'),
    'water': ('nature', 'నీరు', 'water'),
    'fire': ('nature', 'అగ్ని', 'fire'),
    'wind': ('nature', 'గాలి', 'wind'),
    'sky': ('nature', 'ఆకాశం', 'sky, space'),
    'sun': ('nature', 'సూర్యుడు', 'sun'),
    'moon': ('nature', 'చంద్రుడు', 'moon'),
    'son': ('family', 'కుమారుడు', 'son'),
    'friend': ('family', 'మిత్రుడు', 'friend'),
    'enemy': ('war', 'శత్రువు', 'enemy'),
    'teacher': ('family', 'గురువు', 'teacher'),
    'person': ('family', 'మనిషి', 'man, person'),
    'death': ('life', 'మరణం', 'death'),
    'birth': ('life', 'జన్మ, పుట్టుక', 'birth, origin'),
    'liberation': ('liberation', 'మోక్షం', 'liberation'),
    'sin': ('dharma', 'పాపం', 'sin'),
    'all': ('measure', 'అన్నీ, సమస్తం', 'all, whole'),
    'great': ('measure', 'గొప్ప', 'great'),
    'supreme': ('measure', 'శ్రేష్ఠం, ఉత్తమం', 'highest, best'),
    'destroy': ('life', 'నాశనం, చంపడం', 'destroying, killing'),
    'renounce': ('yoga', 'త్యాగం, సన్న్యాసం', 'renouncing, giving up'),
    'attachment': ('emotion', 'ఆసక్తి, సంగం', 'attachment'),
    'hate': ('emotion', 'ద్వేషం', 'hatred'),
    'wonder': ('emotion', 'ఆశ్చర్యం', 'wonder'),
    'enjoy': ('pleasure', 'అనుభవించడం, భోగం', 'enjoying'),
    'obtain': ('getting', 'పొందడం', 'obtaining, attaining'),
    'restrain': ('yoga', 'నిగ్రహం', 'restraining'),
    'refuge': ('worship', 'ఆశ్రయం, శరణు', 'refuge, surrender'),
    'worship': ('worship', 'పూజ, ఆరాధన', 'worship'),
    'salute': ('worship', 'నమస్కరించడం', 'bowing down'),
    'sacrifice': ('worship', 'యజ్ఞం', 'sacrifice'),
    'pure': ('virtue', 'పవిత్రత, శుద్ధి', 'purity'),
    'hypocrisy': ('vice', 'దంభం', 'hypocrisy'),
    'bondage': ('liberation', 'బంధం', 'bondage'),
    'intellect': ('mind', 'బుద్ధి', 'intellect, understanding'),
    'think': ('mind', 'ఆలోచించడం', 'thinking'),
    'remember': ('mind', 'జ్ఞాపకం', 'remembering'),
    'doubt': ('mind', 'సందేహం', 'doubt'),
    'wise': ('knowledge', 'జ్ఞానులు, పండితులు', 'the wise'),
    'sage': ('people', 'ఋషులు, మునులు', 'sages'),
    'word': ('speech', 'మాట', 'word, speech'),
    'eye': ('body', 'కన్ను', 'eye'),
    'mouth': ('body', 'ముఖం, నోరు', 'face, mouth'),
    'victory': ('war', 'విజయం', 'victory'),
    'warrior': ('war', 'యోధులు, విలుకాండ్రు', 'warriors, archers'),
    'bow': ('war', 'విల్లు', 'bow'),
    'chariot': ('war', 'రథం', 'chariot'),
    'kinsman': ('family', 'బంధువులు', 'kinsmen'),
    'woman': ('family', 'స్త్రీ', 'woman'),
    'indra': ('divine', 'ఇంద్రుడు', 'Indra'),
    'ocean': ('nature', 'సముద్రం', 'ocean'),
    'light': ('nature', 'వెలుగు, కాంతి', 'light, radiance'),
    'horse': ('nature', 'గుర్రం', 'horse'),
    'elephant': ('nature', 'ఏనుగు', 'elephant'),
    'serpent': ('nature', 'పాము', 'serpent'),
    'always': ('time', 'ఎల్లప్పుడూ', 'always'),
    'dissolution': ('being', 'ప్రళయం, లయం', 'dissolution'),
    'equal': ('measure', 'సమానం', 'equal, same'),
    'terrible': ('measure', 'భయంకరమైన', 'terrible, fierce'),
    'multitude': ('measure', 'సమూహం', 'host, multitude'),
}

PREFIXES = {'प्र', 'परा', 'अप', 'सम्', 'अनु', 'अव', 'निस्', 'निर्', 'दुस्', 'दुर्', 'वि', 'आ', 'नि',
            'अधि', 'अपि', 'अति', 'सु', 'उत्', 'उद्', 'अभि', 'प्रति', 'परि', 'उप', 'अन्तर्', 'तिरस्',
            'पुरस्', 'प्रादुस्', 'आविस्', 'अलम्', 'श्रत्', 'नमस्'}
DERIVED = {'णिच्', 'सन्', 'यङ्', 'यङ्लुक्'}
STEM_FIXES = {'मत्': 'अस्मद्', 'मद्': 'अस्मद्', 'त्वत्': 'युष्मद्', 'त्वद्': 'युष्मद्', 'तत्': 'तद्',
              'यत्': 'यद्', 'एतत्': 'एतद्', 'महा': 'महत्', 'अ': 'नञ्', 'अन्': 'नञ्', 'अ-': 'नञ्',
              'अन्-': 'नञ्', 'कृत्': 'कृत', 'मनो': 'मनस्', 'मनः': 'मनस्', 'वाङ्': 'वाच्'}
PRONOUNS = {'अस्मद्', 'युष्मद्', 'तद्', 'यद्', 'इदम्', 'एतद्', 'किम्', 'अदस्', 'भवत्', 'सर्व', 'स्व'}
SPEAKERS = {'श्रीभगवानुवाच': 'krishna', 'अर्जुन उवाच': 'arjuna', 'सञ्जय उवाच': 'sanjaya',
            'धृतराष्ट्र उवाच': 'dhritarashtra'}
ADDRESSEE = {'krishna': 'arjuna', 'arjuna': 'krishna', 'sanjaya': 'dhritarashtra',
             'dhritarashtra': 'sanjaya'}

# Epithets, keyed by their member stems. how: 'name' always counts; 'sg' only in the
# singular; 'voc' only when used to address someone; 'addr' when used to address someone,
# and the person is whoever the speaker of the verse is talking to.
EPITHETS = {}
for person, how, items in [
    ('krishna', 'name', 'कृष्ण केशव मधुसूदन जनार्दन गोविन्द माधव हृषीकेश अच्युत वार्ष्णेय वासुदेव यादव हरि '
                        'केशिन्+निषूदन:केशिनिषूदन अरि+सूदन:अरिसूदन पुरुष+उत्तम:पुरुषोत्तम '
                        'जगत्+निवास:जगन्निवास देव+ईश:देवेश देव+देव:देवदेव जगत्+पति:जगत्पति '
                        'भूत+भावन:भूतभावन भूत+ईश:भूतेश योग+ईश्वर:योगेश्वर'),
    ('krishna', 'voc', 'विष्णु परम+ईश्वर:परमेश्वर विश्व+ईश्वर:विश्वेश्वर विश्व+रूप:विश्वरूप '
                       'विश्व+मूर्ति:विश्वमूर्ति कमल+पत्र+अक्ष:कमलपत्राक्ष नञ्+अन्त+रूप:अनन्तरूप '
                       'नञ्+अन्त+वीर्य:अनन्तवीर्य अप्रतिम+प्रभाव:अप्रतिमप्रभाव सहस्र+बाहु:सहस्रबाहु '
                       'देव+वर:देववर'),
    ('arjuna', 'name', 'अर्जुन धनञ्जय गुडाकेश परन्तप सव्यसाचिन् किरीटिन् भरत+ऋषभ:भरतर्षभ '
                       'भरत+सत्तम:भरतसत्तम भरत+श्रेष्ठ:भरतश्रेष्ठ कुरु+नन्दन:कुरुनन्दन कुरु+श्रेष्ठ:कुरुश्रेष्ठ '
                       'कुरु+सत्तम:कुरुसत्तम कुरु+प्रवीर:कुरुप्रवीर कपि+ध्वज:कपिध्वज पुरुष+ऋषभ:पुरुषर्षभ '
                       'पुरुष+व्याघ्र:पुरुषव्याघ्र'),
    ('arjuna', 'sg', 'पार्थ कौन्तेय पाण्डव'),
    ('dhritarashtra', 'name', 'धृतराष्ट्र'),
    ('dhritarashtra', 'voc', 'मही+पति:महीपति पृथिवी+पति:पृथिवीपति'),
    ('sanjaya', 'name', 'सञ्जय'),
    ('drona', 'name', 'द्रोण'),
    ('drona', 'voc', 'आचार्य द्विज+उत्तम:द्विजोत्तम'),
    ('bhishma', 'name', 'भीष्म कुरु+वृद्ध:कुरुवृद्ध'),
    (None, 'addr', 'भारत महत्+बाहु:महाबाहु नञ्+अघ:अनघ अनघ तात सखि वर राजन् प्रभु देव भगवत् '
                   'महत्+आत्मन्:महात्मन् योगिन्'),
]:
    for item in items.split():
        key, _, shown = item.partition(':')
        EPITHETS[key] = (person, how, shown or key)
        EPITHETS.setdefault(shown or key, EPITHETS[key])  # some files leave the compound unsplit

# Names and joined epithets, which a file sometimes gives as the analysis of the first of two
# members only (अ- अच्युत, च्युत …).
JOINED_EPITHETS = {shown for key, (person, how, shown) in EPITHETS.items()
                   if how in ('name', 'sg') or '+' in key}
NOT_KRISHNA = re.compile(r'dark|black', re.I)


# ---------------------------------------------------------------- reading the analysis

def clean_root(part):
    part = re.sub(r'\d', '', part)
    if part == 'आङ्':
        return 'आ'
    if part.startswith(('ष्था', 'ष्ठा')):
        return 'स्था' + part[4:]
    if part.startswith('ष') and len(part) > 1:
        return 'स' + part[1:]
    return part


def parse_morph(m):
    """(kind, lemma, family, gender, case, number) from a morph_in_context cell."""
    m = m.split('/')[0].strip()
    if m.startswith('(') and m.endswith(')'):
        m = m[1:-1]
    if not m or m == '-':
        return None
    head, _, rest = m.partition('{')
    if ',' in head or head.endswith('म्_') or re.search(r'_(विशेषणम्|सम्बन्धः|कर्ता|कर्म)', head) \
            or head.endswith(('ः,.', 'म्,.')):
        return None  # a relation in the morph column (shifted cells)
    rest = rest.rstrip('}')
    fields = re.split(r'[;{}()]', rest)
    case = next((f for f in fields if f in {'1', '2', '3', '4', '5', '6', '7', '8'}), '')
    number = next((f for f in fields if f in {'एक', 'द्वि', 'बहु'}), '')
    gender = next((f for f in fields if f in {'पुं', 'स्त्री', 'नपुं'}), '')
    root = None
    if '(' in head:
        head = head.split('(')[0]
    elif '_' in head:
        root = head
    if root:
        pass
    elif re.match(r'(कर्तरि|कर्मणि|भावे)', rest):
        root = head
    elif 'कृत्_प्रत्ययः' in rest:
        root = head
    else:
        k = re.search(r'\(([^;()]+);', rest)
        if k and not re.fullmatch(r'[\d;]*', k.group(1)):
            root = k.group(1)
    if root:
        parts = [clean_root(p) for p in root.split('_') if p]
        base = [p for p in parts if p not in DERIVED]
        dhatu = next((p for p in reversed(base) if p not in PREFIXES), base[-1] if base else root)
        prefixes = [p for p in base if p in PREFIXES]
        lemma = '+'.join(prefixes + [dhatu]) + (' (णिच्)' if 'णिच्' in parts else '')
        return 'verb', lemma, dhatu, '', case, number
    stem = re.sub(r'\d', '', head).strip()
    stem = STEM_FIXES.get(stem, stem)
    if stem.endswith('-') and stem != '-':
        stem = STEM_FIXES.get(stem[:-1], stem[:-1])
    if 'अव्य' in fields or stem == 'नञ्':
        kind = 'indecl'
    elif any(f.startswith('सर्व') for f in fields):
        kind = 'pron'
    elif not rest:
        kind = 'stem'
    else:
        kind = 'noun'
    return kind, stem, stem, gender, case, number


def verse_label(keys):
    ch = keys[0].split(':')[0]
    nums = [k.split(':')[1] for k in keys]
    return f'{ch}.{nums[0]}' + (f'–{nums[-1]}' if len(nums) > 1 else '')


def read_analysis(local):
    src = os.path.join(os.path.expanduser(local), gai.DIR)
    names = [os.path.basename(p) for p in glob.glob(os.path.join(src, '*.tsv'))]
    if not names:
        sys.exit(f'No Samsaadhanii files in {src}; clone github.com/{gai.REPO} first.')
    verses = gai.verse_files(names)
    covers = collections.defaultdict(list)
    for key, files in verses.items():
        for f in files:
            covers[f].append(key)
    deck = json.load(open(DECK, encoding='utf-8'))
    speaker = {v['id'][5:]: SPEAKERS.get((v.get('speaker') or {}).get('deva', ''), '')
               for v in deck['verses'] if v['src'] == 'gita'}

    words = []  # one list of rows per word (a compound is one word with several rows)
    for f in sorted(covers, key=lambda f: [int(x) for x in covers[f][0].split(':')]):
        keys = covers[f]
        lines = open(os.path.join(src, f + '.tsv'), encoding='utf-8-sig').read().splitlines()
        head = [h.strip() for h in lines[0].split('\t')]
        col = {name: head.index(name) for name in ('word', 'morph_in_context', 'english_meaning') if name in head}
        current = None
        for line in lines[1:]:
            cells = line.split('\t')
            wid = cells[0].strip()
            word = cells[col['word']].strip() if len(cells) > col['word'] else ''
            if not wid or not word or word.startswith('(') or word in {'.', '-'} or wid.count('.') != 1:
                continue
            get = lambda name: cells[col[name]].strip() if name in col and len(cells) > col[name] else ''
            row = {'word': word, 'morph': get('morph_in_context'), 'en': get('english_meaning').replace('_', ' '),
                   'ref': verse_label(keys), 'speaker': speaker.get(keys[0], '')}
            group = wid.split('.')[0]
            if current and current[0] == (f, group):
                current[1].append(row)
            else:
                current = ((f, group), [row])
                words.append(current)
    return [rows for _, rows in words], deck


def occurrences(words):
    """One record per padacchedam word, with epithets of a person kept whole."""
    by_form = {}
    for rows in words:
        for r in rows:
            p = parse_morph(r['morph'])
            if p:
                by_form.setdefault(r['word'].rstrip('-'), p)
    occ = []
    for rows in words:
        parsed = []
        for r in rows:
            p = parse_morph(r['morph']) or by_form.get(r['word'].rstrip('-'))
            if not p:
                stem = r['word'].rstrip('-')
                p = ('stem', STEM_FIXES.get(stem, stem), STEM_FIXES.get(stem, stem), '', '', '')
            parsed.append(p)
        if len(rows) > 1 and all(p == parsed[0] for p in parsed):
            joined = dict(rows[0], word=''.join(r['word'].rstrip('-') for r in rows))
            rows, parsed = [joined], parsed[:1]
        last = parsed[-1]
        key = '+'.join(p[1] for p in parsed)
        epithet = EPITHETS.get(key) or EPITHETS.get(key.replace('+', ''))
        if (not epithet and len(parsed) == 2 and parsed[0][1] in JOINED_EPITHETS
                and rows[0]['word'].rstrip('-') != parsed[0][1]):
            epithet, last = EPITHETS[parsed[0][1]], parsed[0]
        if epithet:
            person, how, shown = epithet
            vocative = last[4] == '8'
            if how == 'addr':
                person = ADDRESSEE.get(rows[0]['speaker']) if vocative else None
            elif how == 'voc' and not vocative:
                person = None
            elif how == 'sg' and last[5] not in ('एक', ''):
                person = None
            elif shown == 'कृष्ण' and NOT_KRISHNA.search(rows[-1]['en']):
                person = None
            if person:
                form = rows[0]['word'] if len(rows) == 1 else shown
                lemma = f'{shown}#{person}' if how == 'addr' else shown
                occ.append({'lemma': lemma, 'family': lemma, 'kind': 'epithet', 'person': person,
                            'form': form, 'ref': rows[0]['ref'], 'en': rows[-1]['en'] or rows[0]['en'],
                            'gender': last[3]})
                continue
        for r, p in zip(rows, parsed):
            kind, lemma, family, gender, case, number = p
            occ.append({'lemma': lemma, 'family': family, 'kind': kind, 'person': None,
                        'form': r['word'], 'ref': r['ref'], 'en': r['en'], 'gender': gender})
    return occ


# ---------------------------------------------------------------- glosses file

def read_glosses():
    rows = {}
    if os.path.exists(GLOSSES):
        lines = open(GLOSSES, encoding='utf-8').read().splitlines()
        for line in lines[1:]:
            if not line.strip():
                continue
            cells = (line.split('\t') + [''] * len(COLUMNS))[:len(COLUMNS)]
            rows[cells[0]] = dict(zip(COLUMNS, cells))
    return rows


def write_glosses(rows):
    os.makedirs(os.path.dirname(GLOSSES), exist_ok=True)
    order = sorted(rows.values(), key=lambda r: (-int(r['count'] or 0), r['lemma']))
    with open(GLOSSES, 'w', encoding='utf-8') as f:
        f.write('\t'.join(COLUMNS) + '\n')
        for r in order:
            f.write('\t'.join(r.get(c, '').replace('\t', ' ') for c in COLUMNS) + '\n')


def kind_label(kind, gender):
    if kind == 'verb':
        return 'ధాతు'
    if kind in ('noun', 'stem', 'epithet'):
        return {'पुं': 'పుం', 'स्त्री': 'స్త్రీ', 'नपुं': 'నపుం'}.get(gender, 'నామ')
    return {'pron': 'సర్వ', 'indecl': 'అవ్య'}.get(kind, '')


# ---------------------------------------------------------------- building entries

def deck_meanings(deck):
    """Telugu meaning of each surface form in the deck (first one listed)."""
    te = {}
    for w in deck['words']:
        if any(r['src'] == 'gita' for r in w['refs']) and w.get('te_meaning'):
            te.setdefault(w['deva'], w['te_meaning'])
    return te


def build(occ, glosses, deck):
    deck_te = deck_meanings(deck)
    lemmas = collections.OrderedDict()
    for o in occ:
        L = lemmas.setdefault(o['lemma'], {
            'lemma': o['lemma'], 'family': o['family'], 'kinds': collections.Counter(), 'count': 0,
            'forms': collections.Counter(), 'refs': [], 'en': collections.Counter(),
            'genders': collections.Counter(), 'person': o['person']})
        L['count'] += 1
        L['kinds'][o['kind']] += 1
        L['forms'][o['form']] += 1
        L['refs'].append(o['ref'])
        if o['en']:
            L['en'][o['en']] += 1
        if o['gender']:
            L['genders'][o['gender']] += 1

    for name, L in lemmas.items():
        kinds = [k for k, _ in L['kinds'].most_common() if k != 'stem']
        L['kind'] = 'pron' if name in PRONOUNS else (kinds[0] if kinds else 'stem')
        g = glosses.setdefault(name, {c: '' for c in COLUMNS})
        g['lemma'] = name
        g['kind'] = L['kind']
        g['count'] = str(L['count'])
        if L['person'] and not g['group']:
            g['group'] = L['person']
        L['gloss'] = g
        L['gender'] = L['genders'].most_common(1)[0][0] if L['genders'] else ''
        forms = [f.rstrip('-') for f, _ in L['forms'].most_common()]
        L['te_hint'] = next((deck_te[f] for f in forms if f in deck_te), '')
        L['en_hint'] = ', '.join(e for e, _ in L['en'].most_common(3))
    for name in list(glosses):
        if name not in lemmas:
            del glosses[name]

    families = collections.OrderedDict()
    for L in lemmas.values():
        families.setdefault(L['family'], []).append(L)

    entries = []
    grouped = collections.defaultdict(list)
    for fam, members in families.items():
        members.sort(key=lambda L: (L['lemma'] != fam, -L['count']))
        by_group = collections.OrderedDict()
        for L in members:
            by_group.setdefault(L['gloss']['group'], []).append(L)
        for group, part in by_group.items():
            block = {'family': fam, 'lemmas': part, 'count': sum(L['count'] for L in part)}
            if group:
                grouped[group].append(block)
            else:
                head = part[0]
                entries.append({'type': 'family', 'blocks': [block], 'count': block['count'],
                                'theme': head['gloss']['theme'] or default_theme(head)})
    for group, blocks in grouped.items():
        blocks.sort(key=lambda b: -b['count'])
        theme, te, en = GROUPS.get(group, ('', group, group))
        if len(blocks) == 1 and theme != 'people':
            head = blocks[0]['lemmas'][0]
            entries.append({'type': 'family', 'blocks': blocks, 'count': blocks[0]['count'],
                            'theme': head['gloss']['theme'] or theme})
            continue
        if not theme:
            theme = blocks[0]['lemmas'][0]['gloss']['theme'] or default_theme(blocks[0]['lemmas'][0])
        entries.append({'type': 'group', 'group': group, 'te': te, 'en': en, 'blocks': blocks,
                        'count': sum(b['count'] for b in blocks), 'theme': theme})
    entries.sort(key=lambda e: -e['count'])
    return entries, lemmas


def default_theme(L):
    if L['kind'] in ('pron', 'indecl'):
        return 'function'
    if L['kind'] == 'epithet':
        return 'people'
    return 'other'


# ---------------------------------------------------------------- HTML

CSS = """
@page { size: A4; margin: 12mm 11mm 14mm; }
* { box-sizing: border-box; }
body { font-family: 'Noto Sans Telugu', 'Kohinoor Telugu', 'Telugu MN', 'Noto Sans Devanagari',
       'Kohinoor Devanagari', system-ui, sans-serif; font-size: 9.2pt; line-height: 1.3; color: #1d1b18;
       margin: 0 auto; max-width: 200mm; padding: 10px; }
h1 { font-size: 19pt; margin: 0 0 2px; }
h2 { font-size: 13.5pt; margin: 0 0 6px; padding: 4px 0 3px; border-bottom: 1.5px solid #b4541a;
     color: #8a3c0d; break-after: avoid; column-span: all; }
h2 small { color: #6b625a; font-weight: normal; font-size: 10pt; }
.part { break-before: page; }
.part > h1 { font-size: 16pt; margin-bottom: 8px; }
.lead { color: #4b443d; margin: 4px 0 10px; }
.toc { columns: 2; font-size: 10pt; margin: 6px 0 0; padding-left: 1.3em; }
.theme { columns: 2; column-gap: 7mm; margin-bottom: 12px; }
.entry { break-inside: avoid; padding: 2px 0 3px; border-bottom: 0.5px solid #ddd5cb; }
.entry.grp { break-inside: auto; }
.entry.grp > .sub { break-inside: avoid; }
.hw { font-weight: 700; font-size: 10.5pt; }
.dv { color: #6b625a; font-weight: normal; font-size: 9.5pt; }
.k { font-size: 8pt; color: #6b625a; border: 0.5px solid #c8bfb4; border-radius: 3px; padding: 0 3px;
     margin-left: 3px; white-space: nowrap; }
.n { float: right; font-weight: 700; color: #8a3c0d; }
.mn { display: block; }
.mn i { color: #4b443d; }
.hint { color: #9a9087; }
.forms { display: block; font-size: 8.2pt; color: #4b443d; }
.forms b { font-weight: 600; color: #1d1b18; }
.refs { font-size: 7.8pt; color: #8b8178; }
.sub { margin: 2px 0 0 9px; padding-left: 6px; border-left: 2px solid #eadfd3; }
.legend { font-size: 9pt; color: #4b443d; border: 0.5px solid #ddd5cb; border-radius: 6px; padding: 6px 9px;
          margin: 10px 0 0; }
.sub .hw { font-size: 10pt; }
.grp > .hw { font-size: 12pt; }
table.freq { width: 100%; border-collapse: collapse; font-size: 9pt; }
.freqcols { columns: 2; column-gap: 7mm; }
.fr { display: flex; gap: 6px; break-inside: avoid; border-bottom: 0.5px solid #e6ded4; padding: 1.5px 0; }
.fr .r { width: 2.6em; color: #8b8178; text-align: right; flex: none; }
.fr .w { flex: none; max-width: 45%; font-weight: 600; }
.fr .m { flex: 1; color: #4b443d; overflow: hidden; }
.fr .c { flex: none; font-weight: 700; color: #8a3c0d; }
.credit { font-size: 8.5pt; color: #6b625a; margin-top: 10px; }
@media print { body { padding: 0; } a { color: inherit; text-decoration: none; } }
"""


def esc(s):
    return html.escape(s or '')


def word_html(deva, cls='hw'):
    return f'<span class="{cls}">{esc(deva_to_telugu(deva))}</span> <span class="dv">{esc(deva)}</span>'


def meaning_html(L):
    g = L['gloss']
    te = esc(g['te']) if g['te'] else (f'<span class="hint">{esc(L["te_hint"])}</span>' if L['te_hint'] else '')
    en = esc(g['en']) if g['en'] else (f'<span class="hint">{esc(L["en_hint"])}</span>' if L['en_hint'] else '')
    return f'<span class="mn">{te}{" <i>" + en + "</i>" if en else ""}</span>'


def forms_html(L, limit=6):
    forms = [(f, n) for f, n in L['forms'].most_common() if f.rstrip('-') != shown(L).replace('-', '')]
    if not forms or (len(forms) == 1 and L['kind'] == 'epithet'):
        return ''
    parts = [f'<b>{esc(deva_to_telugu(f))}</b>' + (f' {n}' if n > 1 else '') for f, n in forms[:limit]]
    more = f' +{len(forms) - limit}' if len(forms) > limit else ''
    return f'{", ".join(parts)}{more}'


def refs_html(L, limit=4):
    refs = list(dict.fromkeys(L['refs']))
    more = ' …' if len(refs) > limit else ''
    return f'<span class="refs">{" ".join(refs[:limit])}{more}</span>'


def detail_html(L):
    forms = forms_html(L)
    return f'<span class="forms">{forms}{" · " if forms else ""}{refs_html(L)}</span>'


def shown(L):
    return L['lemma'].split('#')[0].replace('+', '-')


def lemma_html(L, sub=False):
    label = kind_label(L['kind'], L['gender'])
    k = f'<span class="k">{label}</span>' if label else ''
    n = f'<span class="n">{L["count"]}</span>'
    return (f'<div class="{"sub" if sub else ""}">{n}{word_html(shown(L))}{k}'
            f'{meaning_html(L)}{detail_html(L)}</div>')


def entry_html(e):
    if e['type'] == 'family':
        lemmas = e['blocks'][0]['lemmas']
        body = lemma_html(lemmas[0]) + ''.join(lemma_html(L, True) for L in lemmas[1:])
        return f'<div class="entry">{body}</div>'
    head = (f'<span class="n">{e["count"]}</span><span class="hw">{esc(e["te"])}</span> '
            f'<span class="dv">· {esc(e["en"])}</span>')
    body = ''.join(lemma_html(L, True) for b in e['blocks'] for L in b['lemmas'])
    return f'<div class="entry grp">{head}{body}</div>'


def entry_title(e):
    if e['type'] == 'group':
        return f'<span class="w">{esc(e["te"])}</span>', esc(e['en'])
    L = e['blocks'][0]['lemmas'][0]
    g = L['gloss']
    meaning = g['te'] or L['te_hint'] or g['en'] or L['en_hint']
    return f'<span class="w">{esc(deva_to_telugu(shown(L)))}</span>', esc(meaning)


def render(entries, lemmas, total):
    themes = collections.OrderedDict((t, []) for t in THEME_IDS)
    for e in entries:
        themes.setdefault(e['theme'] if e['theme'] in themes else 'other', []).append(e)
    filled = sum(1 for L in lemmas.values() if L['gloss']['te'])
    out = [f'<!doctype html><html lang="te"><head><meta charset="utf-8">'
           f'<title>భగవద్గీత పదకోశం · Bhagavad Gita word list</title><style>{CSS}</style></head><body>',
           '<h1>భగవద్గీత పదకోశం <span class="dv">· Bhagavad Gita word list</span></h1>',
           f'<p class="lead">పదచ్ఛేదంలోని {total} పదాలు (సమాస పదాలు విడిగా) → {len(lemmas)} మూల పదాలు → '
           f'{len(entries)} ఎంట్రీలు. ప్రతి ఎంట్రీలో: పదం, అర్థం, గీతలో వచ్చిన రూపాలు, ఎన్నిసార్లు, శ్లోకాలు.<br>'
           f'{total} words of the padacchedam (compound members counted separately) → {len(lemmas)} stems and '
           f'roots → {len(entries)} entries after merging epithets and synonyms. '
           f'Part 1 groups them by theme; Part 2 lists them by frequency.'
           + (f' Grey meanings are not yet reviewed ({filled} of {len(lemmas)} done).' if filled < len(lemmas) else '')
           + '</p>',
           '<ol class="toc">' + ''.join(
               f'<li>{te} · {en} ({len(themes[t])})</li>' for t, te, en in THEMES if themes.get(t)) + '</ol>',
           '<p class="legend">ఎంట్రీ ఇలా చదవండి · How to read an entry: <b>పదం</b> <span class="dv">देवनागरी</span> '
           '<span class="k">రకం</span> and, on the right, how many times it occurs in the Gītā; then the Telugu '
           'and <i>English</i> meaning; then the forms found in the Gītā (with counts) and the first verses. '
           'రకం: పుం / స్త్రీ / నపుం = noun or adjective (m / f / n), ధాతు = verb root (all its forms, '
           'participles included), సర్వ = pronoun, అవ్య = indeclinable. Indented lines are prefixed verbs '
           'of the same root, or the members of a synonym group. Verse numbers like 1.4–6 mean the word is '
           'in a passage Samsaadhanii analyses together.</p>']
    out.append('<section class="part"><h1>1. విషయాల వారీగా <span class="dv">· By theme</span></h1>')
    for t, te, en in THEMES:
        if not themes.get(t):
            continue
        out.append(f'<h2>{te} <small>· {en} · {len(themes[t])}</small></h2><div class="theme">')
        out.extend(entry_html(e) for e in themes[t])
        out.append('</div>')
    out.append('</section><section class="part"><h1>2. ఎక్కువసార్లు వచ్చిన పదాలు ముందు '
               '<span class="dv">· By frequency</span></h1><div class="freqcols">')
    for i, e in enumerate(entries, 1):
        w, m = entry_title(e)
        out.append(f'<div class="fr"><span class="r">{i}</span>{w}<span class="m">{m}</span>'
                   f'<span class="c">{e["count"]}</span></div>')
    out.append('</div></section>')
    out.append('<p class="credit">Word analysis: Samsaadhanii (Department of Sanskrit Studies, University of '
               'Hyderabad; Amba Kulkarni and team), github.com/samsaadhanii/ereaders. Glosses, themes and '
               'groupings: Sloka Words (analysis/gita_glossary.tsv). For personal study.</p></body></html>')
    return '\n'.join(out)


CSS_COMPACT = """
@page { size: A4; margin: 8mm 8mm 9mm; }
* { box-sizing: border-box; }
body { font-family: 'Noto Sans Telugu', 'Kohinoor Telugu', 'Telugu MN', 'Noto Sans Devanagari',
       'Kohinoor Devanagari', system-ui, sans-serif; font-size: 7.6pt; line-height: 1.28; color: #1d1b18;
       margin: 0 auto; max-width: 200mm; }
h1 { font-size: 13pt; margin: 0 0 3px; }
.lead { color: #4b443d; margin: 0 0 6px; }
.cols { columns: 3; column-gap: 4.5mm; column-rule: 0.4px solid #e2d9ce; }
h2 { font-size: 9.5pt; margin: 5px 0 2px; padding-bottom: 1px; border-bottom: 1px solid #b4541a;
     color: #8a3c0d; break-after: avoid; }
h2 small { color: #6b625a; font-weight: normal; font-size: 7.5pt; }
p { margin: 0; padding: 0.6px 0; break-inside: avoid; }
p b { font-weight: 700; }
.dv { color: #6b625a; }
.k { color: #8b8178; font-size: 6.6pt; }
i { color: #4b443d; }
.f { color: #6b625a; font-size: 6.9pt; }
.s { padding-left: 7px; }
.gh { font-weight: 700; color: #8a3c0d; margin-top: 1.5px; break-after: avoid; }
.credit { font-size: 6.8pt; color: #6b625a; margin-top: 6px; column-span: all; }
"""

PERSON_TE = re.compile(r'\s*[—–-]\s*(?:శ్రీ)?(?:అర్జునుడు|కృష్ణుడు|ధృతరాష్ట్రుడు|సంజయుడు|ద్రోణుడు|భీష్ముడు)\s*$')
PERSON_EN = re.compile(r'\s*\((?:Arjuna|Kṛṣṇa|Krishna|Dhṛtarāṣṭra|Sañjaya|Droṇa|Bhīṣma)\)\s*$')


def compact_lemma(L, sub=False, in_person=False):
    g = L['gloss']
    te, en = g['te'] or L['te_hint'], g['en'] or L['en_hint']
    if in_person:
        te, en = PERSON_TE.sub('', te), PERSON_EN.sub('', en)
    label = kind_label(L['kind'], L['gender'])
    forms = [f.rstrip('-') for f, _ in L['forms'].most_common()
             if f.rstrip('-') != shown(L).replace('-', '')][:4]
    return (f'<p{" class=s" if sub else ""}><b>{esc(deva_to_telugu(shown(L)))}</b> '
            f'<span class="dv">{esc(shown(L))}</span>'
            + (f' <span class="k">{label}</span>' if label else '')
            + f' {esc(te)}' + (f' <i>{esc(en)}</i>' if en else '')
            + (f' <span class="f">· {esc(", ".join(deva_to_telugu(f) for f in forms))}</span>' if forms else '')
            + '</p>')


def compact_entry(e):
    if e['type'] == 'family':
        lemmas = e['blocks'][0]['lemmas']
        return compact_lemma(lemmas[0]) + ''.join(compact_lemma(L, True) for L in lemmas[1:])
    in_person = GROUPS.get(e['group'], ('',))[0] == 'people'
    return (f'<p class="gh">{esc(e["te"])} <span class="dv">· {esc(e["en"])}</span></p>'
            + ''.join(compact_lemma(L, True, in_person) for b in e['blocks'] for L in b['lemmas']))


def render_compact(entries, lemmas, total):
    themes = collections.OrderedDict((t, []) for t in THEME_IDS)
    for e in entries:
        themes.setdefault(e['theme'] if e['theme'] in themes else 'other', []).append(e)
    out = [f'<!doctype html><html lang="te"><head><meta charset="utf-8">'
           f'<title>భగవద్గీత పదకోశం (సంక్షిప్తం)</title><style>{CSS_COMPACT}</style></head><body>',
           '<h1>భగవద్గీత పదకోశం <span class="dv">· Bhagavad Gita word list (compact)</span></h1>',
           f'<p class="lead">{len(lemmas)} మూల పదాలు, విషయాల వారీగా; ప్రతి విషయంలో ఎక్కువసార్లు వచ్చిన పదాలు ముందు. '
           'పదం · దేవనాగరి · రకం (పుం/స్త్రీ/నపుం, ధాతు, సర్వ, అవ్య) · తెలుగు అర్థం · <i>English</i> · '
           'గీతలోని రూపాలు. Indented lines: prefixed verbs of the same root, or members of a group.</p>',
           '<div class="cols">']
    for t, te, en in THEMES:
        if not themes.get(t):
            continue
        out.append(f'<h2>{te} <small>· {en}</small></h2>')
        out.extend(compact_entry(e) for e in themes[t])
    out.append('<p class="credit">Word analysis: Samsaadhanii (University of Hyderabad), '
               'github.com/samsaadhanii/ereaders. Glosses and groupings: Sloka Words. For personal study.</p>'
               '</div></body></html>')
    return '\n'.join(out)


def print_pdf(html_path, pdf_path):
    chrome = find_chrome()
    if not chrome:
        sys.exit('Chrome not found; open the HTML file and print it instead.')
    subprocess.run([chrome, '--headless=new', '--disable-gpu', '--no-pdf-header-footer',
                    f'--print-to-pdf={pdf_path}', 'file://' + html_path], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f'wrote {os.path.relpath(pdf_path, ROOT)}')


def find_chrome():
    for path in ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
                 shutil.which('google-chrome') or '', shutil.which('chromium') or '']:
        if path and os.path.exists(path):
            return path
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--local', required=True, help=f'a clone of github.com/{gai.REPO}')
    ap.add_argument('--pdf', action='store_true', help='also print the PDF with Chrome')
    ap.add_argument('--compact', action='store_true',
                    help='a short version: one line per word, three columns, no counts, verses or Part 2 '
                         '(build/gita_glossary_compact.html)')
    args = ap.parse_args()

    words, deck = read_analysis(args.local)
    occ = occurrences(words)
    glosses = read_glosses()
    entries, lemmas = build(occ, glosses, deck)
    write_glosses(glosses)
    out_html, out_pdf = OUT_HTML, OUT_PDF
    if args.compact:
        out_html, out_pdf = (p.replace('gita_glossary.', 'gita_glossary_compact.') for p in (OUT_HTML, OUT_PDF))
    os.makedirs(os.path.dirname(out_html), exist_ok=True)
    with open(out_html, 'w', encoding='utf-8') as f:
        f.write((render_compact if args.compact else render)(entries, lemmas, len(occ)))
    print(f'{len(occ)} words → {len(lemmas)} stems and roots → {len(entries)} entries; '
          f'wrote {os.path.relpath(out_html, ROOT)} and {os.path.relpath(GLOSSES, ROOT)}')
    if args.pdf:
        print_pdf(out_html, out_pdf)


if __name__ == '__main__':
    main()
