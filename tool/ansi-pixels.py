#!/usr/bin/python

import sys, base64, zlib, json, types

def main(argv) :
    if len(argv) == 1:
        sys.exit('Require an argument')

    p = convert(argv[1])
    for row in p:
        for code in row:
            sys.stdout.write('%s  ' % ansi_color(code))
        print(ansi_color(None))

def convert(b64):
    zipped = base64.urlsafe_b64decode(b64)
    json_str = zlib.decompress(zipped)
    j = json.loads(json_str)
    if type(j) is types.DictType:
        return j['pixels']
    elif type(j) is types.ListType:
        return j
    else:
        sys.exit('Invalid JSON: %s' % type(j))

def ansi_color(code):
    if code == None:
        return '\033[0m'
    else:
        return '\033[48;5;%dm' % code

main(sys.argv)
