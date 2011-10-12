require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

class StandardPie < ActiveRecord::Base
  set_table_name "pies"
end

class ConstantPie < ActiveRecord::Base
  set_table_name "pies"
  constant_table
  
  if defined?(named_scope)
    named_scope :filled_with_unicorn, :conditions => {:filling => 'unicorn'}
  else
    scope :filled_with_unicorn, :conditions => {:filling => 'unicorn'}
  end
  
  def self.with_unicorn_filling_scope
    with_scope(:find => {:conditions => {:filling => 'unicorn'}}) { yield }
  end
end

class ConstantNamedPie < ActiveRecord::Base
  set_table_name "pies"
  constant_table :name => :filling
end

class ConstantLongNamedPie < ActiveRecord::Base
  set_table_name "pies"
  constant_table :name => :filling, :name_prefix => "a_", :name_suffix => "_pie"
end

class IngredientForStandardPie < ActiveRecord::Base
  set_table_name "ingredients"
  belongs_to :pie, :class_name => "StandardPie"
end

class IngredientForConstantPie < ActiveRecord::Base
  set_table_name "ingredients"
  belongs_to :pie, :class_name => "ConstantPie"
end

if ActiveRecord::VERSION::MAJOR < 3 || (ActiveRecord::VERSION::MAJOR == 3 && ActiveRecord::VERSION::MINOR < 1)
  # proudly stolen from ActiveRecord's test suite, with addition of BEGIN and COMMIT
  ActiveRecord::Base.connection.class.class_eval do
    IGNORED_SQL = [/^PRAGMA/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /SHOW FIELDS/, /^BEGIN$/, /^COMMIT$/]

    def execute_with_query_record(sql, name = nil, &block)
      $queries_executed ||= []
      $queries_executed << sql unless IGNORED_SQL.any? { |r| sql =~ r }
      execute_without_query_record(sql, name, &block)
    end

    alias_method_chain :execute, :query_record
  end
else
  # this is from 3.1's test suite.  ugly.
  class ActiveRecord::SQLCounter
    cattr_accessor :ignored_sql
    self.ignored_sql = [/^PRAGMA (?!(table_info))/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /^SHOW max_identifier_length/, /^BEGIN/, /^COMMIT/]

    # FIXME: this needs to be refactored so specific database can add their own
    # ignored SQL.  This ignored SQL is for Oracle.
    ignored_sql.concat [/^select .*nextval/i, /^SAVEPOINT/, /^ROLLBACK TO/, /^\s*select .* from all_triggers/im]

    def initialize
      $queries_executed = []
    end

    def call(name, start, finish, message_id, values)
      sql = values[:sql]

      # FIXME: this seems bad. we should probably have a better way to indicate
      # the query was cached
      unless ['CACHE', 'SCHEMA'].include?(values[:name]) # we have altered this from the original, to exclude SCHEMA as well
        # debugger if sql =~ /^PRAGMA table_info/ && Kernel.caller.any? {|i| i.include?('test_it_creates_named_class_methods_if_a_')}
        $queries_executed << sql unless self.class.ignored_sql.any? { |r| sql =~ r }
      end
    end
  end
  ActiveSupport::Notifications.subscribe('sql.active_record', ActiveRecord::SQLCounter.new)
end

