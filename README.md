# YoutubeChannelSearcher

# How to use:

> perl create.pl --path=/var/www/domian --name="Domian" --parameter=https://www.youtube.com/watch\?v\=BRe8VCqepgQ\&list\=PLQ9CsdXRvhNcSiQB-OSbfkiBbwX2E8ICP

This will create a folder called `/var/www/domian/` and downloads all the of available transcriptions of the given URL and creates a search called
`Domian-Suche` (in `/var/www/domian/index.php`).

# Dependencies

- Latest version of `youtube-dl`

> sudo apt-get install jq python2.7

> sudo cpan -i Smart::Comments

> sudo cpan -i JSON::Parse

> sudo cpan -i UI::Dialog

# Environment variables

Use `/var/www/` as main dir

> export YoutubeChannelSearcherDir=/var/www/

