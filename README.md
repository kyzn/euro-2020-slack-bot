# NAME

euro-2020-slack v0.03

# DESCRIPTION

Downloads EURO 2020 live game status from football-data.org & posts to Slack.

You can install system dependencies on a ubuntu flavored OS like below.

    apt-get update
    apt install make cpanminus gcc libssl-dev zlib1g-dev

Once you have cpanm, run following to install perl dependencies.

    cpanm --installdeps .

# SYNOPSIS

First, you will need a Slack incoming webhook URL. Here's how to get it:

- Create an app at [https://api.slack.com/apps?new\_app=1](https://api.slack.com/apps?new_app=1)
- Choose "From Scratch" if asked
- Below "Add features and functionality", click "Incoming webhooks"
- Turn on "Activate Incoming Webhooks"
- Click "Add New Webhook to Workspace" down below
- Choose the channel you want the bot to interact with
- Copy webhook URL, take a note. Don't share this with other people.
- Go to your app details page at [https://api.slack.com](https://api.slack.com)
- Go to "Incoming webhooks" on left navigation, it will be there.

Post to slack incoming webhook URL.

    perl euro-2020-slack.pl --token=.. --slack=https://hooks.slack.com/services/..

Increase politeness sleep for outgoing HTTP requests (defaults to 2 seconds)

    perl euro-2020-slack.pl --token=.. --slack=.. --sleep=10

Change delay (in minutes) to post to slack (put 0 for no delay. defaults to 3 mins)

    perl euro-2020-slack.pl --token=.. --slack=.. --delay=1

Specify multiple Slack URLs to post to multiple workspaces

    perl euro-2020-slack.pl --token=.. --slack=... --slack=...

Specify name and location of db.json file. This may be
helpful if you are running multiple instances of script.

    perl euro-2020-slack.pl --token=.. --slack=... --dbjson=some/file.json

Do a dry run: Don't post to slack, don't write to db.json

    perl euro-2020-slack.pl --token=... --dry

# CONTRIBUTING

PRs are welcome, but you are encouraged to discuss it in issues first.
Please don't edit this README directly, it's auto generated with commands below.

    cpanm Pod::Markdown
    pod2markdown euro-2020-slack.pl > README.md

# LICENSE

MIT.

This script talks to [football-data.org](https://www.football-data.org/),
please check their terms for your use case.

# ATTRIBUTION

This script is partly based on
[j0k3r/worldcup-slack-bot](https://github.com/j0k3r/worldcup-slack-bot)
which was written in PHP.

Football data provided by the Football-Data.org API.
