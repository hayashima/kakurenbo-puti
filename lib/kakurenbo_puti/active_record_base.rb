require 'tapp'
module KakurenboPuti
  # Extension module of ActiveRecord::Base
  module ActiveRecordBase
    # Enable soft-delete.
    # @raise [StandardException] if Not found soft-deleted date column.
    #
    # @param [Symbol]        column                 Name of soft-deleted date column.
    # @param [Array<Symbol>] dependent_associations Names of dependency association.
    def soft_deletable(column: :soft_destroyed_at, dependent_associations: [])
      Initializers.create_callbacks self
      Initializers.create_column_name_accessors self, column
      Initializers.create_scopes self, dependent_associations

      include InstanceMethods
      extend ClassMethods
    end

    module Initializers
      # Create callbacks.
      # @param [Class] target_class Class of target.
      def self.create_callbacks(target_class)
        target_class.class_eval do
          define_model_callbacks :restore
          define_model_callbacks :soft_destroy
        end
      end

      # Create attribute_accessors of column_name.
      # @param [Class]  target_class Class of target.
      # @param [Symbol] column       Name of column.
      def self.create_column_name_accessors(target_class, column)
        target_class.class_eval do
          define_singleton_method(:soft_delete_column) { column }
          delegate :soft_delete_column, to: target_class.name.to_sym
        end
      end

      # Create scopes.
      # @param [Class]         target_class           Class of target.
      # @param [Array<Symbol>] dependent_associations Names of dependency association.
      def self.create_scopes(target_class, dependent_associations)
        target_class.class_eval do
          scope :only_soft_destroyed, -> { where(self.arel_table[:id].not_in(without_soft_destroyed.select(self.arel_table[:id]).arel)) }
          scope :without_soft_destroyed, (lambda do
            dependent_associations.inject(where(soft_delete_column => nil)) do |relation, name|
              association = relation.klass.reflect_on_all_associations.find{|a| a.name == name }
              if association.klass.method_defined?(:soft_delete_column)
                relation.joins(name).merge(association.klass.without_soft_destroyed)
              else
                relation.joins(name)
              end
            end
          end)
        end
      end
    end

    module InstanceMethods
      # Restore model.
      # @return [Boolean] Return true if it is success.
      def restore
        true.tap { restore! }
      rescue
        false
      end

      # Restore model.
      # @raise [ActiveRecordError]
      def restore!
        run_callbacks(:restore) { update_column soft_delete_column, nil; self }
      end

      # Soft-Delete model.
      # @return [Boolean] Return true if it is success.
      def soft_destroy
        true.tap { soft_destroy! }
      rescue
        false
      end

      # Soft-Delete model.
      # @raise [ActiveRecordError]
      def soft_destroy!
        run_callbacks(:soft_destroy) { touch soft_delete_column; self }
      end

      # Check if model is soft-deleted.
      # @return [Boolean] Return true if model is soft-deleted.
      def soft_destroyed?
        self.class.unscoped.only_soft_destroyed.where(id: id).exists?
      end
    end

    module ClassMethods
      def soft_destroy_all(conditions = nil)
        if conditions
          where(conditions).soft_destroy_all
        else
          scoped.each {|object| object.soft_destroy }
        end
      end
    end
  end
end
