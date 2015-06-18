#!/bin/bash

curl -so /etc/yum.repos.d/rhel-7-server-rpms.repo http://192.168.0.254:8086/rhel-7-server-rpms.repo
curl -so /etc/yum.repos.d/rhel-7-server-extras-rpms.repo http://192.168.0.254:8086/rhel-7-server-extras-rpms.repo

http_proxy=http://192.168.0.254:8080/ yum -y update
http_proxy=http://192.168.0.254:8080/ yum -y install docker findutils git java-1.8.0-openjdk sudo wget zip

useradd -d "$JENKINS_HOME" -u 1000 -m -s /bin/bash jenkins

sed -i -e '/^Defaults.*requiretty\|visiblepw/ s/^/#/' /etc/sudoers
cat >>/etc/sudoers <<EOF
%jenkins	ALL=(ALL)	NOPASSWD: ALL
EOF

#curl -so /etc/yum.repos.d/jenkins.repo http://pkg.jenkins-ci.org/redhat/jenkins.repo
rpm --import https://jenkins-ci.org/redhat/jenkins-ci.org.key
http_proxy=http://192.168.0.254:8080/ yum -y install http://mirrors.clinkerhq.com/jenkins/redhat/jenkins-1.617-1.1.noarch.rpm

yum clean all

mkdir -p /usr/share/jenkins/ref/init.groovy.d
cat >/usr/share/jenkins/ref/init.groovy.d/init.groovy <<'EOF'
import hudson.model.*;
import jenkins.model.*;


Thread.start {
      sleep 10000
      println "--> setting agent port for jnlp"
      Jenkins.instance.setSlaveAgentPort(50000)
}
EOF

cat >/usr/local/bin/jenkins.sh <<'EOF'
#! /bin/bash

set -e

# Copy files from /usr/share/jenkins/ref into /var/jenkins_home
# So the initial JENKINS-HOME is set with expected content. 
# Don't override, as this is just a reference setup, and use from UI 
# can then change this, upgrade plugins, etc.
copy_reference_file() {
	f=${1%/} 
	echo "$f" >> $COPY_REFERENCE_FILE_LOG
    rel=${f:23}
    dir=$(dirname ${f})
    echo " $f -> $rel" >> $COPY_REFERENCE_FILE_LOG
	if [[ ! -e /var/jenkins_home/${rel} ]] 
	then
		echo "copy $rel to JENKINS_HOME" >> $COPY_REFERENCE_FILE_LOG
		mkdir -p /var/jenkins_home/${dir:23}
		cp -r /usr/share/jenkins/ref/${rel} /var/jenkins_home/${rel};
		# pin plugins on initial copy
		[[ ${rel} == plugins/*.jpi ]] && touch /var/jenkins_home/${rel}.pinned
	fi; 
}
export -f copy_reference_file
echo "--- Copying files at $(date)" >> $COPY_REFERENCE_FILE_LOG
find /usr/share/jenkins/ref/ -type f -exec bash -c 'copy_reference_file {}' \;

# if `docker run` first argument start with `--` the user is passing jenkins launcher arguments
if [[ $# -lt 1 ]] || [[ "$1" == "--"* ]]; then
   exec java $JAVA_OPTS -jar /usr/lib/jenkins/jenkins.war $JENKINS_OPTS "$@"
fi

# As argument is not jenkins, assume user want to run his own process, for sample a `bash` shell to explore this image
exec "$@"
EOF
chmod 0755 /usr/local/bin/jenkins.sh

cat >/usr/local/bin/plugins.sh <<'EOF'
#! /bin/bash

# Parse a support-core plugin -style txt file as specification for jenkins plugins to be installed
# in the reference directory, so user can define a derived Docker image with just :
#
# FROM jenkins
# COPY plugins.txt /plugins.txt
# RUN /usr/local/bin/plugins.sh /plugins.txt
#

set -e

REF=/usr/share/jenkins/ref/plugins
mkdir -p $REF

while read spec || [ -n "$spec" ]; do
    plugin=(${spec//:/ });
    [[ ${plugin[0]} =~ ^# ]] && continue
    [[ ${plugin[0]} =~ ^\s*$ ]] && continue
    [[ -z ${plugin[1]} ]] && plugin[1]="latest"
    echo "Downloading ${plugin[0]}:${plugin[1]}"
    curl -s -L -f ${JENKINS_UC_DOWNLOAD}/plugins/${plugin[0]}/${plugin[1]}/${plugin[0]}.hpi -o $REF/${plugin[0]}.jpi
done  < $1
EOF
chmod 0755 /usr/local/bin/plugins.sh

chown -R jenkins:jenkins "$JENKINS_HOME" /usr/share/jenkins/ref

touch $COPY_REFERENCE_FILE_LOG
chown jenkins:jenkins $COPY_REFERENCE_FILE_LOG

mkdir -p /usr/share/jenkins/ref/plugins
cd /usr/share/jenkins/ref/plugins
wget -q http://updates.jenkins-ci.org/latest/build-pipeline-plugin.hpi
wget -q http://updates.jenkins-ci.org/latest/jquery.hpi
wget -q http://updates.jenkins-ci.org/latest/parameterized-trigger.hpi

rm $0
