module DbRunner
  def self.connect_to_database(*params)
    database_params = { database: params[0], user: params[1], password: params[2], adapter: "postgresql" }
    ActiveRecord::Base.establish_connection(database_params).connection
  end

  private

  def database_params
    params.permit(:name)
  end
end
