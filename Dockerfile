FROM ubuntu

RUN apt-get update \
  && apt-get -y --no-install-recommends install curl python ca-certificates python-pip build-essential python-setuptools jq gpgv2 ruby \
  && apt-get clean

RUN pip install --upgrade pip && pip install b2

ENV GO_CRON_VERSION v0.0.7
ENV AUTHORIZATION_FAIL_MAX_RETRIES 3
ENV CLEAN_OLD_BACKUPS false
ENV MONTHS_RETENTION 1
ENV BACKUP_TARGET /data
ENV EXCLUDES ""

RUN curl -L https://github.com/odise/go-cron/releases/download/${GO_CRON_VERSION}/go-cron-linux.gz | zcat > /usr/local/bin/go-cron \
  && chmod u+x /usr/local/bin/go-cron

ADD backup.rb /backup.rb
ADD defaults.yaml /defaults.yaml
ADD config.yaml /config.yaml
ADD run.sh /run.sh
CMD /run.sh
