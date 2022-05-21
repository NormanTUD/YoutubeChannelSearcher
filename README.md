# YoutubeChannelSearcher

# How to use:

> perl create.pl --path=/var/www/domian --name="Domian" --parameter=https://www.youtube.com/watch\?v\=BRe8VCqepgQ\&list\=PLQ9CsdXRvhNcSiQB-OSbfkiBbwX2E8ICP

This will create a folder called `/var/www/domian/` and downloads all the of available transcriptions of the given URL and creates a search called
`Domian-Suche` (in `/var/www/domian/index.php`).

# Dependencies

- Latest version of `youtube-dl`

> sudo apt-get install jq python2.7 python-pip

> sudo pip install lxml cssselect

> sudo cpan -i Smart::Comments

> sudo cpan -i JSON::Parse

> sudo cpan -i UI::Dialog

# Environment variables

Use `/var/www/` as main dir

> export YoutubeChannelSearcherDir=/var/www/

You can also get a list of all the videos you've seen automatically (if you use firefox), by using this command:

> perl create.pl --lang="de" --parameter="/home/user/.mozilla/firefox/3ijrlrwe.default-1464891319751/places.sqlite"
