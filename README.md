# Standard maintenance scripts

## Setup

    pip install -r requirements.txt
    bundle

To run the Rake tasks:

* [Create a GitHub personal access token](https://github.com/settings/tokens) with the scopes `public_repo` and `admin:org`
* [Edit your `~/.netrc` file](https://github.com/octokit/octokit.rb#using-a-netrc-file) using the token as your password

## Tests

The standard [`.travis.yml`](fixtures/.travis.yml) file performs:

* Linting of:
  * Python ([flake8](https://pypi.python.org/pypi/flake8))
  * Markdown ([markdownlint](https://github.com/markdownlint/markdownlint))
  * JSON (readable by Python)
* Indenting JSON files

To create a pull request to set up a new repository, enable the repository on [travis-ci.org](https://travis-ci.org), then:

    git checkout -b travis
    curl -O https://raw.githubusercontent.com/open-contracting/standard-maintenance-scripts/master/fixtures/.travis.yml
    git add .travis.yml
    git commit -m 'Add .travis.yml'
    git push -u origin travis

### extension-schema.json

This repository holds `extension-schema.json` against which each extension's `extension.json` is tested. The schema is documented in [standard_extension_template](https://github.com/open-contracting/standard_extension_template#extensionjson). It should largely be the same as [`entry-schema.json`](https://github.com/open-contracting/extension_registry/blob/master/entry-schema.json), documented in [extension_registry](https://github.com/open-contracting/extension_registry#entryjson).

If changes are made to `extension-schema.json`, changes may be needed to:

* Each extension and profile: `extension.json`
* [standard_extension_template](https://github.com/open-contracting/standard_extension_template): [`README.md`](https://github.com/open-contracting/standard_extension_template#extensionjson), `extension.json`
* [extension_registry](https://github.com/open-contracting/extension_registry): [`README.md`](https://github.com/open-contracting/extension_registry#entryjson), `entry-schema.json`, all `entry.json` files, `compile.py`, `new.py`, `sync.py`
* [extension_creator](https://github.com/open-contracting/extension_creator): [`entry.js`](https://github.com/open-contracting/extension_creator/blob/gh-pages/entry.js#L125) `extension.json` line (and recompile `app.js`)
* CoVE: [schema.py](https://github.com/OpenDataServices/cove/blob/master/cove_ocds/lib/schema.py#L116) `apply_extensions` method

## Tools

List tasks:

    invoke -l
    rake -AT

Download all extensions to a directory:

    invoke download_extensions <directory>

Check whether `~/.aspell.en.pws` contains unwanted words:

    invoke check_aspell_dictionary

Check for files have unexpected permissions:

    find . \! -perm 644 -type f -not -path '*/.git/*' -o \! -perm 755 -type d

Check for files with TODOs that should be made into GitHub issues (skipping Git, vendored, translation, and generated files):

    grep -R -i --exclude-dir .git --exclude-dir _static --exclude-dir LC_MESSAGES --exclude app.js --exclude conf.py '\btodo' .

### Review GitHub organization configuration

Lists organization members not employed by the Open Contracting Partnership or its helpdesk teams:

    rake org:members

### Manage pull requests

Lists the pull requests from a given branch:

    rake pulls:list REF=branch

Creates pull requests from a given branch:

    rake pulls:create REF=branch BODY=description

Replaces the descriptions of pull requests from a given branch:

    rake pulls:update REF=branch BODY=description

Compares the given branch to the default branch:

    rake pulls:compare REF=branch

Merges pull requests from a given branch:

    rake pulls:merge REF=branch

### Review GitHub repository metadata and configuration

Disables empty wikis and lists repositories with invalid names, unexpected configurations, etc.:

    rake fix:lint_repos

Protects default branches:

    rake fix:protect_branches

Prepares repositories for archival (`REPOS` is a comma-separated list of repository names):

    rake fix:archive_repos REPOS=…

Adds template content to extension readmes:

    rake fix:update_readmes BASEDIR=extensions

Regenerates the [badges page](badges.md):

    rake repos:badges

The next tasks make no changes, but may require the user to perform an action depending on the output.

Lists repositories with missing or unexpected Travis configuration:

    rake repos:travis

Lists repositories with many unexpected, old branches (so that merged branches without new commits may be deleted):

    rake repos:branches [EXCLUDE=branch1,branch2]

Lists repositories with number of issues, PRs, branches, milestones and whether wiki, pages, issues, projects are enabled:

    rake repos:status [ORG=open-contracting]

Lists extension repositories with missing template content:

    rake repos:readmes

Lists missing or unexpected licenses:

    rake repos:licenses

Lists repository descriptions:

    rake repos:descriptions

Lists non-default issue labels:

    rake repos:labels

Lists non-extension releases:

    rake repos:releases

Lists unreleased tags:

    rake repos:tags

Lists non-Travis, non-Requires.io webhooks:

    rake repos:webhooks

Lists web traffic statistics over past two weeks:

    rake repos:traffic
