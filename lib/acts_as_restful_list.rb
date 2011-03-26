module ActsAsRestfulList
  class << self
    def included base #:nodoc:
      base.extend ClassMethods
    end
  end

  module ClassMethods
    # +acts_as_restful_list+ makes the class it is called on automatically behave like an
    # ordered list. There are a number of options you can set:
    # * +column+: The column to use as the position column.  It's set to position by default.
    # * +scope+: The column to scope the list to.  It takes a symbol with our without the _id.
    def acts_as_restful_list(options = {})
      include InstanceMethods
      
      configuration = {:column => :position}.merge(options)
      
      before_create :set_position
      after_update :reset_order_after_update
      after_destroy :reset_order_after_destroy
      
      define_method 'position_column' do
        configuration[:column].to_s
      end

      define_method 'get_scope_condition' do |options|
        if configuration[:scope].nil?
          nil
        else
          conditions, values = [], []
          Array(configuration[:scope]).each do |scope|
            column = self.class.column_names.include?(scope.to_s) ? scope.to_s : "#{scope}_id"
            value = options[:before] ? self.send("#{column}_was") : self.send(column)
            if value.nil?
              conditions.push "#{column} IS NULL"
            else
              conditions.push "#{column} = ?"
              values.push value
            end
          end
          self.class.send(:sanitize_sql_for_conditions, [conditions.join(' AND ')].concat(values))
        end
      end

      define_method 'scope_condition' do
        self.send(:get_scope_condition, {:before => false})
      end

      define_method 'scope_condition_was' do
        self.send(:get_scope_condition, {:before => true})
      end
      
      define_method 'optimistic_locking_update' do
        self.class.column_names.include?("lock_version") ? ", lock_version = (lock_version + 1)" : ""
      end
    end
  end
  
  module InstanceMethods
    def set_position
      last_record = self.class.last( :conditions => scope_condition, :order => "#{position_column} ASC" )
      self.send( "#{position_column}=", ( last_record.nil? ? 1 : last_record.send(position_column) + 1 ) )
    end
    
    def reset_order_after_update
      if scope_condition != scope_condition_was
        self.class.update_all("#{position_column} = (#{position_column} - 1) #{optimistic_locking_update}", [scope_condition_was, "#{position_column} > #{self.send( "#{position_column}_was" )}", "id != #{id}"].compact.join(' AND '))
        self.class.update_all("#{position_column} = (#{position_column} + 1) #{optimistic_locking_update}", [scope_condition, "#{position_column} >= #{self.send( position_column )}", "id != #{id}"].compact.join(' AND '))
      elsif self.send( "#{position_column}_changed?" )
        if self.send( "#{position_column}_was" ) > self.send( position_column )
          self.class.update_all("#{position_column} = (#{position_column} + 1) #{optimistic_locking_update}", [scope_condition, "#{position_column} >= #{self.send( position_column )}", "id != #{id}", "#{position_column} < #{self.send( "#{position_column}_was" )}"].compact.join(' AND '))
        else
          self.class.update_all("#{position_column} = (#{position_column} - 1) #{optimistic_locking_update}", [scope_condition, "#{position_column} <= #{self.send( position_column )}", "#{position_column} >= #{self.send( "#{position_column}_was" )}", "id != #{id}"].compact.join(' AND '))
        end
      end
    end
    
    def reset_order_after_destroy
      self.class.update_all("#{position_column} = (#{position_column} - 1) #{optimistic_locking_update}", [scope_condition, "#{position_column} > #{self.send( position_column )}"].compact.join(' AND '))
    end
  end
end

if Object.const_defined?("ActiveRecord")
  ActiveRecord::Base.send(:include, ActsAsRestfulList)
end