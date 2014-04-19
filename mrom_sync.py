#!/usr/bin/python
import sys, string, os, json, hashlib, time, re, subprocess, copy, gnupg, getpass
from os.path import isfile, join
from datetime import datetime

MANIFEST_NAME = "manifest.json"
RSYNC_ADDR = "tasemnice:/usr/share/nginx/www/multirom/"
BASE_ADDR = "http://tasemnice.eu/multirom/"
MULTIROM_DIR = "/home/tassadar/nexus/multirom/"
CONFIG_JSON = MULTIROM_DIR + "config.json"
RELEASE_DIR = "release"

REGEXP_MULTIROM = re.compile('^multirom-[0-9]{8}-v([0-9]{1,3})([a-z]?)-[a-z]*\.zip$')
REGEXP_RECOVERY = re.compile('^TWRP_multirom_([a-z]*)_([0-9]{8})(-[0-9]{2})?\.img$')

opt_verbose = False
opt_dry_run = False

# config.json example:
#{
#    "devices": [
#        {
#            "name": "grouper",
#            "ubuntu_touch": {
#                "req_multirom": "17",
#                "req_recovery": "mrom20111022-00"
#            },
#            "changelogs": [
#                {
#                    "name": "MultiROM",
#                    "file": "changelog_grouper_multirom.txt"
#                },
#            ],
#            "kernels": [
#                {
#                    "name": "Stock 4.1",
#                    "file": "kernel_kexec_41-2.zip"
#                }
#            ]
#        }
#}

class Utils:
    @staticmethod
    def loadConfig():
        with open(CONFIG_JSON, "r") as f:
            return json.load(f);

    @staticmethod
    def md5sum(path):
        with open(path, "rb") as f:
            m = hashlib.md5()
            while True:
                data = f.read(8192)
                if not data:
                    break
                m.update(data)
            return m.hexdigest()

    @staticmethod
    def get_bbootimg_info(path):
        cmd = [ "bbootimg", "-j", path ]
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = p.communicate()
        ret = p.returncode

        if ret != 0:
            raise Exception("bbootimg failed! " + stdout + "\n" + stderr)

        return json.loads(stdout)

    @staticmethod
    def rsync(src, dst):
        cmd = [ "rsync", "-rLtzP", "--delete", src, dst ]
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        while True:
            c = p.stdout.read(1)
            if not c:
                break;
            sys.stdout.write(c)
            if c == "\r":
                sys.stdout.flush()

        stdout, stderr = p.communicate()

        if p.returncode != 0:
            raise Exception("rsync has failed:\n" + stderr)

    @staticmethod
    def v(txt):
        if opt_verbose:
            print txt

    @staticmethod
    def str_insert(orig, new, pos):
        if pos < 0:
            pos = len(orig) + pos
        return orig[:pos] + new + orig[pos:]

    @staticmethod
    def sign_file(passphrase, path, destination = None):
        key_path = join(MULTIROM_DIR, "gpg")

        if not os.path.isdir(key_path):
            raise IndexError("GPG dir doesn't exist '%s'." % key_path)

        if not destination:
            destination = "%s.asc" % path

        if os.path.exists(destination):
            raise Exception("destination already exists.")

        gpg = gnupg.GPG(gnupghome=key_path)
        gpg.encoding = 'utf-8'
        with open(path, "rb") as f:
            signature = gpg.sign_file(f, passphrase=passphrase, detach=True)
        with open(destination, "w") as f:
            f.write(str(signature))


def get_multirom_file(path, symlinks):
    ver = [ 0, 0 ]
    filename = ""
    size = 0

    for f in os.listdir(path):
        if not isfile(join(path, f)):
            continue

        match = REGEXP_MULTIROM.match(f)
        if not match:
            continue

        maj = int(match.group(1))
        patch = match.group(2)[0] if match.group(2) else 0

        if maj > ver[0] or (maj == ver[0] and patch > ver[1]):
            ver[0] = maj
            ver[1] = patch
            filename = f
            size = os.path.getsize(join(path, f))

    if not filename:
        raise Exception("No multirom zip found in folder " + path)

    Utils.v("    MultiROM: " + filename);
    symlinks.append(filename)

    return {
        "type": "multirom",
        "version": str(ver[0]) + str(ver[1] if ver[1] else ""),
        "url": BASE_ADDR + filename,
        "md5": Utils.md5sum(join(path, filename)),
        "size": size
    }

