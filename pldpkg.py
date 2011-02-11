#!/usr/bin/python
project = "pld-linux"
package = None
username = None
api_token = None

from github2.client import Github
github = None
if api_token:
    github = Github(username=username, api_token=api_token, requests_per_second=1)
else:
    github = Github(username=username, requests_per_second=1)

def add_repo(package, description = '', homepage = ''):
    name = "%s/%s" % (project, package)
    try:
        repo = github.repos.show(name)
    except RuntimeError, e:
        if e.message.count("Repository not found"):
            print "OK: %s not exists yet" % package
        else:
            raise
    if repo:
        print "OK: %s already exists" % package
        return

    repo = github.repos.create(name, description, homepage, public=True)

def del_repo(package):
    name = "%s/%s" % (project, package)
    res = github.repos.delete(name)
    # TODO process delete_token (dig source how)
    print res['delete_token']
    print "OK: %s deleted" % package

#del_repo('eventum')
#add_repo('eventum', 'Eventum Issue / Bug tracking system', 'http://eventum.mysql.org/')
