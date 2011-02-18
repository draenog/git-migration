#!/usr/bin/python
import sys
from optparse import OptionParser
from subprocess import Popen, PIPE
from github2.client import Github

# To use, setup your github user and api token:
# API Token - can be found on the lower right of https://github.com/account
# git config --global github.user USER
# git config --global github.token API_TOKEN

class Package(object):
    def __init__(self, login=None, account=None, apitoken=None, debug = None):
        self.project = "pld-linux"
        self.account = account or self.git_config_get("github.user")
        self.apitoken = apitoken or self.git_config_get("github.token")
        self.login = login or self.account
        self.debug = debug
        self.client = Github(self.account, self.apitoken, debug=self.debug)

    def git_config_get(self, key):
        pipe = Popen(["git", "config", "--get", key], stdout=PIPE)
        return pipe.communicate()[0].strip()

    def exists(self, package):
        name = "%s/%s" % (self.project, package)
        try:
            repo = self.client.repos.show(name)
        except RuntimeError, e:
            if e.message.count("Repository not found"):
                return False
            else:
                raise
        return True

    """ add package repository in GitHub """
    def add(self, package, description = '', homepage = '', team='Developers'):
        name = "%s/%s" % (self.project, package)
        repo = self.client.repos.create(name, description, homepage, public=True)
        if team:
            self.add_team(name, team)
        return repo

    """ delete repository for package """
    def delete(self, package):
        name = "%s/%s" % (self.project, package)
        res = self.client.repos.delete(name)
        token = res['delete_token']
        self.client.repos.delete(name, token)

    """ add package to team """
    def add_team(self, package, team):
        name = "%s/%s" % (self.project, package)
        # find team id
        team_id = None
        for t in self.client.organizations.teams(self.project):
            if t.name == team:
                team_id = t.id
        if team_id == None:
            raise RuntimeError, "Team '%s' not found" % team

        team = self.client.teams.add_repository(str(team_id), name)
        return team

def parse_commandline():
    """Parse the comandline and return parsed options."""

    parser = OptionParser()
    parser.description = __doc__

    parser.set_usage('usage: %prog [options] (add|delete) [package].\n'
                     'Try %prog --help for details.')
    parser.add_option('-d', '--debug', action='store_true',
                      help='Enables debugging mode')
    parser.add_option('-l', '--login',
                      help='Username to login with')
    parser.add_option('-a', '--account',
                      help='User owning the repositories to be changed ' \
                           '[default: same as --login]')
    parser.add_option('-t', '--apitoken',
                      help='API Token - can be found on the lower right of ' \
                           'https://github.com/account')

    options, args = parser.parse_args()
    if len(args) != 2:
        parser.error('wrong number of arguments')
    if (len(args) == 1 and args[0] in ['add', 'delete']):
        parser.error('%r needs a package name as second parameter\n' % args[0])
    if (len(args) == 2 and args[0] not in ['add', 'delete']):
        parser.error('unknown command %r. Try "add" or "delete"\n' % args[0])

    return options, args

def main(options, args):
    """This implements the actual program functionality"""

    if not options.account:
        options.account = options.login

    p = Package(**vars(options))

    command, package = args
    if command == 'add':
        if p.exists(package):
            print "%r already exists in %r" % (package, p.project)
        else:
            p.add(package)
            print "added %r to %r" % (package, p.project)
    if command == 'delete':
        if not p.exists(package):
            print "%r does not exist in %r" % (package, p.project)
        else:
            p.delete(package)
            print "removed %r from %r" % (package, p.project)

if __name__ == '__main__':
    main(*parse_commandline())
