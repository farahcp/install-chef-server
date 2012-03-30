


**Almost** all of the work for this script was done by [Sam Pikesley](http://github.com/pikesley). The install-chef-server script here is 99% his doing. 
I changed:
* the Ruby version from 1.9.2 to 1.9.2 (which took about 4 keystrokes)
* one or two other lines to account for issues I encountered running manually (e.g. added `autoconf` to the list of apt-get installs)

I wrote `init-chef-server.sh`, which simply automates instructions that can be found in his Readme at http://github.com/pikesley/catering-college

I created this repo separately so that I could maintain my version and make it easier to access. I will be updating the SH to pull the extra files from here instead of from my server once all necessary files are where they need to be.
