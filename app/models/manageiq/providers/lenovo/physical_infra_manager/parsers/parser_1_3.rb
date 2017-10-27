=begin
  Class that provides parse of data of lxca API version 1.3
=end
module ManageIQ::Providers::Lenovo
  class Parser_1_3 < ManageIQ::Providers::Lenovo::Parser

    def physical_server_dictionary
      ManageIQ::Providers::Lenovo::ParserDictionaryConstants::PHYSICAL_SERVER_1_3
    end

    def to_s
      puts "Parser versão 1.3"
    end

  end
end