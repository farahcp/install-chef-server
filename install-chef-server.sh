#!/bin/bash

# mostly following this
# http://wiki.opscode.com/display/chef/Installing+Chef+Server+Manually

#set -e

# needs setting on vagrant VMs for some reason
PATH=${PATH}:/usr/local/sbin:/usr/sbin:/sbin:${GEM_PATH}
echo $PATH

STARTDIR=`pwd`

# read the config file
. conf/config

# add the opscode repo
echo "deb http://apt.opscode.com/ `lsb_release -cs`-0.10 main" | \
  sudo tee /etc/apt/sources.list.d/opscode.list > /dev/null
# and their key
sudo mkdir -p /etc/apt/trusted.gpg.d
if [ ! "`gpg --list-keys | grep 83EF826A`" ]
then
  EXITSTATUS=2
  while [ ${EXITSTATUS} == 2 ]
  do
    gpg --keyserver keys.gnupg.net --recv-keys 83EF826A
    EXITSTATUS=$?
  done
fi
gpg --export packages@opscode.com | \
  sudo tee /etc/apt/trusted.gpg.d/opscode-keyring.gpg > /dev/null

# RabbitMQ repo
echo "deb http://www.rabbitmq.com/debian/ testing main" | \
  sudo tee /etc/apt/sources.list.d/rabbit.list > /dev/null
if [ ! "`sudo apt-key list | grep Rabbit`" ]
then
  cd /tmp
  wget http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
  sudo apt-key add rabbitmq-signing-key-public.asc
fi

# configure rabbit (if it's not already done)
[ "`sudo rabbitmqctl list_vhosts | grep chef`" ] \
  || sudo rabbitmqctl add_vhost /chef
[ "`sudo rabbitmqctl list_users | grep chef`" ] \
  || sudo rabbitmqctl add_user chef testing
sudo rabbitmqctl set_permissions -p /chef chef ".*" ".*" ".*"
# we also like the rabbit webui management thing
sudo rabbitmq-plugins enable rabbitmq_management
sudo service rabbitmq-server restart

# install the chef gems (if we don't already have them)
for gem in chef-server chef-server-api chef-solr chef-server-webui 
do
  if [ ! "`gem list | grep \"${gem} \"`" ]
  then
    gem install ${gem} --no-ri --no-rdoc
  fi
done

# install the chef config file
sudo mkdir -p /etc/chef
sudo chown -R `whoami` /etc/chef
[ ${WEBUI_PASSWORD} ] || WEBUI_PASSWORD='password'
[ ${SERVERNAME} ] || SERVERNAME=`ip -f inet -o addr | grep eth0 \
  | tr -s ' ' ' ' | cut -d ' ' -f 4 | cut -d '/' -f 1`
cat ${STARTDIR}/files/server.rb | sed "s:SERVERNAME:${SERVERNAME}:" \
  | sed "s:PASSWORD:${WEBUI_PASSWORD}:" \
  | sudo tee /etc/chef/server.rb > /dev/null

# run the solr installer
# NOTE: THIS WILL NUKE ANY EXISTING CHEF SOLR CONFIGURATION AND DATA
sudo mkdir -p /var/chef
sudo chown -R `whoami` /var/chef
chef-solr-installer -f

# we do this so we don't have to run as root
sudo mkdir -p /var/log/chef
sudo chown -R `whoami` /var/log/chef

# setup the services
[ ${CHEF_SERVER_USER} ] || CHEF_SERVER_USER=`whoami`
# the chef gems supply some upstart scripts, but they run everything as root
# we'd rather run as whatever chef user we're using
for file in `find /usr/local/rvm/ | grep debian/etc/init/ | grep -v client`
do
  outfile=`basename ${file}`
  service=${outfile%.conf}

# horrendous sed monster to make these jobs run as our user 
  cat ${file} | \
    sed "s:    :  :g" | \
    sed "s:test -x .* || \(.*\):su - ${CHEF_SERVER_USER} -c \"which ${service}\" || \1:" | \
    sed "s:exec /usr/bin/${service} \(.*\):script\n  su - ${CHEF_SERVER_USER} -c \"${service} \1\"\nend script:" | \
    sudo tee /etc/init/${outfile} > /dev/null

# symlinking here means we get tab-complete in 'service foo start'-type stuff
# (among other things, I'm sure)
  sudo ln -sf /lib/init/upstart-job /etc/init.d/${service}
# actually start the thing
  sudo service ${service} start 2> /dev/null || sudo service ${service} restart
done

# set up the nginx vhosts to proxy this stuff
#cd ${STARTDIR}/files/nginx
#for file in `ls`
#do
#  NAME=`echo ${file} | tr "[:lower:]" "[:upper:]"`NAME

## @OrganizedGang explained this indirect reference voodoo to me
#  REPLACEMENT=${!NAME}
#  [ ${REPLACEMENT} ] || REPLACEMENT=${file}
#  cat ${file} | sed "s:${NAME}:${REPLACEMENT}:" |\
#    sudo tee /etc/nginx/sites-available/${REPLACEMENT} > /dev/null
#done

cd ${STARTDIR}
for line in `cat conf/vhosts`
do
  UPSTREAM=`echo ${line} | cut -d ':' -f 1`
  PORT=`echo ${line} | cut -d ':' -f 2`
  SERVERNAME=`echo ${line} | cut -d ':' -f 3`
  cat files/nginx/vhost.template |\
    sed "s:UPSTREAM:${UPSTREAM}:" |\
    sed "s:PORT:${PORT}:" |\
    sed "s:SERVERNAME:${SERVERNAME}:" |\
    sudo tee /etc/nginx/sites-available/${SERVERNAME} > /dev/null
  [ ${PORT} == "4040" ] && WEBUI="http://${SERVERNAME}"
  [ ${PORT} == "4000" ] && CHEFSERVER="http://${SERVERNAME}:4000"
  sudo ln -s /etc/nginx/sites-available/${SERVERNAME} /etc/nginx/sites-enabled
done

sudo service nginx restart

# end

echo

echo "Chef-server is at ${CHEFSERVER}"
echo "Chef WebUI is at ${WEBUI}"
echo "WebUI login: admin/${WEBUI_PASSWORD}"

echo
knife configure -i
