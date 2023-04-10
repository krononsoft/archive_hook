require "archive_hook/version"

module ArchiveHook
  class Error < StandardError; end

  class Archiver
    def initialize(dependencies: {}, archive_date:)
      @dependencies = dependencies
      @archive_date = archive_date
      @processed = []
    end

    def call(scope)
      parent = scope.model
      parent_id_groups = scope.or(expiration_scope(parent)).in_batches.map { |relation| relation.pluck(:id) }
      if @dependencies[parent].present?
        @dependencies[parent].each do |child|
          if parent_id_groups.present?
            parent_id_groups.each do |parent_ids|
              call(child.where(parent.to_s.foreign_key => parent_ids))
            end
          else
            call(child.none)
          end
        end
      else
        return if @processed.include?(parent)
        @processed << parent
      end
      parent_id_groups.each do |parent_ids|
        archive_by_scope(parent.where(id: parent_ids))
      end
    end

    private

    def archive_by_scope(scope)
      ActiveRecord::Base.connection.execute(Arel.sql(archive_records_sql(scope)))
      scope.delete_all
    end

    def archive_records_sql(scope)
      table_name = scope.table_name
      attributes_list = scope.column_names.join(",")
      <<-SQL
        INSERT INTO #{table_name}_archive (#{attributes_list})
        #{scope.select(attributes_list).to_sql}
      SQL
    end

    def expiration_scope(model)
      model.where("created_at < ?", @archive_date)
    end
  end

  class << self
    def archive(root, archive_date, dependencies)
      Archiver.new(dependencies: dependencies, archive_date: archive_date).call(root.none)
    end
  end
end