class ConstantTableSaverTest < ActiveRecord::TestCase
  fixtures :all
  
  setup do
    ConstantPie.reset_constant_record_cache!
  end

  test "it caches find(:all) results" do
    @pies = StandardPie.find(:all)
    assert_queries(1) do
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all).collect(&:attributes)
    end
    assert_no_queries do
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all).collect(&:attributes)
    end
  end

  test "it caches all() results" do
    @pies = StandardPie.all
    assert_queries(1) do
      assert_equal @pies.collect(&:attributes), ConstantPie.all.collect(&:attributes)
    end
    assert_no_queries do
      assert_equal @pies.collect(&:attributes), ConstantPie.all.collect(&:attributes)
    end
  end

  test "it caches find(id) results" do
    @pie = StandardPie.find(1)
    assert_queries(1) do
      assert_equal @pie.attributes, ConstantPie.find(1).attributes
    end
    assert_no_queries do
      assert_equal @pie.attributes, ConstantPie.find(1).attributes
    end
  end

  test "it caches find(ids) results" do
    @pie1 = StandardPie.find(1)
    @pie2 = StandardPie.find(2)
    assert_queries(1) do
      assert_equal [@pie1.attributes, @pie2.attributes], ConstantPie.find([1, 2]).collect(&:attributes)
    end
    assert_no_queries do
      assert_equal [@pie1.attributes, @pie2.attributes], ConstantPie.find([1, 2]).collect(&:attributes)
    end
  end

  test "it caches find(:first) results" do
    @pie = StandardPie.find(:first)
    assert_queries(1) do
      assert_equal @pie.attributes, ConstantPie.find(:first).attributes
    end
    assert_no_queries do
      assert_equal @pie.attributes, ConstantPie.find(:first).attributes
    end
  end

  test "it caches first() results" do
    @pie = StandardPie.first
    assert_queries(1) do
      assert_equal @pie.attributes, ConstantPie.first.attributes
    end
    assert_no_queries do
      assert_equal @pie.attributes, ConstantPie.first.attributes
    end
  end

  test "it caches find(:last) results" do
    @pie = StandardPie.find(:last)
    assert_queries(1) do
      assert_equal @pie.attributes, ConstantPie.find(:last).attributes
    end
    assert_no_queries do
      assert_equal @pie.attributes, ConstantPie.find(:last).attributes
    end
  end
  
  test "it caches last() results" do
    @pie = StandardPie.last
    assert_queries(1) do
      assert_equal @pie.attributes, ConstantPie.last.attributes
    end
    assert_no_queries do
      assert_equal @pie.attributes, ConstantPie.last.attributes
    end
  end
  
  test "it caches belongs_to association find queries" do
    @standard_pie_ingredients = IngredientForStandardPie.all
    @standard_pies = @standard_pie_ingredients.collect(&:pie)
    @constant_pie_ingredients = IngredientForConstantPie.all
    assert_queries(1) do # doesn't need to make 3 queries for 3 pie assocations!
      assert_equal @standard_pies.collect(&:attributes), @constant_pie_ingredients.collect(&:pie).collect(&:attributes)
    end
    assert_no_queries do # and once cached, needs no more
      assert_equal @standard_pies.collect(&:attributes), @constant_pie_ingredients.collect(&:pie).collect(&:attributes)
    end
  end
  
  test "it isn't affected by scopes active at the time of first load" do
    assert_equal 0, ConstantPie.filled_with_unicorn.all.size
    assert_equal 0, ConstantPie.with_unicorn_filling_scope { ConstantPie.all.length }
    assert_equal StandardPie.all.size, ConstantPie.all.size
  end
  
  test "it isn't affected by relational algebra active at the time of first load" do
    assert_equal 0, ConstantPie.filled_with_unicorn.all.size
    assert_equal 0, ConstantPie.where(:filling => 'unicorn').all.length
    assert_equal 2, ConstantPie.where("filling LIKE 'Tasty%'").all.length
    assert_equal StandardPie.all.size, ConstantPie.all.size
  end if ActiveRecord::VERSION::MAJOR > 2
  
  test "prevents the returned records from modification" do
    @pie = ConstantPie.find(:first)
    assert @pie.frozen?
    assert !StandardPie.find(:first).frozen?
  end
  
  test "isn't affected by modifying the returned result arrays" do
    @pies = ConstantPie.all
    @pies.reject! {|pie| pie.filling =~ /Steak/}
    assert_equal StandardPie.all.collect(&:attributes), ConstantPie.all.collect(&:attributes)
  end
  
  test "it doesn't cache find queries with options" do
    @pies = StandardPie.find(:all, :lock => true)
    @pie = StandardPie.find(1, :lock => true)
    assert_queries(2) do
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all, :lock => true).collect(&:attributes)
      assert_equal @pie.attributes, ConstantPie.find(1, :lock => true).attributes
    end
    assert_queries(2) do
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all, :lock => true).collect(&:attributes)
      assert_equal @pie.attributes, ConstantPie.find(1, :lock => true).attributes
    end
  end
  
  test "it passes the options preventing caching to the underlying query methods" do
    assert_equal nil, ConstantPie.find(:first, :conditions => {:filling => 'unicorn'})
    assert_equal [],  ConstantPie.find(:all,   :conditions => {:filling => 'unicorn'})
  end
  
  test "it creates named class methods if a :name option is given" do
    @steak_pie = StandardPie.find_by_filling("Tasty beef steak")
    @mushroom_pie = StandardPie.find_by_filling("Tasty mushrooms with tarragon")
    @mince_pie = StandardPie.find_by_filling("Mince")
    assert_queries(1) do
      assert_equal @steak_pie.attributes, ConstantNamedPie.tasty_beef_steak.attributes
      assert_equal @mushroom_pie.attributes, ConstantNamedPie.tasty_mushrooms_with_tarragon.attributes
      assert_equal @mince_pie.attributes, ConstantNamedPie.mince.attributes
    end
    assert_raises(NoMethodError) do
      ConstantNamedPie.unicorn_and_thyme
    end
    assert_raises(NoMethodError) do
      ConstantPie.tasty_beef_steak
    end
    assert_raises(NoMethodError) do
      ActiveRecord::Base.tasty_beef_steak
    end
  end
  
  test "it supports :name_prefix and :name_suffix options" do
    @steak_pie = StandardPie.find_by_filling("Tasty beef steak")
    assert_equal @steak_pie.attributes, ConstantLongNamedPie.a_tasty_beef_steak_pie.attributes
  end
  
  test "it raises the usual exception if asked for a record with id nil" do
    assert_raises ActiveRecord::RecordNotFound do
      ConstantPie.find(nil)
    end
  end
  
  test "it raises the usual exception if asked for a nonexistant records" do
    max_id = ConstantPie.all.collect(&:id).max
    assert_raises ActiveRecord::RecordNotFound do
      ConstantPie.find(max_id + 1)
    end
  end
  
  test "it raises the usual exception if asked for a mixture of present records and nonexistant records" do
    max_id = ConstantPie.all.collect(&:id).max
    assert_raises ActiveRecord::RecordNotFound do
      ConstantPie.find([max_id, max_id + 1])
    end
  end
end
