require 'rubygems'

puts "Rails: #{ENV['RAILS_VERSION'] || 'default'}"
puts "Env: #{ENV['RAILS_ENV'] || 'not set'}"
gem 'minitest', (ENV['RAILS_VERSION'] =~ /^(3\.|4\.0)/ ? '~> 4.0' : nil)
gem 'activesupport', ENV['RAILS_VERSION']
gem 'activerecord',  ENV['RAILS_VERSION']

require 'minitest/autorun'
require 'active_support'
require 'active_support/test_case'
require 'active_record'
require 'active_record/fixtures'
require 'byebug' rescue nil

RAILS_ENV = ENV['RAILS_ENV'] ||= 'sqlite3'

ActiveRecord::Base.configurations = YAML::load(IO.read(File.join(File.dirname(__FILE__), "database.yml")))
ActiveRecord::Base.establish_connection ActiveRecord::Base.configurations[ENV['RAILS_ENV']]
load(File.join(File.dirname(__FILE__), "/schema.rb"))
ActiveSupport::TestCase.send(:include, ActiveRecord::TestFixtures) if ActiveRecord.const_defined?('TestFixtures')
ActiveSupport::TestCase.fixture_path = File.join(File.dirname(__FILE__), "fixtures")

ActiveRecord::Base.class_eval do
  unless instance_methods.include?(:set_table_name)
    eval "class << self; def set_table_name(x); self.table_name = x; end; end"
  end
end

require File.expand_path(File.join(File.dirname(__FILE__), '../init')) # load the plugin
