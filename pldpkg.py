#!/usr/bin/python
import sys
import optparse
from subprocess import Popen, PIPE

from github2.client import Github

OPTION_LIST = (
    optparse.make_option('-t', '--api-token',
            default=None, action="store", dest="api_token", type="str",
            help="Github API token. Default is to find this from git config"),
    optparse.make_option('-u', '--api-user',
            default=None, action="store", dest="api_user", type="str",
            help="Github Username. Default is to find this from git config"),
)

# to use, setup your github user and api key:
# git config --global github.user USER
# git config --global github.token API_TOKEN

class Repository(object):
    def __init__(self, username=None, api_user=None, api_token=None):
        self.project = "pld-linux"
        self.api_user = api_user or self.git_config_get("github.user")
        self.api_token = api_token or self.git_config_get("github.token")
        self.username = username or self.api_user
        print("U:(%s) T:(%s) F:(%s)" % (self.api_user, self.api_token, self.username))
        self.client = Github(self.api_user, self.api_token, requests_per_second=1)

    def git_config_get(self, key):
        pipe = Popen(["git", "config", "--get", key], stdout=PIPE)
        return pipe.communicate()[0].strip()

    def add(self, package, description = '', homepage = ''):
        name = "%s/%s" % (self.project, package)
        repo = None
        try:
            repo = self.client.repos.show(name)
        except RuntimeError, e:
            if e.message.count("Repository not found"):
                print "OK: %s not present, ok to add" % package
            else:
                raise
        if repo:
            print "OK: %s already exists" % package
            return

        repo = self.client.repos.create(name, description, homepage, public=True)

    def delete(self, package):
        name = "%s/%s" % (self.project, package)
        res = self.client.repos.delete(name)
        print res['delete_token']
        # TODO process delete_token (dig source how)
#        req = Github(self.api_user, res['delete_token'], requests_per_second=1)
#        res = req.repos.delete(name)
#        print res
        print "OK: %s deleted" % package

def parse_options(arguments):
    parser = optparse.OptionParser(option_list=OPTION_LIST)
    options, values = parser.parse_args(arguments)
    return options, values


options, values = parse_options(sys.argv[1:])
username = values and values[0] or None
f = Repository(username=username, **vars(options))
#f.delete('eventum')
#f.add('eventum', 'Eventum Issue / Bug tracking system', 'http://eventum.mysql.org/')
