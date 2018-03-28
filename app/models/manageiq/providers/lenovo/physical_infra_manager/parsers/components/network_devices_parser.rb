require_relative 'component_parser'

module ManageIQ::Providers::Lenovo
  module Parsers
    class NetworkDevicesParser < ComponentParser
      class << self
        def get_addin_cards(node)
          parsed_addin_cards = []

          cards_to_parse = select_cards_to_parse(node)

          # For each of the node's addin cards, parse the addin card and then see
          # if it is already in the list of parsed addin cards. If it is, see if
          # all of its ports are already in the existing parsed addin card entry.
          # If it's not, then add the port to the existing addin card entry and
          # don't add the card again to the list of parsed addin cards.
          # This is needed because xclarity_client seems to represent each port
          # as a separate addin card. The code below ensures that each addin
          # card is represented by a single addin card with multiple ports.
          cards_to_parse.each do |card_to_parse|
            next unless get_device_type(card_to_parse) == "ethernet"

            add_card = true
            parsed_node_addin_card = parse_addin_cards(card_to_parse)

            parsed_addin_cards.each do |addin_card|
              next unless parsed_node_addin_card[:device_name] == addin_card[:device_name] ||
                          parsed_node_addin_card[:location] == addin_card[:location]

              add_card = false
              parsed_node_addin_card[:child_devices].each do |parsed_port|
                card_found = false
                addin_card[:child_devices].each do |port|
                  if parsed_port[:device_name] == port[:device_name]
                    card_found = true
                  end
                end
                unless card_found
                  addin_card[:child_devices].push(parsed_port)
                end
              end
            end

            if add_card
              parsed_addin_cards.push(parsed_node_addin_card)
            end
          end

          # binding.pry
          parsed_addin_cards
        end

        def select_cards_to_parse(component)
          pciDevices = component.try(:pciDevices)
          addinCards = component.try(:addinCards)

          devices = []
          devices.concat(pciDevices) unless pciDevices.nil? || pciDevices.empty?
          devices.concat(addinCards) unless addinCards.nil? || addinCards.empty?
          # binding.pry
          devices
        end

        def get_device_type(card)
          device_type = ""

          unless card["name"].nil?
            card_name = card["name"].downcase
            if card_name.include?("nic") || card_name.include?("ethernet")
              device_type = "ethernet"
            end
          end
          device_type
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

        def get_guest_device_firmware(card)
          device_fw = []

          unless card.nil?
            firmware = card["firmware"]
            unless firmware.nil?
              device_fw = firmware.map do |fw|
                parse_firmware(fw)
              end
            end
          end

          device_fw
        end

        def get_guest_device_ports(card)
          device_ports = []

          unless card.nil?
            port_info = card["portInfo"]
            physical_ports = port_info["physicalPorts"]
            physical_ports&.each do |physical_port|
              parsed_physical_port = parse_physical_port(physical_port)
              logical_ports = physical_port["logicalPorts"]
              parsed_logical_port = parse_logical_port(logical_ports[0])
              device_ports.push(parsed_logical_port.merge(parsed_physical_port))
            end
          end

          device_ports
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

        def format_mac_address(mac_address)
          mac_address.scan(/\w{2}/).join(":")
        end

        def parse_firmware(firmware)
          {
            :name         => "#{firmware["role"]} #{firmware["name"]}-#{firmware["status"]}",
            :build        => firmware["build"],
            :version      => firmware["version"],
            :release_date => firmware["date"],
          }
        end
      end
    end
  end
end