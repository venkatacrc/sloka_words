#!/usr/bin/env python3
"""Write gita_analysis.json: where each Gita verse's Samsaadhanii analysis lives, plus the
Telugu explanations the apps show for its relation names and grammar tags.

The analysis itself (word split, anvaya, word analysis, kāraka relations) is not copied.
The apps download each verse from the samsaadhanii/ereaders repository, pinned to COMMIT,
the first time it is opened, and keep it on the device.

  python3 tools/gita_analysis_index.py                       # list files from GitHub
  python3 tools/gita_analysis_index.py --local ~/ereaders    # use a local clone instead
  python3 tools/gita_analysis_index.py --local ~/ereaders --check   # also report unknown labels
"""
import argparse
import collections
import glob
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = 'samsaadhanii/ereaders'
COMMIT = '80a59baa4ec38ec5d365c49af448d05871b7eab0'
DIR = 'Bhagavadgita_new'
OUTPUTS = [
    os.path.join(ROOT, 'web', 'gita_analysis.json'),
    os.path.join(ROOT, 'app', 'Sources', 'SlokaWords', 'Resources', 'gita_analysis.json'),
]

# kind: karaka (kāraka), verb (agreement noted on the verb, not drawn), samasa (inside a
# compound), other (every other relation).
RELATIONS = [
    ('कर्ता', 'karaka', 'కర్త — పని చేసేవారు', 'agent (doer)'),
    ('कर्म', 'karaka', 'కర్మ — పని దేనిపై జరుగుతుందో', 'object'),
    ('करणम्', 'karaka', 'కరణం — సాధనం (చేత, తో)', 'instrument'),
    ('सम्प्रदानम्', 'karaka', 'సంప్రదానం — ఎవరికి (కొరకు)', 'recipient'),
    ('अपादानम्', 'karaka', 'అపాదానం — దేని నుండి', 'source (from)'),
    ('अधिकरणम्', 'karaka', 'అధికరణం — దేనిలో, ఎక్కడ', 'locus (in, on)'),
    ('कालाधिकरणम्', 'karaka', 'కాలాధికరణం — ఎప్పుడు', 'time'),
    ('देशाधिकरणम्', 'karaka', 'దేశాధికరణం — ఏ చోట', 'place'),
    ('विषयाधिकरणम्', 'karaka', 'విషయాధికరణం — దేని విషయంలో', 'subject matter (about)'),
    ('मुख्यकर्म', 'karaka', 'ముఖ్య కర్మ', 'primary object'),
    ('गौणकर्म', 'karaka', 'గౌణ కర్మ — రెండవ కర్మ', 'secondary object'),
    ('प्रयोजककर्ता', 'karaka', 'ప్రయోజక కర్త — చేయించేవారు', 'causer'),
    ('प्रयोज्यकर्ता', 'karaka', 'ప్రయోజ్య కర్త — చేయించబడేవారు', 'agent made to act'),
    ('अभिहित_कर्ता', 'verb', 'క్రియా ప్రత్యయం కర్తను తెలుపుతుంది', 'verb ending agrees with the agent'),
    ('अभिहित_कर्म', 'verb', 'క్రియా ప్రత్యయం కర్మను తెలుపుతుంది (కర్మణి)', 'verb ending agrees with the object'),
    ('सम्बन्धः', 'other', 'సంబంధం — దీనితో అన్వయం', 'related to'),
    ('षष्ठीसम्बन्धः', 'other', 'షష్ఠీ సంబంధం — "యొక్క"', 'possessive (of)'),
    ('नित्यसम्बन्धः', 'other', 'నిత్య సంబంధం — "యత్… తత్" జంట', 'correlative pair'),
    ('उपपदसम्बन्धः', 'other', 'ఉపపద సంబంధం — పక్క పదం కోరే విభక్తి', 'case required by a nearby word'),
    ('विशेषणम्', 'other', 'విశేషణం — గుణం తెలిపేది', 'qualifier (adjective)'),
    ('विधेय_विशेषणम्', 'other', 'విధేయ విశేషణం — చెప్పబడే గుణం', 'predicate adjective'),
    ('कर्तृसमानाधिकरणम्', 'other', 'కర్తృ సమానాధికరణం — కర్తను గురించి చెప్పేది', 'complement of the agent'),
    ('कर्मसमानाधिकरणम्', 'other', 'కర్మ సమానాధికరణం — కర్మను గురించి చెప్పేది', 'complement of the object'),
    ('क्रियाविशेषणम्', 'other', 'క్రియా విశేషణం — పని ఎలా జరిగిందో', 'adverb'),
    ('प्रतिषेधः', 'other', 'ప్రతిషేధం — "కాదు"', 'negation'),
    ('सम्बोध्यः', 'other', 'సంబోధ్యం — పిలువబడేవారు', 'person addressed'),
    ('पूर्वकालः', 'other', 'పూర్వకాలం — ముందు జరిగిన పని ("చేసి")', 'earlier action (having done)'),
    ('वर्तमानसमानकालः', 'other', 'సమానకాలం — అదే సమయంలో ("చేస్తూ")', 'simultaneous action (while)'),
    ('समानकालः', 'other', 'సమానకాలం — అదే సమయంలో ("చేస్తూ")', 'simultaneous action (while)'),
    ('भावलक्षणसप्तमी', 'other', 'భావలక్షణ సప్తమి — "…జరుగుతుండగా"', 'locative absolute'),
    ('भावलक्षणसप्तमी_पूर्वकालः', 'other', 'భావలక్షణ సప్తమి — "…జరిగిన తరువాత"', 'locative absolute (after)'),
    ('भावलक्षणसप्तमी_समानकालः', 'other', 'భావలక్షణ సప్తమి — "…జరుగుతుండగా"', 'locative absolute (while)'),
    ('हेतुः', 'other', 'హేతువు — కారణం', 'cause'),
    ('प्रयोजनम्', 'other', 'ప్రయోజనం — దేని కొరకు', 'purpose'),
    ('निर्धारणम्', 'other', 'నిర్ధారణం — ఏ సమూహం నుండి ఎంచబడిందో', 'group singled out from'),
    ('विभक्तम्', 'other', 'విభక్తం — దేని నుండి వేరుగా', 'distinguished from'),
    ('समुच्चितः', 'other', 'సముచ్చితం — "మరియు"తో కలిసినది', 'joined by "and"'),
    ('सुप्समुच्चितम्', 'other', 'సముచ్చితం — "మరియు"తో కలిసినది', 'joined by "and"'),
    ('समुच्चय_द्योतकः', 'other', 'సముచ్చయ ద్యోతకం — "చ" (మరియు)', '"and" marker'),
    ('अन्यतरः', 'other', 'అన్యతరం — "లేదా"తో కలిసినది', 'alternative (or)'),
    ('अन्यतर_द्योतकः', 'other', 'అన్యతర ద్యోతకం — "వా" (లేదా)', '"or" marker'),
    ('घटकः', 'other', 'ఘటకం — "యది… తర్హి" వంటి జంటలో భాగం', 'part of a correlative pair'),
    ('घटक_द्योतकः', 'other', 'ఘటక ద్యోతకం — జంటను తెలిపే పదం', 'correlative marker'),
    ('वाक्यकर्म', 'other', 'వాక్య కర్మ — కర్మగా ఉన్న వాక్యం', 'clause as object'),
    ('वाक्यकर्म_द्योतकः', 'other', 'వాక్యకర్మ ద్యోతకం — "ఇతి"', 'quotation marker (iti)'),
    ('वाक्यार्थ_द्योतकः', 'other', 'వాక్యార్థ ద్యోతకం', 'clause marker'),
    ('कर्म_द्योतकः', 'other', 'కర్మ ద్యోతకం', 'object marker'),
    ('तुमुन्कर्म', 'other', 'తుమున్ కర్మ — "చేయడానికి"', 'infinitive as object'),
    ('उपमानम्', 'other', 'ఉపమానం — దేనితో పోల్చబడిందో', 'standard of comparison'),
    ('उपमान_द्योतकः', 'other', 'ఉపమాన ద్యోతకం — "ఇవ" (లాగ)', 'comparison marker (like)'),
    ('उपमा_द्योतकः', 'other', 'ఉపమాన ద్యోతకం — "ఇవ" (లాగ)', 'comparison marker (like)'),
    ('उत्प्रेक्षा', 'other', 'ఉత్ప్రేక్ష — "ఉన్నట్లు"', 'as if'),
    ('उत्प्रेक्षा_द्योतकः', 'other', 'ఉత్ప్రేక్ష ద్యోతకం — "ఇవ" (ఉన్నట్లు)', '"as if" marker'),
    ('तुलना_बिन्दुः', 'other', 'తులనా బిందువు — దేనిలో పోలిక', 'point of comparison'),
    ('सन्दर्भ_बिन्दुः', 'other', 'సందర్భ బిందువు', 'point of reference'),
    ('वीप्सा', 'other', 'వీప్స — మళ్ళీ మళ్ళీ', 'repetition'),
    ('सहार्थः', 'other', 'సహార్థం — "తో కూడా"', 'accompaniment (with)'),
    ('सहार्थ_द्योतकः', 'other', 'సహార్థ ద్యోతకం — "సహ"', '"with" marker'),
    ('विनार्थः', 'other', 'వినార్థం — "లేకుండా"', 'without'),
    ('विनार्थ_द्योतकः', 'other', 'వినార్థ ద్యోతకం — "వినా"', '"without" marker'),
    ('अभेदः', 'other', 'అభేదం — ఒకటే అని', 'identity'),
    ('प्रतियोगी', 'other', 'ప్రతియోగి', 'counterpart'),
    ('अनुयोगी', 'other', 'అనుయోగి', 'correlate'),
    ('आवश्यकता_द्योतकः', 'other', 'ఆవశ్యకత ద్యోతకం — తప్పనిసరి', 'necessity marker'),
    ('कार्य_द्योतकः', 'other', 'కార్య ద్యోతకం — ఫలితం', 'effect marker'),
    ('कारण_द्योतकः', 'other', 'కారణ ద్యోతకం', 'cause marker'),
    ('परिणाम', 'other', 'పరిణామం — ఫలితం', 'result'),
    ('परिणाम_द्योतकः', 'other', 'పరిణామ ద్యోతకం', 'result marker'),
    ('प्रयोजन_द्योतकः', 'other', 'ప్రయోజన ద్యోతకం — "కొరకు"', 'purpose marker'),
    ('सम्बोधन_द्योतकः', 'other', 'సంబోధన ద్యోతకం — "హే"', 'vocative marker'),
    ('व्यभिचार_द्योतकः', 'other', 'వ్యభిచార ద్యోతకం — మినహాయింపు', 'exception marker'),
    ('सञ्ज्ञा', 'other', 'సంజ్ఞ — పేరు', 'name'),
    ('सञ्ज्ञा_द्योतकः', 'other', 'సంజ్ఞా ద్యోతకం — "ఇతి" (అని)', 'naming marker'),
    ('तीव्रतादर्शी', 'other', 'తీవ్రతాదర్శి — ఎంత ఎక్కువో', 'intensifier'),
    ('सहायकक्रिया', 'other', 'సహాయక క్రియ', 'auxiliary verb'),
    ('कर्मप्रवचनीयः', 'other', 'కర్మప్రవచనీయం', 'governing particle'),
    ('कर्मप्रवचनीय_अन्वितः', 'other', 'కర్మప్రవచనీయంతో అన్వయం', 'governed by a particle'),
    ('बहुव्रीहिः', 'samasa', 'బహువ్రీహి — మరొకరిని వర్ణించే సమాసం', 'bahuvrīhi (possessive compound)'),
    ('नञ्-बहुव्रीहिः', 'samasa', 'నఞ్ బహువ్రీహి — "లేనివారు"', 'negative bahuvrīhi'),
    ('तत्पुरुषः', 'samasa', 'తత్పురుష సమాసం', 'tatpuruṣa compound'),
    ('द्वितीया-तत्पुरुषः', 'samasa', 'ద్వితీయా తత్పురుష ("ని, ను")', 'accusative tatpuruṣa'),
    ('तृतीया-तत्पुरुषः', 'samasa', 'తృతీయా తత్పురుష ("చేత, తో")', 'instrumental tatpuruṣa'),
    ('चतुर्थी-तत्पुरुषः', 'samasa', 'చతుర్థీ తత్పురుష ("కొరకు")', 'dative tatpuruṣa'),
    ('पञ्चमी-तत्पुरुषः', 'samasa', 'పంచమీ తత్పురుష ("నుండి")', 'ablative tatpuruṣa'),
    ('षष्ठी-तत्पुरुषः', 'samasa', 'షష్ఠీ తత్పురుష ("యొక్క")', 'genitive tatpuruṣa'),
    ('सप्तमी-तत्पुरुषः', 'samasa', 'సప్తమీ తత్పురుష ("లో")', 'locative tatpuruṣa'),
    ('नञ्-तत्पुरुषः', 'samasa', 'నఞ్ తత్పురుష — "అ / అన్" (కాని)', 'negative compound'),
    ('उपपद-तत्पुरुषः', 'samasa', 'ఉపపద తత్పురుష — "…చేసేవాడు"', 'upapada compound'),
    ('प्रादि-तत्पुरुषः', 'samasa', 'ప్రాది తత్పురుష — ఉపసర్గతో', 'prefix compound'),
    ('द्विगु-तत्पुरुषः', 'samasa', 'ద్విగు — సంఖ్యతో', 'numeral compound'),
    ('कर्मधारयः', 'samasa', 'కర్మధారయం — విశేషణ విశేష్యాల సమాసం', 'descriptive compound'),
    ('द्वन्द्वः', 'samasa', 'ద్వంద్వ సమాసం', 'copulative compound'),
    ('इतरेतर-द्वन्द्वः', 'samasa', 'ఇతరేతర ద్వంద్వం — "మరియు" జంట', 'copulative compound'),
    ('समाहार-द्वन्द्वः', 'samasa', 'సమాహార ద్వంద్వం — సమూహం', 'collective compound'),
    ('अव्ययीभावः', 'samasa', 'అవ్యయీభావం — అవ్యయంగా మారే సమాసం', 'adverbial compound'),
    ('केवल-समासः', 'samasa', 'కేవల సమాసం', 'simple compound'),
]

