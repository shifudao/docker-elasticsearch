FROM elasticsearch:2.1.2
MAINTAINER "冯宇<yu.feng@shifudao.com>"

ADD elasticsearch-analysis-ik-1.7.0.tar.xz /usr/share/elasticsearch/plugins/elasticsearch-analysis-ik/
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["elasticsearch"]
