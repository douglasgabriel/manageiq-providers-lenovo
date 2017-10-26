=begin

  Mixin responsible to provide methods to parse data in the Xclarity api
  to provider objects

=end
module ManageIQ::Providers::Lenovo
  class Parser

    require_relative 'dictionary_constants'
    require_relative 'parser_1_3'

    VERSION_PARSERS = {
      '1.3' => ManageIQ::Providers::Lenovo::Parser_1_3.new
    }

    # returns the parser of version request
    def self.get_instance(version)
      VERSION_PARSERS[version]
    end

  end
end