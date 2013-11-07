#!/usr/bin/python
import sys, string, os, json, hashlib, time, re, subprocess
from os.path import isfile, join
from datetime import datetime

MANIFEST_ADDR = "saffron:/var/www/"
MANIFEST_NAME = "multirom_manifest.json"
RSYNC_ADDR = "malygos:/usr/share/nginx/www/multirom/"
BASE_ADDR = "http://54.194.25.123/multirom/"
MULTIROM_DIR = "/home/tassadar/nexus/multirom/"
CONFIG_JSON = MULTIROM_DIR + "config.json"

REGEXP_MULTIROM = re.compile('^multirom-[0-9]{8}-v([0-9]{1,3})([a-z]?)-[a-z]*\.zip$')
REGEXP_RECOVERY = re.compile('^TWRP_multirom_[a-z]*_([0-9]{8})([0-9]{2})?\.img$')

# config.json example:
#{
#    "devices": [
#        {
#            "name": "grouper",
#            "ubuntu_touch": {
#                "req_multirom": "17",
#                "req_recovery": "mrom20111022-00"
#            },
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


def get_multirom_file(path, symlinks):
    ver = [ 0, 0, "" ]

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
            ver[2] = f

    if ver[0] == 0:
        raise Exception("No multirom zip found in folder " + path)

    symlinks.append(ver[2])

    return {
        "type": "multirom",
        "version": str(ver[0]) + str(ver[1] if ver[1] else ""),
        "url": BASE_ADDR + ver[2],
        "md5": Utils.md5sum(join(path, ver[2]))
    }

def get_recovery_file(path, symlinks):
    ver = [ datetime.min, "", "" ]

    for f in os.listdir(path):
        if not isfile(join(path, f)):
            continue

        match = REGEXP_RECOVERY.match(f)
        if not match:
            continue

        info = Utils.get_bbootimg_info(join(path, f))
        if not info["boot_img_hdr"]["name"]:
            continue

        date = datetime.strptime(info["boot_img_hdr"]["name"], "mrom%Y%m%d-%M")
        if date > ver[0]:
            ver[0] = date
            ver[1] = info["boot_img_hdr"]["name"]
            ver[2] = f

    if not ver[1]:
        raise Exception("No recovery image found in folder " + path)

    symlinks.append(ver[2])

    return {
        "type": "recovery",
        "version": ver[1],
        "url": BASE_ADDR + ver[2],
        "md5": Utils.md5sum(join(path, ver[2]))
    }

def generate(readable_json):
    print "Generating manifest..."

    config = Utils.loadConfig();

    manifest = {
        "status":"ok",
        "date" : time.strftime("%Y-%m-%d"),
        "devices" : [ ]
    }

    symlinks = { }

    for dev in config["devices"]:
        man_dev = { "name": dev["name"] }
        if "ubuntu_touch" in dev:
            man_dev["ubuntu_touch"] = dev["ubuntu_touch"]

        symlinks[dev["name"]] = []

        files = [
            get_multirom_file(join(MULTIROM_DIR, dev["name"]), symlinks[dev["name"]]),
            get_recovery_file(join(MULTIROM_DIR, dev["name"]), symlinks[dev["name"]])
        ]

        for k in dev["kernels"]:
            symlinks[dev["name"]].append(k["file"])
            files.append({
                "type": "kernel",
                "version": k["name"],
                "url": BASE_ADDR + k["file"],
                "md5": Utils.md5sum(join(MULTIROM_DIR, dev["name"], k["file"]))
            })


        man_dev["files"] = files
        manifest["devices"].append(man_dev)

    # Remove old manifest and symlinks
    os.system("rm \"" + MULTIROM_DIR + "/release/\"*")

    # write manifest
    with open(join(MULTIROM_DIR, "release", MANIFEST_NAME), "w") as f:
        if readable_json:
            json.dump(manifest, f, indent=4, separators=(',', ': '))
        else:
            json.dump(manifest, f)
        f.write('\n')

    # create symlinks
    for dev in symlinks.keys():
        for f in symlinks[dev]:
            os.symlink(join("..", dev, f), join(MULTIROM_DIR, "release", f))


def upload():
    print "Uploading files..."
    Utils.rsync(join(MULTIROM_DIR, "release") + "/", RSYNC_ADDR)
    Utils.rsync(join(MULTIROM_DIR, "release", MANIFEST_NAME), MANIFEST_ADDR + MANIFEST_NAME)

def print_usage(name):
    print "Usage: " + name + " [switches]";
    print "\nSwitches:"
    print "  --help                     Print this help"
    print "  --no-upload                Don't upload anything, just generate"
    print "  --no-gen-manifest          Don't generate anything, just rsync current files"
    print "  -h, --readable-json        Generate JSON manifest in human-readable form"

def main(argc, argv):
    i = 1
    gen_manifest = True
    upload_files = True
    readable_json = False

    while i < argc:
        if argv[i] == "--no-upload":
            upload_files = False
        elif argv[i] == "--no-gen-manifest":
            gen_manifest = False
        elif argv[i] == "-h" or argv[i] == "--readable-json":
            readable_json = True
        else:
            print_usage(argv[0]);
            return 0
        i += 1

    if gen_manifest:
        generate(readable_json)

    if upload_files:
        upload()

if __name__ == "__main__":
   exit(main(len(sys.argv), sys.argv))
