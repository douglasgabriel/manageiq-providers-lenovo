require_relative 'refresh_parser'

refresher = ManageIQ::Providers::Lenovo::PhysicalInfraManager::RefreshParser.new ExtManagementSystem.first

puts "Refresh result => #{refresher.ems_inv_to_hashes}"