# Spellings found in the data for the relations above.
ALIASES = {
    'अभिहितकर्ता': 'अभिहित_कर्ता', 'अभिहिताकर्ता': 'अभिहित_कर्ता', 'अभिहिता_कर्ता': 'अभिहित_कर्ता',
    'अभिहिता': 'अभिहित_कर्ता', 'अभिहितकर्म': 'अभिहित_कर्म', 'अभिहिततकर्म': 'अभिहित_कर्म',
    'कर्ता_बे_वर्ब्स': 'कर्ता', 'कर्ता_बे_वेर्ब्स्': 'कर्ता', 'कर्म्': 'कर्म',
    'षष्ठीसंबन्धः': 'षष्ठीसम्बन्धः', 'विशेषणम': 'विशेषणम्', 'कालाधिकरण्': 'कालाधिकरणम्',
    'द्वन्दः': 'द्वन्द्वः', 'इतरेतर-द्वन्दः': 'इतरेतर-द्वन्द्वः', 'तॄतीया-तत्पुरुषः': 'तृतीया-तत्पुरुषः',
    'पञ्च-तत्पुरुषः': 'पञ्चमी-तत्पुरुषः', 'उपपदसमासः': 'उपपद-तत्पुरुषः', 'प्रादि-समासः': 'प्रादि-तत्पुरुषः',
    'बहुव्रीहि': 'बहुव्रीहिः', 'वर्तमानसमानसमानकालः': 'वर्तमानसमानकालः', 'सहार्धः': 'सहार्थः',
    'घटकद्योतकः': 'घटक_द्योतकः', 'घटकः_द्योतकः': 'घटक_द्योतकः', 'घटक': 'घटकः',
    'समुच्चितम्': 'समुच्चितः', 'सुप्_समुच्चितः': 'सुप्समुच्चितम्', 'सुप्-समुच्चितः': 'सुप्समुच्चितम्',
    'समु्च्चय_द्योतकः': 'समुच्चय_द्योतकः', 'कर्मद्योतकः': 'कर्म_द्योतकः', 'विशेेषणम्': 'विशेषणम्',
    'वााक्यकर्म': 'वाक्यकर्म',
}

