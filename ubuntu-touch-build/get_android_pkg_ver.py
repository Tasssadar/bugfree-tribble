#!/usr/bin/python
import requests, string, os, re, datetime, sys
from BeautifulSoup import *

PKG_URL="http://packages.ubuntu.com/trusty/android"

def main(argc, argv):
    req = requests.get(PKG_URL)
    if req.status_code != 200:
        sys.stderr.write("requests.get failed with status code " + str(req.status_code))
        return 1

    soup = BeautifulSoup(req.text)
    content_div = soup.find(id="content")
    if not content_div:
        sys.stderr.write("Failed to find <div id=\"content\">!")
        return 1

    title = content_div.find("h1")
    if not title:
        sys.stderr.write("Failed to find <h1>!")
        return 1

    # Package: android (20140228-2008-0ubuntu1)\n [multiverse]
    expr = re.compile('^Package: android \\(([0-9]{8})-([0-9]{4})-\\w*\\).*\n.*$')
    m = expr.match(title.text)
    if not m or len(m.groups()) < 2:
        sys.stderr.write("Failed to match regexp!")
        return 1

    pkg_date = datetime.datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M")
    # uncodumented feature on linux systems - %s - print timestamp
    print pkg_date.strftime("%s")
    return 0

if __name__ == "__main__":
   exit(main(len(sys.argv), sys.argv))