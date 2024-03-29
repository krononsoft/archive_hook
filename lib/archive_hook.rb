require "archive_hook/version"

module ArchiveHook
  class ScopeArchiver
    def initialize(dependencies: {})
      @dependencies = dependencies
    end

    def call(scope)
      parent = scope.model
      parent_id_groups = scope.in_batches.map { |relation| relation.pluck(:id) }
      return if parent_id_groups.empty?

      archive_children(parent, parent_id_groups)
      parent_id_groups.each do |parent_ids|
        archive_by_scope(parent.unscoped.where(id: parent_ids))
      end
    end

    private

    def archive_children(parent, parent_id_groups)
      return unless @dependencies[parent] && @dependencies[parent][:children].present?

      @dependencies[parent][:children].each do |child|
        parent_id_groups.each do |parent_ids|
          call(child.unscoped.where(parent.to_s.foreign_key => parent_ids))
        end
      end
    end

    def archive_by_scope(scope)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(Arel.sql(archive_records_sql(scope)))
        scope.delete_all
      end
    end

    def archive_records_sql(scope)
      table_name = scope.table_name
      attributes_list = scope.column_names.join(",")
      <<-SQL
        INSERT INTO #{table_name}_archive (#{attributes_list})
        #{scope.select(attributes_list).to_sql}
      SQL
    end
  end

  class ScopeRestorer
    def initialize(dependencies: {})
      @dependencies = dependencies
    end

    def call(scope)
      parent = scope.model
      table_name = "#{scope.table_name}_archive as #{scope.table_name}"
      parent_id_groups = scope.from(table_name).in_batches.map { |relation| relation.pluck(:id) }
      parent_id_groups.each do |parent_ids|
        restore_by_ids(parent, parent_ids)
      end
      restore_children(parent, parent_id_groups)
    end

    private

    def restore_children(parent, parent_id_groups)
      return unless @dependencies[parent] && @dependencies[parent][:children].present?

      @dependencies[parent][:children].each do |child|
        if parent_id_groups.present?
          parent_id_groups.each do |parent_ids|
            call(child.unscoped.where(parent.to_s.foreign_key => parent_ids))
          end
        else
          call(child.none)
        end
      end
    end

    def restore_by_ids(model, ids)
      table_name = model.table_name
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(Arel.sql(restore_records_sql(model, ids)))
        ActiveRecord::Base.connection.execute(Arel.sql <<-SQL
          DELETE FROM #{table_name}_archive WHERE id IN (#{ids.join(', ')})
        SQL
        )
      end
    end

    def restore_records_sql(model, ids)
      table_name = model.table_name
      attributes_list = model.column_names.join(",")
      <<-SQL
        INSERT INTO #{table_name} (#{attributes_list})
        SELECT #{attributes_list} FROM #{table_name}_archive WHERE id IN (#{ids.join(', ')})
      SQL
    end
  end

  class << self
    def archive(root, archive_date, dependencies)
      column = dependencies[root] && dependencies[root][:column] || :created_at
      base_scope = root.where("#{column} < ?", archive_date)
      ScopeArchiver.new(dependencies: dependencies).call(base_scope)
    end

    def archive_scope(scope, dependencies = {})
      ScopeArchiver.new(dependencies: dependencies).call(scope)
    end

    def restore_scope(scope, dependencies = {})
      ScopeRestorer.new(dependencies: dependencies).call(scope)
    end
  end
end
