FROM docker.elastic.co/logstash/logstash:8.14.0
RUN rm -f /usr/share/logstash/pipeline/logstash.conf
RUN rm -f /usr/share/logstash/config/logstash-sample.conf
COPY ./pipeline/ /usr/share/logstash/pipeline/
COPY ./config/ /usr/share/logstash/config/
