#!/usr/bin/env python

import os, stat
import sys
from subprocess import call

def walk(dir):
    try:
        for child in os.listdir(dir):
            child= os.path.join(dir, child)
            if os.path.isdir(child):
                for descendant in walk(child):
                    yield descendant
            yield child
    except OSError, e:
        print >>sys.stderr, "Error accessing dir:", e

def check(p):
    for path in walk(p):
        try:
            u= unicode(path, 'utf-8')
        except UnicodeError:
            print "CODES:",path
        if not bool(os.stat(path).st_mode & stat.S_IROTH):
            print "PERMS:",path
            call("chmod -R u=rwX,g=rX,o=rX".split() + [path])
        if os.path.isdir(path) and not bool(os.stat(path).st_mode & stat.S_IXOTH):
            print "DPERMS:",path
            call("chmod -R u=rwX,g=rX,o=rX".split() + path)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print >>sys.stderr, "Usage: %s /path/to/check" % sys.argv[0]
        print >>sys.stderr, "Then: chmod -R o=rX /path/to/check"
        exit(1)
    check(sys.argv[1])
