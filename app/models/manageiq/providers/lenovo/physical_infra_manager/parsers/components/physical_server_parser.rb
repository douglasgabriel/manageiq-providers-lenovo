require_relative 'component_parser'
require_relative 'network_devices_parser'

module ManageIQ::Providers::Lenovo
  module Parsers
    class PhysicalServerParser < ComponentParser
      class << self
        #
        # parse a node object to a hash with physical servers data
        #
        # @param [XClarityClient::Node] node - object containing physical server data
        #
        # @return [Hash] containing the physical server information
        #
        def parse_physical_server(node)
          result = parse(node, ParserDictionaryConstants::PHYSICAL_SERVER)

          result[:vendor]                     = "lenovo"
          result[:type]                       = ParserDictionaryConstants::MIQ_TYPES["physical_server"]
          result[:power_state]                = ParserDictionaryConstants::POWER_STATE_MAP[node.powerStatus]
          result[:health_state]               = ParserDictionaryConstants::HEALTH_STATE_MAP[node.cmmHealthState.nil? ? node.cmmHealthState : node.cmmHealthState.downcase]
          result[:host]                       = get_host_relationship(node.serialNumber)
          result[:location_led_state]         = find_loc_led_state(node.leds)
          result[:computer_system][:hardware] = get_hardwares(node)

          return node.uuid, result
        end

        private

        # Assign a physicalserver and host if server already exists and
        # some host match with physical Server's serial number
        def get_host_relationship(serial_number)
          Host.find_by(:service_tag => serial_number) ||
            Host.joins(:hardware).find_by('hardwares.serial_number' => serial_number)
        end

        # Find the identification led state
        def find_loc_led_state(leds)
          identification_led = leds.to_a.find { |led| ParserDictionaryConstants::PROPERTIES_MAP[:led_identify_name].include?(led["name"]) }
          identification_led.try(:[], "state")
        end

        def get_hardwares(node)
          {
            :disk_capacity   => get_disk_capacity(node),
            :memory_mb       => get_memory_info(node),
            :cpu_total_cores => get_total_cores(node),
            :firmwares       => get_firmwares(node),
            :guest_devices   => get_guest_devices(node)
          }
        end

        def get_disk_capacity(node)
          total_disk_cap = 0
          node.raidSettings&.each do |storage|
            storage['diskDrives']&.each do |disk|
              total_disk_cap += disk['capacity'] unless disk['capacity'].nil?
            end
          end
          total_disk_cap.positive? ? total_disk_cap : nil
        end

        def get_memory_info(node)
          total_memory_gigabytes = node.memoryModules&.reduce(0) { |total, mem| total + mem['capacity'] }
          total_memory_gigabytes * 1024 # convert to megabytes
        end

        def get_total_cores(node)
          node.processors&.reduce(0) { |total, pr| total + pr['cores'] }
        end

        def get_firmwares(node)
          node.firmware&.map { |firmware| parse_firmware(firmware) }
        end

        def get_guest_devices(node)
          guest_devices = NetworkDevicesParser.get_addin_cards(node)
          guest_devices << parse_management_device(node)
        end

        def parse_firmware(firmware)
          {
            :name         => "#{firmware["role"]} #{firmware["name"]}-#{firmware["status"]}",
            :build        => firmware["build"],
            :version      => firmware["version"],
            :release_date => firmware["date"],
          }
        end

        def parse_management_device(node)
          {
            :device_type => "management",
            :network     => parse_management_network(node),
            :address     => node.macAddress
          }
        end

        def parse_management_network(node)
          {
            :ipaddress   => node.mgmtProcIPaddress,
            :ipv6address => node.ipv6Addresses.nil? ? node.ipv6Addresses : node.ipv6Addresses.join(", ")
          }
        end
      end
    end
  end
end
