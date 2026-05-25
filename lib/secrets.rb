require 'securerandom'
require 'fileutils'

module Secrets
  DIR = File.expand_path('../secrets', __dir__)

  def self.fetch(name, length: 32)
    FileUtils.mkdir_p(DIR)

    path = File.join(DIR, "#{name}.txt")

    unless File.exist?(path)
      File.write(path, "#{SecureRandom.base64(length)}\n")
    end

    File.read(path).strip
  end
end
