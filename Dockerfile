# this Dockerfile is used only to get a consistent environment in which to run the tests (test_all.rb),
# it has nothing to do with the actual gem that gets published.

# use an older version of ubuntu so that we get a version of postgresql so is supported by the older rails
# versions, or we won't be able to test out support for them.
FROM ubuntu:16.04

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
	apt-get install -y software-properties-common && \
	apt-add-repository ppa:brightbox/ruby-ng && \
	DEBIAN_FRONTEND=noninteractive apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential git \
		mysql-server libmysqlclient-dev postgresql-9.5 libpq-dev libsqlite3-dev \
		ruby2.5 ruby2.5-dev && \
	rm -f /etc/apt/apt.conf.d/20auto-upgrades && \
	apt-get clean -y && \
	rm -rf /var/cache/apt/archives/*

RUN ln -sf /usr/bin/ruby2.5 /usr/bin/ruby
RUN ln -sf /usr/bin/gem2.5 /usr/bin/gem
RUN gem install bundler -v 1.16.4 --no-ri --no-rdoc

# install a version of mysql2 that the older versions of rails are compatible with
RUN gem install mysql2 -v 0.4.10

WORKDIR /tmp
ADD Gemfile Gemfile
ADD constant_table_saver.gemspec constant_table_saver.gemspec
ADD lib/constant_table_saver/version.rb lib/constant_table_saver/version.rb
RUN bundle install -j 4

ADD . .
RUN echo 'starting postgresql' && \
	service postgresql start && \
	echo 'creating postgresql database' && \
	su postgres -c 'createdb --encoding unicode --template template0 constant_table_saver_test' && \
	echo 'creating postgresql user' && \
	su postgres -c 'createuser --superuser root' && \
	echo 'starting mysql' && \
	mkdir -p /var/run/mysqld && \
	chown mysql:mysql /var/run/mysqld && \
	(/usr/sbin/mysqld --skip-grant-tables &) && \
	echo 'waiting for mysql to start' && \
	mysqladmin --wait=30 ping && \
	echo 'creating mysql database' && \
	mysqladmin create constant_table_saver_test && \
	echo 'running tests' && \
	./test_all.rb
