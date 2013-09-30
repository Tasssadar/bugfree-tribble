#!/usr/bin/python
import sys, string, os, getpass, hashlib
import requests
import dexml
from dexml import fields

class file_info(dexml.Model):
    response = fields.String(tagname='response', required=False)
    file_code = fields.String(tagname="file_code")
    folder_id = fields.String(tagname="folder_id")
    filename = fields.String(tagname="filename")

class folder_info(dexml.Model):
    id = fields.String(tagname="id")
    name = fields.String(tagname="name")
    total_files = fields.Integer(tagname='total_files')
    total_folders = fields.Integer(tagname='total_folders')

class results(dexml.Model):
    method = fields.String(tagname='method')
    response = fields.String(tagname='response',required=False)
    token = fields.String(tagname='token',required=False)
    file_infos = fields.List(fields.Model(file_info),required=False)
    folder_info = fields.Model(folder_info, required=False)
    folders = fields.List("folder_info", tagname="folders", required=False)
    files = fields.List("file_info", tagname="files", required=False)

class DevHostAPI:
    def __init__(self):
        self.session_token = ""
        self.user = ""
        self.password = ""
        self.dest_dir=""

    def doRequest(self, url, args):
        res = requests.get(url, params=args);
        return results.parse(res.text);

    def login(self, print_key):
        info = self.doRequest("http://d-h.st/api/user/auth", { "user":self.user, "pass":self.password });

        if info.response != "Success":
            return 1

        if print_key:
            print info.token

        self.session_token = info.token
        return 0

    def get_folder_key(self, folder, folder_id):
        args = { "token":self.session_token };
        if folder_id:
            args["folder_id"] = folder_id;

        res = self.doRequest("http://d-h.st/api/folder/content", args);
        if res.response != "Success":
            return ""

        for i in range(res.folder_info.total_folders):
           if res.folders[i].name == folder:
                return str(res.folders[i].id)
        return ""

    def get_folder_key_recursive(self, path):
        p = path.split("/");
        if not p[0]:
            p.pop(0);

        if len(p) == 0:
            return "0";

        folder_key = ""
        for i in range(len(p)):
            folder_key = self.get_folder_key(p[i], folder_key);
            if not folder_key:
                return ""
        return folder_key

    def find_file_code(self, filename, folder_id):
        args = { "token":self.session_token };
        if folder_id:
            args["folder_id"] = folder_id;

        res = self.doRequest("http://d-h.st/api/folder/content", args);
        if res.response != "Success":
            return ""

        for i in range(res.folder_info.total_files):
           if res.files[i].filename == filename:
                return res.files[i].file_code
        return ""

    def upload_file(self, f, folder_id):
        parameters = { "token":self.session_token, "action":"uploadapi", "public":"1" }
        if folder_id:
            parameters["uploadfolder"] = folder_id;
        file_code = self.find_file_code(os.path.basename(f), folder_id);
        if file_code:
            parameters["file_code[]"] = file_code;

        file = {'files[]':open(f,'r')}

        print "Uploading file " + f + (" (Replacing file " + file_code + ")" if file_code else "")

        r = requests.post("http://api.d-h.st/upload", files=file,data=parameters)
        res = results.parse(r.text);

        if res.file_infos[0].response != "Success":
            return "Failed"

        return ""

    def upload(self, files):
        if not self.session_token:
            if self.login(False) != 0:
                return 1

        dest_dir_id = self.get_folder_key_recursive(self.dest_dir);

        for i in range(len(files)):
            if self.upload_file(files[i], dest_dir_id):
                print "Failed to upload file " + files[i]
                return 1
        return 0

def print_usage(name):
    print "Usage: " + name + " [switches] [command] [command arguments]";
    print "\nCommands:"
    print "  login                      Logs in and prints out session token"
    print "  upload                     Uploads files (filenames as argument)"
    print "\nSwitches:"
    print "  -h, --help                 Print this help"
    print "  -l                         Set login"
    print "  -p                         Set password (you will be promted for pass if -l is specified without -p)"
    print "  -t                         Set session token"
    print "  -d                         Destination folder for upload"

def main(argc, argv):
    api = DevHostAPI()
    i = 1
    command = ""
    cmd_args = []
    while i < argc:
        if argv[i] == "-h" or argv[i] == "--help":
            print_usage(argv[0]);
            return 0;
        elif argv[i] == "-l":
            i+=1
            api.user = argv[i];
        elif argv[i] == "-p":
            i+=1
            api.password = argv[i];
        elif argv[i] == "-t":
            i+=1
            api.session_token = argv[i];
        elif argv[i] == "-d":
            i+=1
            api.dest_dir = argv[i];
        elif not command:
            command = argv[i]
        else:
            cmd_args.append(argv[i]);

        i+=1;

    if not command:
        print "Command was not specified\n\n"
        print_usage(argv[0]);
        return 1

    if command == "upload" and len(cmd_args) == 0:
        print "No files to upload\n\n"
        print_usage(argv[0]);
        return 1

    if api.user and not api.password:
        api.password = getpass.getpass("Enter password for " + api.user + ": ");

    if not api.session_token and (not api.password or not api.user):
        print "You have to enter either session token or login and pass\n"
        print_usage(argv[0]);
        return 1;

    if command == "login":
        if not api.user or not api.password:
            print "You have to enter login and password to log-in"
            print_usage(argv[0]);
            return 1
        return api.login(True);
    elif command == "upload":
        return api.upload(cmd_args);
    else:
        print "Unknown command: " + command + "\n\n"
        print_usage(argv[0]);
        return 1;

if __name__ == "__main__":
   exit(main(len(sys.argv), sys.argv))
