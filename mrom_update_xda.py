#!/usr/bin/python

import sys
import datetime
import json
import string
import requests
import dhst_cli
import xdaapi
import re

MANIFEST_URL = "http://tasemnice.eu/multirom/manifest.json"
MULTIROM_DIR = "/home/tassadar/nexus/multirom/"
CONFIG_PATH = MULTIROM_DIR + "config.json"

class RemoteManifest:
    def __init__(self, url):
        res = requests.get(url)
        self.data = json.loads(res.text)

    def __getitem__(self, k):
        return self.data[k]

    def __contains__(self, elt):
        return (elt in self.data)

    def get_files(self, dev_name, ftype):
        res = []
        for dev in self.data["devices"]:
            if dev_name == dev["name"]:
                for f in dev["files"]:
                    if ftype == f["type"]:
                        res.append(f)
        return res

    def get_file(self, dev_name, ftype):
        res = self.get_files(dev_name, ftype)
        if len(res) == 0:
            return None
        return res[0]

    def has_device(self, dev_name):
         for dev in self.data["devices"]:
             if dev_name == dev["name"]:
                 return True
         return False

class FirstPostTitleGenerator():
    re_multirom = re.compile('^multirom-([0-9]{8})-v([0-9]{1,3})([a-z]?)-[a-z]*\.zip$')
    re_recovery = re.compile('^TWRP_multirom_([a-z]*)_([0-9]{8})(-[0-9]{2})?\.img$')

    def __init__(self, cfg_dev):
        self.date = None
        self.files = { }
        if "title_summary" in cfg_dev["xda"]:
            self.title_summary = " (%s)" % cfg_dev["xda"]["title_summary"]
        else:
            self.title_summary = ""

    def get_file_date(self, f):
        if f["type"] == "recovery":
            r = self.re_recovery.match(f["filename"])
            return datetime.datetime.strptime(r.group(2), "%Y%m%d")
        elif f["type"] == "multirom":
            r = self.re_multirom.match(f["filename"])
            return datetime.datetime.strptime(r.group(1), "%Y%m%d")
        else:
            return None

    def add_file(self, f):
        if f["type"] in self.files:
            new_date = self.get_file_date(f)
            old_date = self.get_file_date(self.files[f["type"]])
            if new_date < old_date:
                return

        self.files[f["type"]] = f

    def get_highest_date(self):
        res = datetime.datetime.min;
        for f in self.files.itervalues():
            f_date = self.get_file_date(f)
            if f_date > res:
                res = f_date
        return res

    def generate_title(self):
        date = self.get_highest_date()
        return "[MOD][%s] MultiROM %s%s" % (
            date.strftime("%b %d").upper(),
            self.files["multirom"]["version"],
            self.title_summary
        )

class SecondPostGenerator():
    url_re = re.compile("http.?://[^ )\\n]*")

    def __init__(self, cfg_dev, manifest, dhst_session):
        self.cfg_dev = cfg_dev
        self.manifest = manifest

        dhst_api = dhst_cli.DevHostAPI()
        dhst_api.session_token = dhst_session
        self.dhst_files = dhst_api.get_folder_content("multirom/%s" % cfg_dev["name"])

        self.multirom = manifest.get_file(cfg_dev["name"], "multirom")
        self.recovery = manifest.get_file(cfg_dev["name"], "recovery")
        self.kernels = manifest.get_files(cfg_dev["name"], "kernel")

        [ self.man_file_add_filename(f) for f in [ self.multirom, self.recovery ] + self.kernels ]

    def man_file_add_filename(self, f):
        u = f["url"]
        f["filename"] = u[u.rfind("/")+1:]
        return f

    def find_dhst_link(self, filename):
        for f in self.dhst_files:
            if f["name"] == filename:
                return f["url"]
        raise Exception("Couldn't find file %s in dev-host folder!\n" % filename)

    def generate_downloads(self, title_gen):
        res = '[INDENT][COLOR="Blue"][b] 1. Main downloads[/b][/COLOR]\n\n'
        # multirom
        title_gen.add_file(self.multirom)
        res += "[B]MultiROM:[/B] [URL=%s]%s[/url]\n" % (
                    self.find_dhst_link(self.multirom["filename"]),
                    self.multirom["filename"]
                )
        # recovery
        title_gen.add_file(self.recovery)
        res += "[B]Modified recovery (based on TWRP):[/B] [URL=%s]%s[/url]" % (
                    self.find_dhst_link(self.recovery["filename"]),
                    self.recovery["filename"]
                )
        if "variants" in self.cfg_dev:
            res += " (%s)" % self.cfg_dev["name"]
            for var in self.cfg_dev["variants"]:
                if var["override"].find("recovery") == -1:
                    continue
                var_rec = self.manifest.get_file(var["name"], "recovery")
                self.man_file_add_filename(var_rec)
                title_gen.add_file(var_rec)
                res += " or [URL=%s]%s[/url] (%s)" % (
                            self.find_dhst_link(var_rec["filename"]),
                            var_rec["filename"],
                            var["name"]
                        )
        res += "\n"
        # MutliROM Manager
        res += (
            '[B]MultiROM Manager Android app[/b]: [url=https://play.google.com/store/apps/details?id=com.tassadar.multirommgr]Google Play[/url] '
            'or [url=http://d-h.st/users/tassadar/?fld_id=27952#files]link to APK[/url]\n\n'
        )
        # kernels
        for k in self.kernels:
            res += '[b]Kernel w/ kexec-hardboot patch (%s):[/b] [url=%s]%s[/url]\n' % (
                        k["version"],
                        self.find_dhst_link(k["filename"]),
                        k["filename"]
                    )

        # footer
        res += (
            '[COLOR="Red"]You need to have kernel with kexec-hardboot patch in both primary ROM and secondary ROMs, if said secondary ROM does not share kernel![/COLOR]\n\n'
            'Mirror: [url]http://goo.im/devs/Tassadar/multirom/%s/[/url] (also accessible via GooManager, search for [i]multirom[/i])[/INDENT]' % self.cfg_dev["name"]
        )
        return res

    def get_changelog_file(self, ctype):
        ctype = ctype.upper()
        for c in self.cfg_dev["changelogs"]:
            if c["name"].upper() == ctype:
                return "%s%s/%s" % ( MULTIROM_DIR, self.cfg_dev["name"], c["file"])

    def convert_urls(self, line):
        pos = 0
        while True:
            m=self.url_re.search(line, pos)
            if not m:
                break
            url = "[url]%s[/url]" % m.group()
            line = line[:m.start()] + url + line[m.end():]
            pos = m.start() + len(url)
        return line

    def generate_changelog(self, path):
        with open(path, "r") as f:
            res = "[code]\n"
            for line in f:
                while len(line) >= 80:
                    split_idx = line.rfind(" ", 0, 79)
                    if split_idx < 3:
                        break
                    res += self.convert_urls(line[:split_idx]) + "\n"
                    line = "  %s" % line[split_idx+1:]
                res += self.convert_urls(line)
            res += "[/code]\n"
            return res

    def generate_changelogs(self):
        multirom = self.get_changelog_file("multirom")
        recovery = self.get_changelog_file("recovery")
        res = '[u][SIZE="5"][B]Changelog[/B][/SIZE][/u]\n'
        res += self.generate_changelog(multirom)
        res += '\n\n[b][color=red]Recoveries:[/color][/b]\n'
        res += self.generate_changelog(recovery)
        return res

