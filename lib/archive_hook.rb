require "archive_hook/version"
require "archive_hook/db_runner"
require "active_record"

module ArchiveHook
  @version ||= ArchiveHook::VERSION

  @connection ||= DbRunner.connect_to_database("custom_gem_development") #(dbname, user, password)

  def self.create_migration(model_name)
    # create_schema_dumper(model_name + "s")
    create_archive_table model_name + "s"
  end

  private

  def self.create_archive_table(table_name)
    @connection.tables.each do |table|
      clone_table(table, table_name) if table === table_name
    end
  end

  def self.clone_table(table_orig, table_arch)
    archive_table_name = "archive_#{table_arch}"
    sql = "CREATE TABLE #{archive_table_name} AS
      (SELECT * FROM #{table_orig} WHERE 1=2)"
    @connection.execute(sql)
  end

  def self.create_schema_dumper(table_name)
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    filename = "#{timestamp}_archive_hook_#{table_name}_schema.rb"
    path_to_folder = "./tmp/archive_hook/"

    Dir.mkdir(path_to_folder) unless File.exists?(path_to_folder)

    Dir.each_child(path_to_folder) { |file| puts File.delete(path_to_folder + file) }

    File.open(path_to_folder + filename, "w:utf-8") do |file|
      ignore_tables = ActiveRecord::Base.connection.tables - [table_name]
      ActiveRecord::SchemaDumper.ignore_tables = ignore_tables
      ActiveRecord::SchemaDumper.dump(@connection, file)
    end
  end
end
