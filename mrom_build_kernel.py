#!/usr/bin/python

import sys, os, hashlib, multiprocessing, subprocess, shutil, zipfile, json, base64
from ftplib import FTP

MULTIROM_DIR = "/home/tassadar/nexus/multirom/"
BUILD_DIR = "/opt/android/kernels"
PATCHES_DIR = "/opt/android/kernels/patches"
TEMPLATES_DIR = "/opt/android/kernels/templates"

info = {
    "flo": {
        "make": BUILD_DIR + "/make_arm_48.sh",
        "arch": "arm",
        "dtb": False,
        "aosp": {
            "remote": "https://android.googlesource.com/kernel/msm",
            "branch-prefix": "android-msm-flo-3.4-",
            "defconfig": "flo_defconfig",
        },
        "cm": {
            "remote": "https://github.com/CyanogenMod/android_kernel_google_msm.git",
            "branch-prefix": "cm-",
            "defconfig": "cyanogen_flo_defconfig",
        }
    },
    "mako": {
        "make": BUILD_DIR + "/make_arm_48.sh",
        "arch": "arm",
        "dtb": False,
        "aosp": {
            "remote": "https://android.googlesource.com/kernel/msm",
            "branch-prefix": "android-msm-mako-3.4-",
            "defconfig": "mako_defconfig",
        },
        "cm": {
            "remote": "https://github.com/CyanogenMod/android_kernel_google_msm.git",
            "branch-prefix": "cm-",
            "defconfig": "cyanogen_mako_defconfig",
        }
    },
    "hammerhead": {
        "make": BUILD_DIR + "/make_arm_48.sh",
        "arch": "arm",
        "dtb": True,
        "aosp": {
            "remote": "https://android.googlesource.com/kernel/msm",
            "branch-prefix": "android-msm-hammerhead-3.4-",
            "defconfig": "hammerhead_defconfig",
        },
        "cm": {
            "remote": "https://github.com/CyanogenMod/android_kernel_lge_hammerhead.git",
            "branch-prefix": "cm-",
            "defconfig": "cyanogenmod_hammerhead_defconfig"
        },
    },
    "shamu": {
        "make": BUILD_DIR + "/make_arm_48.sh",
        "arch": "arm",
        "dtb": True,
        "aosp": {
            "remote": "https://android.googlesource.com/kernel/msm",
            "branch-prefix": "android-msm-shamu-3.10-",
            "defconfig": "shamu_defconfig",
        },
    }
}

def git_init(cfg):
    dirname = hashlib.md5(cfg["remote"]).hexdigest()
    dir = os.path.join(BUILD_DIR, dirname)

    if os.path.exists(os.path.join(dir, ".git")):
        print "  Fetching %s to %s/%s..." % (cfg["remote"], BUILD_DIR, dirname)
        os.chdir(dir)
        subprocess.check_call(["git", "fetch", "origin"])
    else:
        print "  Cloning %s to %s/%s..." % (cfg["remote"], BUILD_DIR, dirname)
        os.chdir(BUILD_DIR)
        subprocess.check_call(["git", "clone", cfg["remote"], dirname])
        os.chdir(dir)
    return dir

def git_checkout(cfg, version):
    print "  Checking out origin/%s%s" % (cfg["branch-prefix"], version)
    subprocess.call(["git", "reset", "--hard"])
    subprocess.call(["git", "clean", "-fd"])
    subprocess.check_call(["git", "checkout", "origin/%s%s" % (cfg["branch-prefix"], version)])
    subprocess.check_call(["git", "reset", "--hard"])
    subprocess.check_call(["git", "clean", "-fd"])
    subprocess.call(["git", "show", "-s", "--oneline"])

def git_get_hash():
    hash = subprocess.check_output([ "git", "log", "-n1", "--format=format:%H" ])
    return hash.strip()

def apply_patch(patch):
    patch_path = os.path.join(PATCHES_DIR, patch)
    subprocess.check_call(["patch", "-p1", "-i", patch_path])

def prepare_config(make, dtb, cfg):
    print "  Using %s" % (cfg["defconfig"])
    subprocess.check_call([ make, "defconfig", cfg["defconfig"] ])

    with open(".config", "a") as f:
        f.write("CONFIG_KEXEC=y\n")
        f.write("CONFIG_KEXEC_HARDBOOT=y\n")
        if dtb:
            f.write("CONFIG_ATAGS_PROC=n\n")
            f.write("CONFIG_PROC_DEVICETREE=y\n")
        else:
            f.write("CONFIG_ATAGS_PROC=y\n")

def get_num_android_ver(android_version):
    ver_num = android_version.replace(".", "")
    if len(ver_num) == 2:
        ver_num += "0"
    try:
        return int(ver_num)
    except ValueError:
        return 0

