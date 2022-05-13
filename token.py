#!/usr/bin/env python3

import urllib.request
import re
from collections import OrderedDict
import re
import json
import sys

# Copied from https://github.com/alexdutton/www-authenticate
# Copyright (c) 2015 Alexander Dutton.
# All rights reserved.

# Redistribution and use in source and binary forms are permitted
# provided that the above copyright notice and this paragraph are
# duplicated in all such forms and that any documentation,
# advertising materials, and other materials related to such
# distribution and use acknowledge that the software was developed
# by the Alexander Dutton. The name of the Alexander Dutton may not
# be used to endorse or promote products derived from this software
# without specific prior written permission.
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
_tokens = (
    ('token', re.compile(r'''^([!#$%&'*+\-.^_`|~\w/]+(?:={1,2}$)?)''')),
    ('token', re.compile(r'''^"((?:[^"\\]|\\\\|\\")+)"''')),
    (None, re.compile(r'^\s+')),
    ('equals', re.compile(r'^(=)')),
    ('comma', re.compile(r'^(,)')),
)

def _casefold(value):
    try:
        return value.casefold()
    except AttributeError:
        return value.lower()

class CaseFoldedOrderedDict(OrderedDict):
    def __getitem__(self, key):
        return super(CaseFoldedOrderedDict, self).__getitem__(_casefold(key))

    def __setitem__(self, key, value):
        super(CaseFoldedOrderedDict, self).__setitem__(_casefold(key), value)

    def __contains__(self, key):
        return super(CaseFoldedOrderedDict, self).__contains__(_casefold(key))

    def get(self, key, default=None):
        return super(CaseFoldedOrderedDict, self).get(_casefold(key), default)

    def pop(self, key, default=None):
        return super(CaseFoldedOrderedDict, self).pop(_casefold(key), default)

def _group_pairs(tokens):
    i = 0
    while i < len(tokens) - 2:
        if tokens[i][0] == 'token' and \
           tokens[i+1][0] == 'equals' and \
           tokens[i+2][0] == 'token':
            tokens[i:i+3] = [('pair', (tokens[i][1], tokens[i+2][1]))]
        i += 1

def _group_challenges(tokens):
    challenges = []
    while tokens:
        j = 1
        if len(tokens) == 1:
            pass
        elif tokens[1][0] == 'comma':
            pass
        elif tokens[1][0] == 'token':
            j = 2
        else:
            while j < len(tokens) and tokens[j][0] == 'pair':
                j += 2
            j -= 1
        challenges.append((tokens[0][1], tokens[1:j]))
        tokens[:j+1] = []
    return challenges

def parse(value):
    tokens = []
    while value:
        for token_name, pattern in _tokens:
            match = pattern.match(value)
            if match:
                value = value[match.end():]
                if token_name:
                    tokens.append((token_name, match.group(1)))
                break
        else:
             raise ValueError("Failed to parse value")
    _group_pairs(tokens)

    challenges = CaseFoldedOrderedDict()
    for name, tokens in _group_challenges(tokens):
        args, kwargs = [], {}
        for token_name, value in tokens:
            if token_name == 'token':
                args.append(value)
            elif token_name == 'pair':
                kwargs[value[0]] = value[1]
        challenges[name] = (args and args[0]) or kwargs or None

    return challenges

# Registry Auth

def get_auth_realm(uri):
    try:
        response = urllib.request.urlopen(uri)
    except urllib.error.URLError as e:
        if e.code != 401:
            raise e
        realm = parse(e.headers['WWW-Authenticate'])['Bearer']['realm']
        return realm

    return None

def get_auth_token_for_registry(registry):
    realm = get_auth_realm('https://{}/v2/'.format(registry))
    if realm == None:
        return None

    response = urllib.request.urlopen(realm)
    return json.loads(response.read())

print(get_auth_token_for_registry(sys.argv[1]))
