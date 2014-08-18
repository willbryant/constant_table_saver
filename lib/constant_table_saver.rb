require 'active_record/fixtures' # so we can hook it & reset our cache afterwards
require 'active_support/core_ext/object/to_param'

module ConstantTableSaver
  module BaseMethods
    def constant_table(options = {})
      options.assert_valid_keys(:name, :name_prefix, :name_suffix)
      class_attribute :constant_table_options, :instance_writer => false
      self.constant_table_options = options
      
      if ActiveRecord::VERSION::MAJOR == 3
        extend ActiveRecord3ClassMethods
      else
        extend ActiveRecord4ClassMethods
      end
      extend ClassMethods
      extend NameClassMethods if constant_table_options[:name]
      
      klass = defined?(ActiveRecord::FixtureSet) ? ActiveRecord::FixtureSet : ActiveRecord::Fixtures
      class <<klass
        # normally, create_fixtures method gets called exactly once - but unfortunately, it
        # loads the class and does a #respond_to?, which causes us to load and cache before
        # the new records are added, so we need to reset our cache afterwards.
        def create_fixtures_with_constant_tables(*args)
          create_fixtures_without_constant_tables(*args).tap { ConstantTableSaver.reset_all_caches }
        end
        def reset_cache_with_constant_tables(*args)
          reset_cache_without_constant_tables(*args).tap     { ConstantTableSaver.reset_all_caches }
        end
        alias_method_chain :create_fixtures, :constant_tables
        alias_method_chain :reset_cache,     :constant_tables
      end unless klass.respond_to?(:create_fixtures_with_constant_tables)
    end
  end

  def self.reset_all_caches
    klasses = ActiveRecord::Base.respond_to?(:descendants) ? ActiveRecord::Base.descendants : ActiveRecord::Base.send(:subclasses)
    klasses.each {|klass| klass.reset_constant_record_cache! if klass.respond_to?(:reset_constant_record_cache!)}
  end
  
  module ClassMethods
    # Resets the cached records.  Remember that this only affects this process, so while this
    # is useful for running tests, it's unlikely that you can use this in production - you
    # would need to call it on every Rails instance on every Rails server.  Don't use this
    # plugin on if the table isn't really constant!
    def reset_constant_record_cache!
      @constant_record_methods.each {|method_id| (class << self; self; end;).send(:remove_method, method_id)} if @constant_record_methods
      @cached_records = @cached_records_by_id = @constant_record_methods = @cached_blank_scope = @find_by_sql = nil
    end
  end

  module ActiveRecord4ClassMethods
    def find_by_sql(sql, binds = [])
      @find_by_sql ||= {
        :all   => all.to_sql,
        :id    => relation.where(relation.table[primary_key].eq(connection.substitute_at(columns_hash[primary_key], 1))).limit(1),
        :first => relation.order(relation.table[primary_key].asc).limit(1).to_sql,
        :last  => relation.order(relation.table[primary_key].desc).limit(1).to_sql,
      }

      if binds.empty?
        _sql = _to_sql_with_binds(sql, binds)

        if _sql == @find_by_sql[:all]
          return @cached_records ||= super(relation.to_sql).each(&:freeze)
        elsif _sql == @find_by_sql[:first]
          return [relation.to_a.first].compact
        elsif _sql == @find_by_sql[:last]
          return [relation.to_a.last].compact
        end

      elsif binds.length == 1 &&
            binds.first.first.is_a?(ActiveRecord::ConnectionAdapters::Column) &&
            binds.first.first.name == primary_key &&
            _to_sql_with_binds(sql, binds) == _to_sql_with_binds(@find_by_sql[:id], binds) # we have to late-render the find(id) SQL because mysql2 on 4.1 and later requires the bind variables to render the SQL, and errors out with a nil dereference otherwise
        @cached_records_by_id ||= relation.to_a.index_by {|record| record.id.to_param}
        return [@cached_records_by_id[binds.first.last.to_param]].compact
      end

      super
    end

    def _to_sql_with_binds(sql, binds)
      if sql.respond_to?(:to_sql)
        # an arel object
        connection.to_sql(sql, binds)
      else
        # a plain string
        sql
      end
    end

    def relation
      super.tap do |s|
        class << s
          # we implement find_some here because we'd have to use partial string matching to catch
          # this case in find_by_sql, which would be ugly.  (we do the other cases in find_by_sql
          # because it's simpler & the only place to catch things like association find queries.)
          def find_some(ids)
            return super if @values.present? # special cases such as offset and limit
            ids.collect {|id| find_one(id)}
          end
        end
      end
    end
  end

  module ActiveRecord3ClassMethods
    def scoped(options = nil)
      return super if options
      return super if respond_to?(:current_scoped_methods, true) && current_scoped_methods
      return super if respond_to?(:current_scope, true) && current_scope
      @cached_blank_scope ||= super.tap do |s|
        class << s
          def to_a
            return @records if loaded?
            super.each(&:freeze)
          end
          
          def find(*args)
            # annoyingly, the call to find to load a belongs_to passes :conditions => nil, which causes
            # the base find method to apply_finder_options and construct an entire new scope, which is
            # unnecessary and also means that it bypasses our find_one implementation (we don't interfere
            # with scopes or finds that actually do apply conditions etc.), so we check as a special case
            return find_with_ids(args.first) if args.length == 2 && args.last == {:conditions => nil}
            super
          end
      
          def find_first
            # the normal scope implementation would cache this anyway, but we force a load of all records,
            # since otherwise if the app used .first before using .all there'd be unnecessary queries
            to_a.first
          end
        
          def find_last
            # as for find_first
            to_a.last
          end
        
          def find_one(id)
            # see below re to_param
            cached_records_by_id[id.to_param] || raise(::ActiveRecord::RecordNotFound, "Couldn't find #{name} with ID=#{id}")
          end
          
          def find_some(ids)
            # see below re to_param
            ids.collect {|id| cached_records_by_id[id.to_param]}.tap do |results| # obviously since find_one caches efficiently, this isn't inefficient as it would be for real finds
              results.compact!
              raise(::ActiveRecord::RecordNotFound, "Couldn't find all #{name.pluralize} with IDs #{ids.join ','} (found #{results.size} results, but was looking for #{ids.size}") unless results.size == ids.size
            end
          end

          # in Rails 3.1 the associations code was rewritten to generalise its sql generation to support
          # more complex relationships (eg. nested :through associations).  however unfortunately, during
          # this work the implementation of belongs_to associations was changed so that it no longer calls
          # one of the basic find_ methods above; instead a vanilla target scope is constructed, a where()
          # scope to add the constraint that the primary key = the FK value is constructed, the two are
          # merged, and then #first is called on that scope.  frustratingly, all this complexity means that
          # our find_ hooks above are no longer called when dereferencing a belongs_to association; they
          # work fine and are used elsewhere, but we have to explicitly handle belongs_to target scope
          # merging to avoid those querying, which is a huge PITA.  because we want to ensure that we don't
          # end up accidentally caching other scope requests, we explicitly build a list of the possible
          # ARel constrained scopes - indexing them by their expression in SQL so that we don't need to
          # code in the list of all the possible ARel terms.  we then go one step further and make this
          # cached scope pre-loaded using the record we already have - there's sadly no external way to do
          # this so we have to shove in the instance variables.
          #
          # it will be clear that this was a very problematic ActiveRecord refactoring.
          def belongs_to_record_scopes
            @belongs_to_record_scopes ||= to_a.each_with_object({}) do |record, results|
              scope_that_belongs_to_will_want = where(table[primary_key].eq(record.id))
              scope_that_belongs_to_will_want.instance_variable_set("@loaded", true)
              scope_that_belongs_to_will_want.instance_variable_set("@records", [record])
              results[scope_that_belongs_to_will_want.to_sql] = scope_that_belongs_to_will_want
            end.freeze
          end

          def merge(other)
            if belongs_to_record_scope = belongs_to_record_scopes[other.to_sql]
              return belongs_to_record_scope
            end

            super other
          end
        
        private
          def cached_records_by_id
            # we'd like to use the same as ActiveRecord's finder_methods.rb, which uses:
            #  id = id.id if ActiveRecord::Base === id
            # but referencing ActiveRecord::Base here segfaults my ruby 1.8.7
            # (2009-06-12 patchlevel 174) [universal-darwin10.0]!  instead we use to_param.
            @cached_records_by_id ||= all.index_by {|record| record.id.to_param}
          end
        end
      end
    end
  end

  module NameClassMethods
    def define_named_record_methods
      @constant_record_methods = [] # dummy so respond_to? & method_missing don't call us again if reading an attribute causes another method_missing
      @constant_record_methods = all.collect do |record|
        method_name = "#{constant_table_options[:name_prefix]}#{record[constant_table_options[:name]].downcase.gsub(/\W+/, '_')}#{constant_table_options[:name_suffix]}"
        next if method_name.blank?
        (class << self; self; end;).instance_eval { define_method(method_name) { record } }
        method_name.to_sym
      end.compact.uniq
    end
    
    def respond_to?(method_id, include_private = false)
      super || (@constant_record_methods.nil? && @attribute_methods_generated && define_named_record_methods && super)
    end
    
    def method_missing(method_id, *arguments, &block)
      if @constant_record_methods.nil?
        define_named_record_methods
        send(method_id, *arguments, &block) # retry
      else
        super
      end
    end
  end
end

ActiveRecord::Base.send(:extend, ConstantTableSaver::BaseMethods)
