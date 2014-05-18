require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), 'activerecord_count_queries'))

class StandardPie < ActiveRecord::Base
  set_table_name "pies"
end

class ConstantPie < ActiveRecord::Base
  set_table_name "pies"
  constant_table
  
  scope :filled_with_unicorn, -> { where(:filling => 'unicorn') }
  
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

class ConstantTableSaverTest < ActiveSupport::TestCase
  fixtures :all
  
  def setup
    ConstantPie.reset_constant_record_cache!
  end

  def assert_queries(num = 1)
    ::SQLCounter.clear_log
    yield
  ensure
    assert_equal num, ::SQLCounter.log.size, "#{::SQLCounter.log.size} instead of #{num} queries were executed.#{::SQLCounter.log.size == 0 ? '' : "\nQueries:\n#{::SQLCounter.log.join("\n")}"}"
  end

  def assert_no_queries(&block)
    assert_queries(0, &block)
  end

  DEPRECATED_FINDERS = ActiveRecord::VERSION::MAJOR == 3 || (ActiveRecord::VERSION::MAJOR == 4 && ActiveRecord::VERSION::MINOR == 0)

  test "it caches all() results" do
    @pies = StandardPie.all.to_a
    assert_queries(1) do
      assert_equal @pies.collect(&:attributes), ConstantPie.all.to_a.collect(&:attributes)
    end
    assert_no_queries do
      assert_equal @pies.collect(&:attributes), ConstantPie.all.to_a.collect(&:attributes)
    end
  end

  test "it caches find(:all) results" do
    @pies = StandardPie.find(:all).to_a
    assert_queries(1) do
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all).to_a.collect(&:attributes)
    end
    assert_no_queries do
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all).to_a.collect(&:attributes)
    end
  end if DEPRECATED_FINDERS

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
  end if DEPRECATED_FINDERS

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
  end if DEPRECATED_FINDERS
  
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
    @standard_pie_ingredients = IngredientForStandardPie.all.to_a
    @standard_pies = @standard_pie_ingredients.collect(&:pie)
    @constant_pie_ingredients = IngredientForConstantPie.all.to_a
    assert_queries(1) do # doesn't need to make 3 queries for 3 pie assocations!
      assert_equal @standard_pies.collect(&:attributes), @constant_pie_ingredients.collect(&:pie).collect(&:attributes)
    end
    assert_no_queries do # and once cached, needs no more
      assert_equal @standard_pies.collect(&:attributes), @constant_pie_ingredients.collect(&:pie).collect(&:attributes)
    end
  end
  
  test "it isn't affected by scopes active at the time of first load" do
    assert_equal 0, ConstantPie.filled_with_unicorn.all.to_a.size
    assert_equal 0, ConstantPie.with_unicorn_filling_scope { ConstantPie.all.to_a.length } if DEPRECATED_FINDERS
    assert_equal StandardPie.all.to_a.size, ConstantPie.all.to_a.size
  end
  
  test "it isn't affected by relational algebra active at the time of first load" do
    assert_equal 0, ConstantPie.filled_with_unicorn.all.to_a.size
    assert_equal 0, ConstantPie.where(:filling => 'unicorn').all.to_a.length
    assert_equal 2, ConstantPie.where("filling LIKE 'Tasty%'").all.to_a.length
    assert_equal StandardPie.all.to_a.size, ConstantPie.all.to_a.size
  end
  
  test "prevents the returned records from modification" do
    @pie = ConstantPie.first
    assert @pie.frozen?
    assert !StandardPie.first.frozen?
  end
  
  test "isn't affected by modifying the returned result arrays" do
    @pies = ConstantPie.all.to_a
    @pies.reject! {|pie| pie.filling =~ /Steak/}
    assert_equal StandardPie.all.to_a.collect(&:attributes), ConstantPie.all.to_a.collect(&:attributes)
  end

  test "it doesn't cache find queries on scopes with options" do
    @pies = StandardPie.select("id").all.to_a
    @pie = StandardPie.select("id").find(1)
    @second_pie = StandardPie.select("id").find(2)
    assert_queries(3) do
      assert_equal @pies.collect(&:attributes), ConstantPie.select("id").all.collect(&:attributes)
      assert_equal @pie.attributes, ConstantPie.select("id").find(1).attributes
      assert_equal [@pie, @second_pie].collect(&:attributes), ConstantPie.select("id").find([1, 2]).collect(&:attributes)
    end
    assert_queries(3) do
      assert_equal @pies.collect(&:attributes), ConstantPie.select("id").all.collect(&:attributes)
      assert_equal @pie.attributes, ConstantPie.select("id").find(1).attributes
      assert_equal [@pie, @second_pie].collect(&:attributes), ConstantPie.select("id").find([1, 2]).collect(&:attributes)
    end
  end
  
  test "it doesn't cache find queries with options" do
    @pies = StandardPie.all(:select => "id").to_a
    @pie = StandardPie.find(1, :select => "id")
    assert_queries(3) do
      assert_equal @pies.collect(&:attributes), ConstantPie.all(:select => "id").collect(&:attributes)
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all, :select => "id").collect(&:attributes)
      assert_equal @pie.attributes, ConstantPie.find(1, :select => "id").attributes
    end
    assert_queries(3) do
      assert_equal @pies.collect(&:attributes), ConstantPie.all(:select => "id").collect(&:attributes)
      assert_equal @pies.collect(&:attributes), ConstantPie.find(:all, :select => "id").collect(&:attributes)
      assert_equal @pie.attributes, ConstantPie.find(1, :select => "id").attributes
    end
  end if DEPRECATED_FINDERS
  
  test "it passes the options preventing caching to the underlying query methods" do
    assert_equal nil, ConstantPie.where(:filling => 'unicorn').first
    assert_equal nil, ConstantPie.first(:conditions => {:filling => 'unicorn'}) if DEPRECATED_FINDERS
    assert_equal nil, ConstantPie.find(:first, :conditions => {:filling => 'unicorn'}) if DEPRECATED_FINDERS
    assert_equal [],  ConstantPie.where(:filling => 'unicorn').all
    assert_equal [],  ConstantPie.all(:conditions => {:filling => 'unicorn'}) if DEPRECATED_FINDERS
    assert_equal [],  ConstantPie.find(:all,   :conditions => {:filling => 'unicorn'}) if DEPRECATED_FINDERS
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
    max_id = ConstantPie.all.to_a.collect(&:id).max
    assert_raises ActiveRecord::RecordNotFound do
      ConstantPie.find(max_id + 1)
    end
  end
  
  test "it raises the usual exception if asked for a mixture of present records and nonexistant records" do
    max_id = ConstantPie.all.to_a.collect(&:id).max
    assert_raises ActiveRecord::RecordNotFound do
      ConstantPie.find([max_id, max_id + 1])
    end
  end
end