TAGS = {
    'पुं': ('पुंलिङ्गम्', 'పుంలింగం'), 'स्त्री': ('स्त्रीलिङ्गम्', 'స్త్రీలింగం'), 'नपुं': ('नपुंसकलिङ्गम्', 'నపుంసకలింగం'),
    '1': ('प्रथमा', 'ప్రథమా విభక్తి'), '2': ('द्वितीया', 'ద్వితీయా విభక్తి (ని, ను)'),
    '3': ('तृतीया', 'తృతీయా విభక్తి (చేత, తో)'), '4': ('चतुर्थी', 'చతుర్థీ విభక్తి (కొరకు)'),
    '5': ('पञ्चमी', 'పంచమీ విభక్తి (వలన, నుండి)'), '6': ('षष्ठी', 'షష్ఠీ విభక్తి (యొక్క)'),
    '7': ('सप्तमी', 'సప్తమీ విభక్తి (అందు, లో)'), '8': ('सम्बोधनम्', 'సంబోధన (ఓ, హే)'),
    'एक': ('एकवचनम्', 'ఏకవచనం'), 'द्वि': ('द्विवचनम्', 'ద్వివచనం'), 'बहु': ('बहुवचनम्', 'బహువచనం'),
    'प्र': ('प्रथमपुरुषः', 'ప్రథమ పురుష (అతడు, వారు)'), 'म': ('मध्यमपुरुषः', 'మధ్యమ పురుష (నీవు)'),
    'उ': ('उत्तमपुरुषः', 'ఉత్తమ పురుష (నేను, మేము)'),
    'कर्तरि': ('कर्तरि', 'కర్తరి ప్రయోగం'), 'कर्मणि': ('कर्मणि', 'కర్మణి ప్రయోగం'), 'भावे': ('भावे', 'భావే ప్రయోగం'),
    'परस्मैपदी': ('परस्मैपदम्', 'పరస్మైపదం'), 'आत्मनेपदी': ('आत्मनेपदम्', 'ఆత్మనేపదం'),
    'उभयपदी': ('उभयपदम्', 'ఉభయపదం'),
    'लट्': ('लट्', 'వర్తమాన కాలం'), 'लिट्': ('लिट्', 'పరోక్ష భూతకాలం'), 'लुट्': ('लुट्', 'భవిష్యత్ (దూరం)'),
    'लृट्': ('लृट्', 'భవిష్యత్ కాలం'), 'लोट्': ('लोट्', 'ఆజ్ఞార్థం'), 'लङ्': ('लङ्', 'భూతకాలం'),
    'विधिलिङ्': ('विधिलिङ्', 'విధ్యర్థం (చేయవలెను)'), 'आशीर्लिङ्': ('आशीर्लिङ्', 'ఆశీర్వాదార్థం'),
    'लुङ्': ('लुङ्', 'భూతకాలం (లుఙ్)'), 'लृङ्': ('लृङ्', 'సంకేతార్థం (చేసి ఉండేవాడు)'),
    'अव्य': ('अव्ययम्', 'అవ్యయం'), 'अव्य्': ('अव्ययम्', 'అవ్యయం'),
    'सर्वनाम': ('सर्वनाम', 'సర్వనామం'), 'सर्व': ('सर्वनाम', 'సర్వనామం'),
    'अ': ('अलिङ्गम्', 'లింగం లేదు'), 'संख्येयम्': ('संख्येयम्', 'సంఖ్యా పదం'),
    'क्त': ('क्त', 'భూత కృదంతం ("చేయబడిన")'), 'क्तवतु': ('क्तवतु', 'భూత కృదంతం ("చేసిన")'),
    'शतृ': ('शतृ', 'వర్తమాన కృదంతం ("చేస్తున్న")'), 'शानच्': ('शानच्', 'వర్తమాన కృదంతం ("చేస్తున్న")'),
    'क्त्वा': ('क्त्वा', '"చేసి"'), 'ल्यप्': ('ल्यप्', '"చేసి" (ఉపసర్గతో)'), 'तुमुन्': ('तुमुन्', '"చేయడానికి"'),
    'तव्यत्': ('तव्यत्', '"చేయదగిన"'), 'अनीयर्': ('अनीयर्', '"చేయదగిన"'), 'यत्': ('यत्', '"చేయదగిన"'),
    'ण्यत्': ('ण्यत्', '"చేయదగిన"'), 'क्यप्': ('क्यप्', '"చేయదగిన"'),
    'घञ्': ('घञ्', 'క్రియా నామం'), 'ल्युट्': ('ल्युट्', 'క్రియా నామం'), 'तृच्': ('तृच्', '"చేసేవాడు"'),
    'णिच्': ('णिच्', 'ప్రేరణార్థకం (చేయించు)'), 'सन्': ('सन्', 'ఇచ్ఛార్థకం (చేయాలనుకొను)'),
    'यङ्': ('यङ्', 'మళ్ళీ మళ్ళీ చేయు'), 'नामधातु': ('नामधातु', 'నామం నుండి క్రియ'),
    'मतुप्': ('मतुप्', '"…కలవాడు"'), 'इनि': ('इनि', '"…కలవాడు"'), 'त्व': ('त्व', '"…తనం"'),
    'तल्': ('तल्', '"…తనం"'), 'तसिल्': ('तसिल्', '"…నుండి"'),
    'भ्वादिः': ('भ्वादिः', 'భ్వాది గణం (1)'), 'अदादिः': ('अदादिः', 'అదాది గణం (2)'),
    'जुहोत्यादिः': ('जुहोत्यादिः', 'జుహోత్యాది గణం (3)'), 'दिवादिः': ('दिवादिः', 'దివాది గణం (4)'),
    'स्वादिः': ('स्वादिः', 'స్వాది గణం (5)'), 'तुदादिः': ('तुदादिः', 'తుదాది గణం (6)'),
    'रुधादिः': ('रुधादिः', 'రుధాది గణం (7)'), 'तनादिः': ('तनादिः', 'తనాది గణం (8)'),
    'क्र्यादिः': ('क्र्यादिः', 'క్ర్యాది గణం (9)'), 'चुरादिः': ('चुरादिः', 'చురాది గణం (10)'),
}

