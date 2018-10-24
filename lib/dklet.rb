require "pathname"
require "erb"

module Dklet
  class << self
    def lib_path
      Pathname(__dir__)
    end
  end
end

require "dklet/version"
require 'dklet/util'
require 'dklet/dsl'
require 'dklet/cli'
