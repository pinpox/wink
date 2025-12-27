# frozen_string_literal: true

require_relative "boot"

require "rails/all"
require "pp"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Wink
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Berlin"

    # config.eager_load_paths << Rails.root.join("extras")

    # set the application name and slogan
    config.application_name = "WINK"
    config.application_slogan = "(W)o (i)st mei(n)e Winke(k)atze?"

    # Allow overriding paths via environment variables (for nix store deployment)
    if ENV["WINK_STATE_DIR"]
      state_dir = ENV["WINK_STATE_DIR"]
      config.paths["tmp"] = "#{state_dir}/tmp"
      config.paths["log"] = "#{state_dir}/log"
      config.paths["storage"] = "#{state_dir}/storage"
      config.paths["db"] = "#{state_dir}/db"
    end

    if ENV["WINK_CONFIG_DIR"]
      config.mqtt = YAML.load_file(
        File.join(ENV["WINK_CONFIG_DIR"], "mqtt.yml"),
        aliases: true
      ).fetch(Rails.env, {})
    else
      config.mqtt = config_for(:mqtt)
    end
  end
end
