#!/usr/bin/python
import sys, string, os, getpass, json, httplib, urllib, urllib2, hashlib
import mimetypes, mimetools, itertools

# For this class thanks to site http://pymotw.com.
class MultiPartForm(object):
    """Accumulate the data to be used when posting a form."""

    def __init__(self):
        self.form_fields = []
        self.files = []
        self.boundary = mimetools.choose_boundary()
        return

    def get_content_type(self):
        return 'multipart/form-data; boundary=%s' % self.boundary

    def add_field(self, name, value):
        """Add a simple field to the form data."""
        self.form_fields.append((name, value))
        return

    def add_file(self, fieldname, filename, fileHandle, mimetype=None):
        """Add a file to be uploaded."""
        body = fileHandle.read()
        if mimetype is None:
            mimetype = mimetypes.guess_type(filename)[0] or 'application/octet-stream'
        self.files.append((fieldname, filename, mimetype, body))
        return

    def __str__(self):
        """Return a string representing the form data, including attached files."""
        # Build a list of lists, each containing "lines" of the
        # request.  Each part is separated by a boundary string.
        # Once the list is built, return a string where each
        # line is separated by '\r\n'.
        parts = []
        part_boundary = '--' + self.boundary

        # Add the form fields
        parts.extend(
            [ part_boundary,
              'Content-Disposition: form-data; name="%s"' % name,
              '',
              value,
              ]
            for name, value in self.form_fields
        )

        # Add the files to upload
        parts.extend(
            [ part_boundary,
              'Content-Disposition: file; name="%s"; filename="%s"' % \
              (field_name, filename),
              'Content-Type: %s' % content_type,
              '',
              body,
              ]
            for field_name, filename, content_type, body in self.files
        )

        # Flatten the list and add closing boundary marker,
        # then return CR+LF separated data
        flattened = list(itertools.chain(*parts))
        flattened.append('--' + self.boundary + '--')
        flattened.append('')
        return '\r\n'.join(flattened)

class MFireAPI:
    API_KEY_CONST=""
    APP_ID_CONST=""

    def __init__(self):
        self.session_token = ""
        self.email = ""
        self.password = ""
        self.dest_dir=""
        self.api_key = self.API_KEY_CONST
        self.app_id = self.APP_ID_CONST

    def doRequest(self, url, args):
        args["response_format"] = "json";
        res = urllib2.urlopen(url, urllib.urlencode(args));
        return json.load(res)

    def login(self, print_key):
        sign = hashlib.sha1(self.email + self.password + self.app_id + self.api_key).hexdigest();
        info = self.doRequest("https://www.mediafire.com/api/user/get_session_token.php",
                  {"email":self.email, "password":self.password, "application_id":self.app_id,
                   "signature":sign });

        if info["response"]["result"] != "Success":
            return 1

        if print_key:
            print info["response"]["session_token"];

        self.session_token = info["response"]["session_token"];
        return 0

    def renew_token(self, print_key):
        info = self.doRequest("http://www.mediafire.com/api/user/renew_session_token.php",
                              { "session_token":self.session_token });

        if info["response"]["result"] != "Success":
            return 1

        if print_key:
            print info["response"]["session_token"];

        self.session_token = info["response"]["session_token"];
        return 0

    def get_folder_key(self, folder, folder_key):
        args = { "content_type":"folders" };
        if not folder_key:
            args["session_token"] = self.session_token;
        else:
            args["folder_key"] = folder_key;

        info = self.doRequest("http://www.mediafire.com/api/folder/get_content.php", args);

        folders = info["response"]["folder_content"]["folders"];
        if not folders:
            return ""
        for i in range(len(folders)):
            if folders[i]["name"] == folder:
                return folders[i]["folderkey"];
        return ""

    def get_folder_key_recursive(self, path):
        p = path.split("/");
        if not p[0]:
            p.pop(0);

        if len(p) == 0:
            return "";

        folder_key = ""
        for i in range(len(p)):
            folder_key = self.get_folder_key(p[i], folder_key);
            if not folder_key:
                return ""
        return folder_key

    def upload_file(self, f, folder_key):
        print "Uploading file " + f

        fp = open(f, "rb");
        fSize = os.path.getsize(f)
        headers = {'x-filename': os.path.basename(f), 'x-filesize': int(fSize) }
        data = {'session_token': self.session_token, 'response_format': "json", "action_on_duplicate":"replace" }
        if folder_key:
            data["uploadkey"] = folder_key;

        form = MultiPartForm()
        form.add_file('fileUpload', os.path.basename(f), fp)

        request = urllib2.Request("http://www.mediafire.com/api/upload/upload.php?" + urllib.urlencode(data), None, headers)
        body = str(form)
        request.add_header('Content-Type', form.get_content_type())
        request.add_header('Content-Length', len(body))
        request.add_data(body)
        res = urllib2.urlopen(request)
        js = json.load(res)['response']
        fp.close()
        if (js['result'] == "Error"):
            return js['message']
        return ""

    def upload(self, files):
        if not self.session_token:
            if login(false) != 0:
                return 1

        folder_key = ""
        if self.dest_dir and self.dest_dir != "/":
            folder_key = self.get_folder_key_recursive(self.dest_dir)
            if not folder_key:
                print "Could not find folder " + self.dest_dir
                return 1

        for i in range(len(files)):
            if self.upload_file(files[i], folder_key):
                return 1
        return 0

def print_usage(name):
    print "Usage: " + name + " [switches] [command] [command arguments]";
    print "\nCommands:"
    print "  login                      Logs in and prints out session token"
    print "  upload                     Uploads files (filenames as argument)"
    print "  renew                      Renews session token and prints out the new one"
    print "\nSwitches:"
    print "  -h, --help                 Print this help"
    print "  -l                         Set login (email)"
    print "  -p                         Set password (you will be promted for pass if -l is specified without -p)"
    print "  -t                         Set session token"
    print "  -d                         Destination folder for upload"
    print "  -k                         API key"
    print "  -i                         App id"

def main(argc, argv):
    api = MFireAPI()
    i = 1
    command = ""
    cmd_args = []
    while i < argc:
        if argv[i] == "-h" or argv[i] == "--help":
            print_usage(argv[0]);
            return 0;
        elif argv[i] == "-l":
            i+=1
            api.email = argv[i];
        elif argv[i] == "-p":
            i+=1
            api.password = argv[i];
        elif argv[i] == "-t":
            i+=1
            api.session_token = argv[i];
        elif argv[i] == "-d":
            i+=1
            api.dest_dir = argv[i];
        elif argv[i] == "-k":
            i+=1
            api.api_key = argv[i];
        elif argv[i] == "-i":
            i+=1
            api.app_id = argv[i];
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

    if api.email and not api.password:
        api.password = getpass.getpass("Enter password for " + api.email + ": ");

    if not api.session_token and (not api.password or not api.email):
        print "You have to enter either session token or login and pass\n"
        print_usage(argv[0]);
        return 1;

    if command == "login":
        if not api.email or not api.password:
            print "You have to enter login and password to log-in"
            print_usage(argv[0]);
            return 1
        if not api.api_key or not api.app_id:
            print "API key or App id was not specified!\n\n"
            print_usage(argv[0]);
            return 1
        return api.login(True);
    elif command == "upload":
        return api.upload(cmd_args);
    elif command == "renew":
        if not api.session_token:
            print "You have to enter old session token!"
            print_usage(argv[0]);
            return 1
        return api.renew_token(True);
    else:
        print "Unknown command: " + command + "\n\n"
        print_usage(argv[0]);
        return 1;

if __name__ == "__main__":
   exit(main(len(sys.argv), sys.argv))
