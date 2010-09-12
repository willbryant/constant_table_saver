if File.exist?("../../../config/boot.rb")
  require "../../../config/boot.rb"
else
  require 'rubygems'
end

require 'test/unit'
require 'active_support'
require 'active_support/test_case'
require 'active_record'
require 'active_record/fixtures'

begin
  require 'ruby-debug'
  Debugger.start
rescue LoadError
  # ruby-debug not installed, no debugging for you
end

RAILS_ENV = ENV['RAILS_ENV'] ||= 'test'

ActiveRecord::Base.configurations = YAML::load(IO.read(File.join(File.dirname(__FILE__), "database.yml")))
ActiveRecord::Base.establish_connection ActiveRecord::Base.configurations[ENV['RAILS_ENV']]
load(File.join(File.dirname(__FILE__), "/schema.rb"))
ActiveSupport::TestCase.send(:include, ActiveRecord::TestFixtures) if ActiveRecord.const_defined?('TestFixtures')
ActiveSupport::TestCase.fixture_path = File.join(File.dirname(__FILE__), "fixtures")

require 'init' # load the plugin
