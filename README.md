# redmine2github
Issue import from redmine (currently old version) to github issues.
Ahmy Yulrizka (ahmy@yulrizka.com)

##Requirement
* Ruby 1.9 (preferably 1.9.3)

## Installation
There is builtin package for linux called ruby 1.9.1 but the preferable method to install ruby is with rvm (https://rvm.io/) or rbenv (https://github.com/sstephenson/rbenv)

After installing ruby, install dependency with:

```
  $ gem install bundler 
  $ bundle install
```

## Usage
First Go to the redmine, and export the issues of a project to .csv file. There should be a link on the bottom of issues pages

```
$ ruby redmine2github.rb -h
Usage: redmine2github GITHUB_REPO_USER REPO_NAME ISSUE_CSV [OPTIONS]

Options
    -n, --dry-run                    Not actually write any data to github
    -u, --user-file USER_FILE        Specify YAML file with mapping 'Assigned to' to github username
    -e API_KEY,REDMINE_URL,          Export comments from redmine. API_KEY must be provided. you can find this key when trying to export issues as atom. its the 'key' parameter in the url
        --export-comment
    -m, --convert-to-markdown        Convert comment to markdown
    -s, --skip-ssl-cert
    -v, --verbose                    Turn on verbose output
    -h, --help                       help
```

Example

```
  ruby redmine2github.rb github_username github_repo redmine-issues.csv -u users.yml -e 123213123123123123123123123,https://redmine.example.com/ --skip-ssl-cert -m -v
```

* github_username is the username of the repository where issues should be posted
* github_repo is the repository name
* redime-issues.csv is the exported issues file from redmine in csv format
* -u users.yml is mapping from Name "Assigend To" in the redmine issues to Github username (optional)
* -e 123123,http://redmine.example.com is [key],[redmine_url]. you can obtain [key] when you want to export atom in your redmine issues. This would import Comments in redmine to github (optional)
* --skip-ssl-cert if you want to skip https verification
* -v turn on verbose output

## 'Assigned To' mapping 
you could 'convert' the 'assigned_to' field in redmine issue to github issues. to do this create a YAML (http://www.yaml.org/) file and add option -u to the commands
there is example of users.yml provided in this repository