def make_zip(cfg, device, type, version, android_version):
    kernel_image_name = "zImage"
    if cfg["dtb"]:
        kernel_image_name += "-dtb"

    kernel_image_path = "arch/%s/boot/%s" % (cfg["arch"], kernel_image_name)

    if not os.path.isfile(kernel_image_path):
        raise Exception("Can't find kernel image at %s!" % kernel_image_path)

    if type == "aosp":
        cnt = 0
        dest_base = os.path.join(MULTIROM_DIR, device, "kernel_kexec_%s_%d" % (device, get_num_android_ver(android_version)))
        dest = dest_base + ".zip"
        while os.path.exists(dest):
            cnt += 1
            dest = "%s-%d.zip" % (dest_base, cnt)
    elif type == "cm":
        ver = version.replace(".", "")
        if ver.endswith("0"):
            ver = ver[:-1]
        zip_base = "kernel_kexec_%s_cm%s" % (device, ver)
        dest_base = os.path.join(MULTIROM_DIR, device, zip_base)
        taken = {}
        for file in os.listdir(os.path.join(MULTIROM_DIR, device)):
            if file.startswith(zip_base):
                tokens = file.split("-")
                if len(tokens) >= 2:
                    taken[int(tokens[1])] = True

        order = 1
        while order in taken:
            order += 1
        dest = "%s-%02d-%s.zip" % (dest_base, order, git_get_hash()[:9])

    print "  Preparing %s..." % (dest)

    shutil.copy(os.path.join(TEMPLATES_DIR, "%s.zip" % device), dest)
    with zipfile.ZipFile(dest, "a", zipfile.ZIP_DEFLATED) as z:
        z.write(kernel_image_path, "kernel/%s" % kernel_image_name)
    return os.path.basename(dest)

def update_config(device, type, zip_name, version, android_version):
    with open(os.path.join(MULTIROM_DIR, "config.json"), "r") as f:
        cfg = json.load(f)

    kernel_cfg = {
        "file": zip_name,
        "extra": {
            "releases": [ android_version ],
        }
    }

    ver_num = get_num_android_ver(android_version)

    if type == "cm":
        name_prefix = "CM "
        kernel_cfg["name"] = "CM %s" % version
        kernel_cfg["extra"]["display"] = "cm_"
    elif type == "aosp":
        name_prefix = "Stock "
        kernel_cfg["name"] = "Stock %s" % android_version

    for dev in cfg["devices"]:
        if dev["name"] != device:
            continue

        idx = 0
        last_with_prefix = 0
        inserted = False
        for k in dev["kernels"]:
            if "extra" not in k:
                idx += 1
                continue

            if k["name"] == kernel_cfg["name"]:
                dev["kernels"][idx] = kernel_cfg
                inserted = True
                break
            elif k["name"].startswith(name_prefix):
                last_with_prefix = idx + 1
                max_ver = 0
                for rel in k["extra"]["releases"]:
                    v = get_num_android_ver(rel)
                    if v > max_ver:
                        max_ver = v

                if max_ver > ver_num:
                    inserted = True
                    dev["kernels"].insert(idx, kernel_cfg)
                    break
            idx += 1

        if not inserted:
            dev["kernels"].insert(last_with_prefix, kernel_cfg)

    with open(os.path.join(MULTIROM_DIR, "config-new.json"), "w") as f:
        json.dump(cfg, f, sort_keys=True, indent=4, separators=(',', ': '))
    os.rename(os.path.join(MULTIROM_DIR, "config-new.json"), os.path.join(MULTIROM_DIR, "config.json"))

def load_user_mrom_cfg():
    res = {}
    with open(os.path.join(os.getenv("HOME"), "mrom_cfg.sh"), "r") as f:
        for line in f:
            idx = line.find("=")
            if idx == -1:
                continue
            key = line[:idx]
            val = line[idx+1:].strip('"\n')
            if key.endswith("_PASS"):
                val = base64.b64decode(val).strip("\n")
            res[key] = val
    return res

def upload_basketbuild(dev, zip):
    cfg = load_user_mrom_cfg()
    ftp = FTP("basketbuild.com", cfg["BASKET_LOGIN"], cfg["BASKET_PASS"])
    with open(os.path.join(MULTIROM_DIR, dev, zip), "rb") as f:
        ftp.storbinary("STOR multirom/%s/%s" % (dev, zip), f)
    ftp.close()

if __name__ == "__main__":
    cnt = -1
    clean = True
    checkout_only = False
    for arg in sys.argv:
        if arg == "--noclean":
            clean=False
            continue
        elif arg == "--checkout":
            checkout_only = True
            continue

        if cnt == 0:
            devices = arg
        elif cnt == 1:
            type = arg
        elif cnt == 2:
            version = arg
        elif cnt == 3:
            android_version = arg
        cnt += 1

    if cnt < 4:
        print "%s DEVICES TYPE VERSION ANDROID_VERSION" % sys.argv[0]
        sys.exit(1)

    zips = {}
    for dev in info:
        if devices.find(dev) == -1:
            continue

        print "Building kernel for %s, %s-%s" % (dev, type, version)

        cfg = info[dev]
        git_init(cfg[type])
        git_checkout(cfg[type], version)
        apply_patch("%s-%s.patch" % (dev, type))

        if checkout_only:
            continue

        if clean:
            subprocess.check_call([ cfg["make"], "mrproper" ])

        prepare_config(cfg["make"], cfg["dtb"], cfg[type])

        print "  Building the kernel"
        subprocess.check_call([ cfg["make"], "-j%d" % multiprocessing.cpu_count() ])

        zip_name = make_zip(cfg, dev, type, version, android_version)
        zips[zip_name] = dev

        update_config(dev, type, zip_name, version, android_version)

        subprocess.check_call([ cfg["make"], "clean" ])

    if len(zips) == 0:
        sys.exit(0)

#    for zip in zips:
#        print "\nUploading %s" % zip
#        dev = zips[zip]

#        subprocess.check_call([ "upload_dhst.sh", os.path.join(MULTIROM_DIR, dev, zip), "multirom/%s" % dev ])

#        print "  Uploading to basketbuild"
#        upload_basketbuild(dev, zip)


