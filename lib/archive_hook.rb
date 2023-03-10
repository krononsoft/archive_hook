require "archive_hook/version"
require "archive_hook/db_runner"
require "active_record"

module ArchiveHook
  @version ||= ArchiveHook::VERSION

  @connection ||= DbRunner.connect_to_database("custom_gem_development") #(dbname, user, password)

  def self.create_migration(model_name)
    create_schema_dumper(model_name + "s")
  end

  private

  def self.create_archive_table(table_name)
    # @connection.tables.each do |table|
    #   clone_table(table, table_name) if table === table_name
    # end
  end

  def self.clone_table(table_orig, table_arch)
    archive_table_name = "archive_#{table_arch}"
    sql = "CREATE TABLE #{archive_table_name} AS
      (SELECT * FROM #{table_orig} WHERE 1=2)"
    @connection.execute(sql)
  end

  def self.create_schema_dumper(table_name)
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    filename = "#{timestamp}_archive_#{table_name}_schema.rb"
    path_to_folder = "./tmp/archive_hook/"

    Dir.mkdir(path_to_folder) unless File.exists?(path_to_folder)

    Dir.each_child(path_to_folder) { |file| File.delete(path_to_folder + file) }

    File.open(path_to_folder + filename, "w:utf-8") do |file|
      ignore_tables = ActiveRecord::Base.connection.tables - [table_name]
      ActiveRecord::SchemaDumper.ignore_tables = ignore_tables
      ActiveRecord::SchemaDumper.dump(@connection, file)
    end

    migration = File.open(path_to_folder + "#{timestamp}_archive_#{table_name}.rb", "w:utf-8")

    firstString = "class Archive#{table_name.capitalize} < ActiveRecord::Migration\n  "
    secondString = "def change\n  "
    start_index = 0
    end_index = 0

    File.open(path_to_folder + filename).each_with_index do |line, index|
      start_index = index if line.include?("create_table")
      end_index = index if line.include?(" end")
      migration.write(firstString) if line.include?("ActiveRecord")
      migration.write(secondString) if line.include?('enable_extension "plpgsql"')
    end

    File.open(path_to_folder + filename).each_with_index do |line, index|
      migration.write line if index >= start_index && index <= end_index
    end

    migration.write("end")

    File.delete(path_to_folder + filename)

    ActiveRecord::Migration.migrate(path_to_folder)
  end
end
