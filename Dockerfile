FROM rhel

ENTRYPOINT ["/usr/local/bin/jenkins.sh"]
ENV COPY_REFERENCE_FILE_LOG /var/log/copy_reference_file.log
ENV JENKINS_HOME /var/jenkins_home
EXPOSE 8080
EXPOSE 50000

COPY install.sh /tmp/install.sh
RUN /tmp/install.sh

USER jenkins
VOLUME /var/jenkins_home