def get_recovery_file(device_name, path, symlinks):
    ver_date = datetime.min
    ver_str = ""
    filename = ""
    size = 0

    for f in os.listdir(path):
        if not isfile(join(path, f)):
            continue

        match = REGEXP_RECOVERY.match(f)
        if not match or match.group(1) != device_name:
            continue

        info = Utils.get_bbootimg_info(join(path, f))
        if not info["boot_img_hdr"]["name"]:
            continue

        date = datetime.strptime(info["boot_img_hdr"]["name"], "mrom%Y%m%d-%M")
        if date > ver_date:
            ver_date = date
            ver_str = info["boot_img_hdr"]["name"]
            filename = f
            size = os.path.getsize(join(path, f))

    if not filename:
        raise Exception("No recovery image found in folder " + path)

    Utils.v("    Recovery: " + filename);
    symlinks.append(filename)

    return {
        "type": "recovery",
        "version": ver_str,
        "url": BASE_ADDR + filename,
        "md5": Utils.md5sum(join(path, filename)),
        "size": size
    }

def generate_variants(dev, man_dev, symlinks):
    res = []
    for var in dev["variants"]:
        Utils.v("Variant " + var["name"] + " of " + dev["name"] + ":")
        man_var = copy.deepcopy(man_dev)
        man_var["name"] = var["name"]

        overrides = var["override"].split("|");
        Utils.v("    overrides: " + str(overrides))

        symlinks[var["name"]] = []

        if "recovery" in overrides:
            rec = get_recovery_file(var["name"], join(MULTIROM_DIR, var["name"]), symlinks[var["name"]])
            for i in range(len(man_var["files"])):
                if man_var["files"][i]["type"] == "recovery":
                    man_var["files"][i] = rec
                    break

        if opt_verbose:
            Utils.v("    files:")
            for f in man_var["files"]:
                Utils.v("      " + str(f))

        res.append(man_var)

    return res

def generate(readable_json, status_text, gpg_sign_data, gpg_passphrase):
    print "Generating manifest..."

    config = Utils.loadConfig();

    manifest = {
        "status": status_text,
        "date" : time.strftime("%Y-%m-%d"),
        "gpg" : gpg_sign_data,
        "devices" : [ ]
    }

    symlinks = { }

    for dev in config["devices"]:
        Utils.v("Device " + dev["name"] + ":")
        if "active" in dev and dev["active"] == False:
            Utils.v("    active: False");
            continue

        man_dev = { "name": dev["name"] }
        if "ubuntu_touch" in dev:
            Utils.v("    ubuntu_touch: " + str(dev["ubuntu_touch"]))
            man_dev["ubuntu_touch"] = dev["ubuntu_touch"]

        symlinks[dev["name"]] = []

        files = [
            get_multirom_file(join(MULTIROM_DIR, dev["name"]), symlinks[dev["name"]]),
            get_recovery_file(dev["name"], join(MULTIROM_DIR, dev["name"]), symlinks[dev["name"]])
        ]

        for k in dev["kernels"]:
            symlinks[dev["name"]].append(k["file"])

            path = join(MULTIROM_DIR, dev["name"], k["file"]);
            f = {
                "type": "kernel",
                "version": k["name"],
                "url": BASE_ADDR + k["file"],
                "md5": Utils.md5sum(path),
                "size": os.path.getsize(path)
            }
            if "extra" in k:
                f["extra"] = k["extra"]
            files.append(f)

        if "uninstaller" in dev:
            symlinks[dev["name"]].append(dev["uninstaller"])
            path = join(MULTIROM_DIR, dev["name"], dev["uninstaller"]);
            files.append({
                "type": "uninstaller",
                "version": "",
                "url": BASE_ADDR + dev["uninstaller"],
                "md5": Utils.md5sum(path),
                "size": os.path.getsize(path)
            })

        if "changelogs" in dev:
            man_dev["changelogs"] = []
            for c in dev["changelogs"]:
                man_c = { "name": c["name"], "url": BASE_ADDR + c["file"] }
                man_dev["changelogs"].append(man_c)
                symlinks[dev["name"]].append(c["file"])

        if opt_verbose:
            Utils.v("    files:")
            for f in files:
                Utils.v("      " + str(f))

        man_dev["files"] = files
        manifest["devices"].append(man_dev)

        if "variants" in dev:
            manifest["devices"].extend(generate_variants(dev, man_dev, symlinks))

    if opt_dry_run:
        return

    # Remove old manifest and symlinks
    release_path = join(MULTIROM_DIR, RELEASE_DIR)
    os.system("mkdir -p \"" + release_path + "\"")
    os.system("rm -f \"" + release_path + "/\"*")

    # write manifest
    man_path = join(MULTIROM_DIR, RELEASE_DIR, MANIFEST_NAME)
    with open(man_path, "w") as f:
        if readable_json:
            json.dump(manifest, f, indent=4, separators=(',', ': '))
        else:
            json.dump(manifest, f)
        f.write('\n')
    Utils.sign_file(gpg_passphrase, man_path)

    # upload gpg public keyring
    os.symlink(join("..", "gpg", "pubring.gpg"), join(MULTIROM_DIR, RELEASE_DIR, "keyring.gpg"))

    # create symlinks
    for dev in symlinks.keys():
        for f in symlinks[dev]:
            dest = join(MULTIROM_DIR, RELEASE_DIR, f)
            os.symlink(join("..", dev, f), dest)
            if gpg_sign_data:
                Utils.sign_file(gpg_passphrase, dest)

