class EmbeddedAnsible
  include Vmdb::Logging

  ANSIBLE_ROLE           = "embedded_ansible".freeze
  WAIT_FOR_ANSIBLE_SLEEP = 1.second

  def self.new
    require "ansible_tower_client"
    self == EmbeddedAnsible ? detect_available_platform.new : super
  end

  def self.detect_available_platform
    subclasses.detect(&:available?) || NullEmbeddedAnsible
  end

  def self.available?
    detect_available_platform != NullEmbeddedAnsible
  end

  def self.enabled?
    MiqServer.my_server(true).has_active_role?(ANSIBLE_ROLE)
  end

  def alive?
    return false unless configured? && running?
    begin
      api_connection.api.verify_credentials
    rescue AnsibleTowerClient::ClientError
      return false
    end
    true
  end

  private

  def api_connection_raw(host, port)
    admin_auth = miq_database.ansible_admin_authentication
    AnsibleTowerClient::Connection.new(
      :base_url   => URI::HTTP.build(:host => host, :path => "/api/v1", :port => port).to_s,
      :username   => admin_auth.userid,
      :password   => admin_auth.password,
      :verify_ssl => 0
    )
  end

  def find_or_create_secret_key
    miq_database.ansible_secret_key ||= SecureRandom.hex(16)
  end

  def find_or_create_admin_authentication
    miq_database.ansible_admin_authentication || miq_database.set_ansible_admin_authentication(:password => generate_password)
  end

  def find_or_create_rabbitmq_authentication
    miq_database.ansible_rabbitmq_authentication || miq_database.set_ansible_rabbitmq_authentication(:password => generate_password)
  end

  def find_or_create_database_authentication
    auth = miq_database.ansible_database_authentication
    return auth if auth

    auth = miq_database.set_ansible_database_authentication(:password => generate_password)

    database_connection.select_value("CREATE ROLE #{database_connection.quote_column_name(auth.userid)} WITH LOGIN PASSWORD #{database_connection.quote(auth.password)}")
    database_connection.select_value("CREATE DATABASE awx OWNER #{database_connection.quote_column_name(auth.userid)} ENCODING 'utf8'")

    auth
  end

  def generate_password
    SecureRandom.base64(18).tr("+/", "-_")
  end

  def miq_database
    MiqDatabase.first
  end

  def database_connection
    ActiveRecord::Base.connection
  end
end

Dir.glob(File.join(File.dirname(__FILE__), "embedded_ansible/*.rb")).each { |f| require_dependency f }
