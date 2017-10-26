require_relative 'refresh_parser'

puts ManageIQ::Providers::Lenovo::PhysicalInfraManager::RefreshParser.new.ems_inv_to_hashes