def update_second_post(api, cfg_dev, manifest, dhst_session, title_gen):
    gen = SecondPostGenerator(cfg_dev, manifest, dhst_session)
    post = api.get_raw_post(cfg_dev["xda"]["second_post"])

    new_post = post["post_content"].data.replace("\r", "")
    # replace main downloads
    downloads_start = new_post.find('[INDENT][COLOR="Blue"][b] 1. Main downloads[/b][/COLOR]')
    downloads_end = new_post.upper().find('[/INDENT]', downloads_start)
    if downloads_start == -1 or downloads_end == -1:
        raise Exception("Failed to find 'Main downloads' in the %s post" % cfg_dev["name"])
    downloads_end += len("[/INDENT]")
    downloads = gen.generate_downloads(title_gen)
    new_post = new_post[:downloads_start] + downloads + new_post[downloads_end:]

    # replace changelogs
    changelogs_start = new_post.find('[u][SIZE="5"][B]Changelog[/B][/SIZE][/u]')
    if changelogs_start == -1:
        raise Exception("Failed to find changelogs in the %s post" % cfg_dev["name"])
    changelogs = gen.generate_changelogs()
    new_post = new_post[:changelogs_start] + changelogs

    # edit the post
    api.save_raw_post(post["post_id"], post["post_title"].data, new_post)

def update_first_post(api, cfg_dev, title_gen):
    post = api.get_raw_post(cfg_dev["xda"]["first_post"])
    title = title_gen.generate_title()
    api.save_raw_post(post["post_id"], title, post["post_content"].data.replace("\r", ""))

def main(argc, argv):
    i = 1
    user=""
    password=""
    device=""
    dhst_session=""

    while i < argc:
        if argv[i] == "-u":
            i+=1
            user = argv[i]
        elif argv[i] == "-p":
            i+=1
            password = argv[i]
        elif argv[i] == "-d":
            i+=1
            device = argv[i]
        elif argv[i] == "-s":
            i+=1
            dhst_session = argv[i]
        else:
            print "Invalid argument " + argv[i]
            return 1

        i += 1

    if not user or not password:
        print "User name and password are required, use -u and -p arguments!"
        return 1

    with open(CONFIG_PATH, "r") as f:
        config = json.load(f);

    manifest = RemoteManifest(MANIFEST_URL)
    api=xdaapi.XdaApi()
    api.login(user, password)

    for dev in config["devices"]:
        if device and device != dev["name"]:
            continue

        if not manifest.has_device(dev["name"]):
            print "Device " + dev["name"] + " not found in remote manifest"
            continue

        if not "xda" in dev:
            print "Device " + dev["name"] + " doesn't have xda config"
            continue

        print "Updating thread for " + dev["name"]
        title_gen = FirstPostTitleGenerator(dev)
        update_second_post(api, dev, manifest, dhst_session, title_gen)
        update_first_post(api, dev, title_gen)

    api.logout_user()
    return 0

if __name__ == "__main__":
   exit(main(len(sys.argv), sys.argv))