def upload():
    print "Uploading files..."
    Utils.rsync(join(MULTIROM_DIR, RELEASE_DIR) + "/", RSYNC_ADDR)

def insert_suffix(suffix):
    global BASE_ADDR
    global RSYNC_ADDR
    global RELEASE_DIR

    if suffix[0] != '-':
        suffix = '-' + suffix

    BASE_ADDR = Utils.str_insert(BASE_ADDR, suffix, -1)
    RSYNC_ADDR = Utils.str_insert(RSYNC_ADDR, suffix, -1)
    RELEASE_DIR += suffix

def lock_suffix():
    path = join(MULTIROM_DIR, RELEASE_DIR, ".lock")
    open(path, 'a').close()
    print "Lock \"" + path + "\" was created."

def unlock_suffix():
    path = join(MULTIROM_DIR, RELEASE_DIR, ".lock")
    os.remove(path)
    print "Lock \"" + path + "\" was removed."

def print_usage(name):
    print "Usage: " + name + " [switches]";
    print "\nSwitches:"
    print "  --help                             Print this help"
    print "  --no-upload                        Don't upload anything, just generate"
    print "  --no-gen-manifest                  Don't generate anything, just rsync current files"
    print "  -h, --readable-json                Generate JSON manifest in human-readable form"
    print "  -v, --verbose                      Print more info"
    print "  -n, --dry-run                      Don't change/upload anything. turns on --verbose and --no-upload"
    print "  -p <pass>, --password=<pass>       Password for the gpg key"
    print "  -s <suffix>, --suffix=<suffix>     Append suffix to upload folder name and manifest name"
    print "  -l, --lock                         Locks this suffix and does nothing else"
    print "  -u, --unlock                       Unlocks this suffix and does nothing else"
    print "  --status=<status text>             Set manifest status text"
    print "  --no-gpg                           Disable gpg signature on data files (manifest is still signed!)"

def main(argc, argv):
    global opt_verbose
    global opt_dry_run

    i = 1
    gen_manifest = True
    upload_files = True
    readable_json = False
    lock = False
    unlock = False
    status = "ok"
    gpg_passphrase = None
    no_gpg = False

    while i < argc:
        if argv[i] == "--no-upload":
            upload_files = False
        elif argv[i] == "--no-gen-manifest":
            gen_manifest = False
        elif argv[i] == "-h" or argv[i] == "--readable-json":
            readable_json = True
        elif argv[i] == "-v" or argv[i] == "--verbose":
            opt_verbose = True
        elif argv[i] == "-n" or argv[i] == "--dry-run":
            opt_dry_run = True
            opt_verbose = True
            upload_files = False
        elif argv[i] == "-s" and i+1 < argc:
            i += 1
            insert_suffix(argv[i])
        elif argv[i].startswith("--suffix="):
            insert_suffix(argv[i][9:])
        elif argv[i] == "-l" or argv[i] == "--lock":
            lock = True
            upload_files = False
            gen_manifest = False
        elif argv[i] == "-u" or argv[i] == "--unlock":
            unlock = True
            upload_files = False
            gen_manifest = False
        elif argv[i].startswith("--status="):
            status = argv[i][9:].replace("\\n", "\n")
        elif argv[i] == "-p" and i+1 < argc:
            i += 1
            gpg_passphrase = argv[i]
        elif argv[i].startswith("--password="):
            gpg_passphrase = argv[i][11:]
        elif argv[i] == "--no-gpg":
            no_gpg = True
        else:
            print_usage(argv[0]);
            return 0
        i += 1

    Utils.v("MANIFEST_NAME: " + MANIFEST_NAME);
    Utils.v("BASE_ADDR: " + BASE_ADDR);
    Utils.v("RSYNC_ADDR: " + RSYNC_ADDR);

    if lock:
        lock_suffix()
    elif unlock:
        unlock_suffix()
    else:
        lock_path = join(MULTIROM_DIR, RELEASE_DIR, ".lock")
        if os.path.exists(lock_path):
            print "Lock \"" + lock_path + "\" exists!"
            print "Run this script with -u argument to unlock it."
            return 1

        if gen_manifest:
            if not gpg_passphrase:
                gpg_passphrase = getpass.getpass(prompt='Enter GPG key passphrase: ')
            generate(readable_json, status, not no_gpg, gpg_passphrase)

        if upload_files:
            upload()

    return 0

if __name__ == "__main__":
   exit(main(len(sys.argv), sys.argv))