ZW = re.compile('[\u200b\u200c\u200d\u00a0]')


def relation_key(name):
    """Same as relationKey in web/analysis.js and GitaAnalysis.swift."""
    s = ZW.sub('', name)
    s = re.sub(r'[\s_.\-\d]', '', s)
    return re.sub(r'ः$', '', s)


def tsv_names_github():
    url = f'https://api.github.com/repos/{REPO}/git/trees/{COMMIT}?recursive=1'
    with urllib.request.urlopen(url, timeout=60) as r:
        tree = json.load(r)
    if tree.get('truncated'):
        sys.exit('GitHub listing was truncated; use --local with a clone instead.')
    prefix = DIR + '/'
    return [t['path'][len(prefix):] for t in tree['tree']
            if t['type'] == 'blob' and t['path'].startswith(prefix) and t['path'].endswith('.tsv')]


def verse_files(names):
    """{"1:12": ["01_012_1"], "1:28": ["01_027_2-028_1", "01_028_2-029_1"], ...}"""
    stems = {n[:-4] for n in names}
    picked = []
    for stem in sorted(stems):
        base = re.sub(r' \(\d+\)$', '', stem)
        if base != stem and base in stems:
            continue  # a second upload of the same verse
        m = re.match(r'^(\d+)_(.+)$', base)
        if not m:
            continue
        chapter = int(m.group(1))
        nums = re.findall(r'\d+', m.group(2))
        verses = [int(n) for n in nums if len(n) >= 2]
        if not verses:
            continue
        if any(len(n) == 2 for n in nums if len(n) >= 2):
            fixed = f'{chapter:02d}_' + '_'.join(f'{int(n):03d}' if len(n) >= 2 else n for n in nums)
            if fixed in stems:
                continue  # "10_06_2" next to "10_006_2"
        lo, hi = min(verses), max(verses)
        # "027_2-028_1" starts with the second part of verse 27.
        first_part = int(re.match(r'\d+(?:_(\d)(?!\d))?', m.group(2)).group(1) or 1)
        picked.append((chapter, lo, first_part, stem, range(lo, hi + 1)))
    index = collections.defaultdict(list)
    for chapter, lo, first_part, stem, covered in sorted(picked):
        for v in covered:
            index[f'{chapter}:{v}'].append(stem)
    return dict(sorted(index.items(), key=lambda kv: tuple(int(x) for x in kv[0].split(':'))))


