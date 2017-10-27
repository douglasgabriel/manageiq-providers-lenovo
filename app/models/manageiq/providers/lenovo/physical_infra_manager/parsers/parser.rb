# Mixin responsible to provide methods to parse data in the Xclarity api
# to provider objects.
module ManageIQ::Providers::Lenovo
  class Parser

    require_relative 'parser_dictionary_constants'
    require_relative 'parser_1_3'

    # suported API versions
    VERSION_PARSERS = {
      '1.3' => ManageIQ::Providers::Lenovo::Parser_1_3
    }.freeze

    # returns the parser of api version request
    # see the +VERSION_PARSERS+ to know what versions are suporteds
    def self.get_instance(version)
      version_parser = VERSION_PARSERS[version]

      raise "This version is not supported" if version_parser.nil?

      version_parser.new
    end
    
    # parse a json containing physical server data to a hash
    # +node+ - json containing physical server data
    def parse_physical_server(node)
      
      new_result = {
        :type                   => "ManageIQ::Providers::Lenovo::PhysicalInfraManager::PhysicalServer",
        :name                   => node.name,
        :ems_ref                => node.uuid,
        :uid_ems                => node.uuid,
        :hostname               => node.hostname,
        :product_name           => node.productName,
        :manufacturer           => node.manufacturer,
        :machine_type           => node.machineType,
        :model                  => node.model,
        :serial_number          => node.serialNumber,
        :field_replaceable_unit => node.FRU,
        :host                   => get_host_relationship(node.serialNumber),
        :power_state            => power_state_map(node.powerStatus),
        :health_state           => health_state_map(node.cmmHealthState.nil? ? node.cmmHealthState : node.cmmHealthState.downcase),
        :vendor                 => "lenovo",
        :computer_system        => {
          :hardware => {
            :guest_devices => [],
            :firmwares     => [] # Filled in later conditionally on what's available
          }
        },
        :asset_details          => parse_asset_details(node),
        :location_led_state    	=> find_loc_led_state(node.leds)
      }
      new_result[:computer_system][:hardware] = get_hardwares(node)
      return node.uuid, new_result
    end

    def parse_config_pattern(config_pattern)
      new_result =
        {
          :manager_ref  => config_pattern.id,
          :name         => config_pattern.name,
          :description  => config_pattern.description,
          :user_defined => config_pattern.userDefined,
          :in_use       => config_pattern.inUse
        }
      return config_pattern.id, new_result
    end

    def parse_physical_port(port)
      {
        :device_type => "physical_port",
        :device_name => "Physical Port #{port['physicalPortIndex']}"
      }
    end

    def parse_logical_port(port)
      {
        :address => format_mac_address(port["addresses"])
      }
    end

    private

    # Assign a physicalserver and host if server already exists and
    # some host match with physical Server's serial number
    def get_host_relationship(serial_number)
      Host.find_by(:service_tag => serial_number)
    end

    def parse_asset_details(node)
      {
        :contact          => node.contact,
        :description      => node.description,
        :location         => node.location['location'],
        :room             => node.location['room'],
        :rack_name        => node.location['rack'],
        :lowest_rack_unit => node.location['lowestRackUnit'].to_s
      }
    end

    def find_loc_led_state(leds)
      loc_led_state = ""
      unless leds.nil?
        leds.each do |led|
          if led["name"] == "Identify"
            loc_led_state = led["state"]
            break
          end
        end
      end
      loc_led_state
    end

    def get_hardwares(node)
      {
        :memory_mb       => get_memory_info(node),
        :cpu_total_cores => get_total_cores(node),
        :firmwares       => get_firmwares(node),
        :guest_devices   => get_guest_devices(node)
      }
    end

    def get_total_cores(node)
      total_cores = 0
      processors = node.processors
      unless processors.nil?
        processors.each do |pr|
          total_cores += pr['cores']
        end
      end
      total_cores
    end

    def get_memory_info(node)
      total_memory = 0
      memory_modules = node.memoryModules
      unless memory_modules.nil?
        memory_modules.each do |mem|
          total_memory += mem['capacity'] * 1024
        end
      end
      total_memory
    end

    def get_firmwares(node)
      firmwares = node.firmware
      unless firmwares.nil?
        firmwares = firmwares.map do |firmware|
          parse_firmware(firmware)
        end
      end
      firmwares
    end

    def get_guest_devices(node)
      # Retrieve the addin cards associated with the node
      addin_cards = get_addin_cards(node)
      guest_devices = addin_cards.map do |addin_card|
        addin_card
      end

      # Retrieve management devices
      guest_devices.push(parse_management_device(node))

      guest_devices
    end

    def parse_firmware(firmware)
      {
        :name         => "#{firmware["role"]} #{firmware["name"]}-#{firmware["status"]}",
        :build        => firmware["build"],
        :version      => firmware["version"],
        :release_date => firmware["date"],
      }
    end

    def get_addin_cards(node)
      parsed_addin_cards = []

      # For each of the node's addin cards, parse the addin card and then see
      # if it is already in the list of parsed addin cards. If it is, see if
      # all of its ports are already in the existing parsed addin card entry.
      # If it's not, then add the port to the existing addin card entry and
      # don't add the card again to the list of parsed addin cards.
      # This is needed because xclarity_client seems to represent each port
      # as a separate addin card. The code below ensures that each addin
      # card is represented by a single addin card with multiple ports.
      node_addin_cards = node.addinCards
      unless node_addin_cards.nil?
        node_addin_cards.each do |node_addin_card|
          if get_device_type(node_addin_card) == "ethernet"
            add_card = true
            parsed_node_addin_card = parse_addin_cards(node_addin_card)

            parsed_addin_cards.each do |addin_card|
              if parsed_node_addin_card[:device_name] == addin_card[:device_name]
                if parsed_node_addin_card[:location] == addin_card[:location]
                  parsed_node_addin_card[:child_devices].each do |parsed_port|
                    card_found = false

                    addin_card[:child_devices].each do |port|
                      if parsed_port[:device_name] == port[:device_name]
                        card_found = true
                      end
                    end

                    unless card_found
                      addin_card[:child_devices].push(parsed_port)
                      add_card = false
                    end
                  end
                end
              end
            end

            if add_card
              parsed_addin_cards.push(parsed_node_addin_card)
            end
          end
        end
      end

      parsed_addin_cards
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

    def parse_addin_cards(addin_card)
      {
        :device_name            => addin_card["productName"],
        :device_type            => get_device_type(addin_card),
        :firmwares              => get_guest_device_firmware(addin_card),
        :manufacturer           => addin_card["manufacturer"],
        :field_replaceable_unit => addin_card["FRU"],
        :location               => "Bay #{addin_card['slotNumber']}",
        :child_devices          => get_guest_device_ports(addin_card)
      }
    end

    def power_state_map(state)
      ManageIQ::Providers::Lenovo::ParserDictionaryConstants::POWER_STATE_MAP[state]
    end

    def health_state_map(state)
      ManageIQ::Providers::Lenovo::ParserDictionaryConstants::HEALTH_STATE_MAP[state]
    end

  end
end