def check(local_dir, names):
    known = {relation_key(n) for n, *_ in RELATIONS} | {relation_key(a) for a in ALIASES}
    unknown = collections.Counter()
    for name in names:
        lines = open(os.path.join(local_dir, name), encoding='utf-8-sig').read().splitlines()
        head = [h.strip().lower() for h in lines[0].split('\t')]
        col = next((i for i, h in enumerate(head) if h.startswith('kaaraka_sambandha')), None)
        for line in lines[1:]:
            cells = line.split('\t')
            if col is None or col >= len(cells) or not cells[0].strip():
                continue
            rel = cells[col].split(';')[0].partition(',')[0].strip()
            key = relation_key(rel)
            if key and key not in known:
                unknown[rel] += 1
    for rel, n in unknown.most_common():
        print(f'unknown relation: {rel} ({n})', file=sys.stderr)
    return not unknown


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--local', help=f'a clone of {REPO} (at commit {COMMIT[:7]})')
    ap.add_argument('--check', action='store_true', help='report relation names with no Telugu explanation')
    args = ap.parse_args()

    if args.local:
        local_dir = os.path.join(os.path.expanduser(args.local), DIR)
        names = [os.path.basename(p) for p in glob.glob(os.path.join(local_dir, '*.tsv'))]
    else:
        names = tsv_names_github()
    verses = verse_files(names)

    relations = {}
    for sa, kind, te, en in RELATIONS:
        relations[relation_key(sa)] = {'sa': sa.replace('_', ' '), 'kind': kind, 'te': te, 'en': en}
    aliases = {relation_key(k): relation_key(v) for k, v in ALIASES.items()}
    tags = {k: {'sa': sa, 'te': te} for k, (sa, te) in TAGS.items()}

    data = {
        'source': {
            'name': 'Samsaadhanii, University of Hyderabad',
            'repo': REPO, 'commit': COMMIT, 'dir': DIR,
            'url': f'https://raw.githubusercontent.com/{REPO}/{COMMIT}/{DIR}/',
            'credit': 'Word analysis and kāraka relations: Samsaadhanii (Department of Sanskrit Studies, '
                      'University of Hyderabad; Amba Kulkarni and team), downloaded from '
                      'github.com/samsaadhanii/ereaders.',
        },
        'verses': verses,
        'relations': relations,
        'aliases': aliases,
        'tags': tags,
    }
    for out in OUTPUTS:
        with open(out, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
            f.write('\n')
    files = {f for fs in verses.values() for f in fs}
    print(f'{len(verses)} verses in {len(files)} files; wrote {", ".join(os.path.relpath(o, ROOT) for o in OUTPUTS)}')
    if args.check and args.local and not check(local_dir, sorted(f + '.tsv' for f in files)):
        sys.exit(1)


if __name__ == '__main__':
    main()
