# rubocop:disable Style/AccessorMethodName
module ManageIQ::Providers::Lenovo
  class PhysicalInfraManager::RefreshParser < EmsRefresh::Parsers::Infra
    include ManageIQ::Providers::Lenovo::RefreshHelperMethods

    require_relative './parsers/parser'

    def initialize(ems, options = nil)
      ems_auth = ems.authentications.first

      @ems               = ems
      @connection        = ems.connect(:user => ems_auth.userid,
                                       :pass => ems_auth.password,
                                       :host => ems.endpoints.first.hostname,
                                       :port => ems.endpoints.first.port)
      @options           = options || {}
      @data              = {}
      @data_index        = {}
      @host_hash_by_name = {}
    end

    # TODO: ver como recuperar a versão do lxca
    def get_parser
      version = '1.3' # TODO: substituir por código que recupera versão
      ManageIQ::Providers::Lenovo::Parser.get_instance(version)
    end

    def ems_inv_to_hashes
      log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS : [#{@ems.name}] id: [#{@ems.id} ref: #{@ems.uid_ems}]"

      $log.info("#{log_header}...")

      get_physical_servers
      discover_ip_physical_infra
      get_config_patterns

      $log.info("#{log_header}...Complete")

      @data
    end

    def self.miq_template_type
      "ManageIQ::Providers::Lenovo::PhysicalInfraManager::Template"
    end

    private

    def get_physical_servers
      nodes = all_server_resources

      nodes = nodes.map do |node|
        XClarityClient::Node.new node
      end
      process_collection(nodes, :physical_servers) { |node| get_parser.parse_physical_server(node) }
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

    def get_guest_device_ports(card)
      device_ports = []

      unless card.nil?
        port_info = card["portInfo"]
        physical_ports = port_info["physicalPorts"]
        unless physical_ports.nil?
          physical_ports.each do |physical_port|
            parsed_physical_port = get_parser.parse_physical_port(physical_port)
            logical_ports = physical_port["logicalPorts"]
            parsed_logical_port = get_parse.parse_logical_port(logical_ports[0])
            device_ports.push(get_parse.parsed_logical_port.merge(parsed_physical_port))
          end
        end
      end

      device_ports
    end

    def get_guest_device_firmware(card)
      device_fw = []

      unless card.nil?
        firmware = card["firmware"]
        unless firmware.nil?
          device_fw = firmware.map do |fw|
            get_parser.parse_firmware(fw)
          end
        end
      end

      device_fw
    end

    def get_config_patterns
      config_patterns = @connection.discover_config_pattern
      process_collection(config_patterns, :customization_scripts) { |config_pattern| get_parser.parse_config_pattern(config_pattern) }
    end

    def format_mac_address(mac_address)
      mac_address.scan(/\w{2}/).join(":")
    end

    def all_server_resources
      return @all_server_resources if @all_server_resources

      cabinets = @connection.discover_cabinet(:status => "includestandalone")

      nodes = cabinets.map(&:nodeList).flatten
      nodes = nodes.map do |node|
        node["itemInventory"]
      end.flatten

      chassis = cabinets.map(&:chassisList).flatten

      nodes_chassis = chassis.map do |chassi|
        chassi["itemInventory"]["nodes"]
      end.flatten
      nodes_chassis = nodes_chassis.select { |node| node["type"] != "SCU" }

      nodes += nodes_chassis

      @all_server_resources = nodes
    end

    def discover_ip_physical_infra
      hostname = URI.parse(@ems.hostname).host || URI.parse(@ems.hostname).path
      if @ems.ipaddress.blank?
        resolve_ip_address(hostname, @ems)
      end
      if @ems.hostname_ipaddress?(hostname)
        resolve_hostname(hostname, @ems)
      end
    end

    def resolve_hostname(ipaddress, ems)
      ems.hostname = Resolv.getname(ipaddress)
      $log.info("EMS ID: #{ems.id}" + " Resolved hostname successfully.")
    rescue => err
      $log.warn("EMS ID: #{ems.id}" + " It's not possible resolve hostname of the physical infra, #{err}.")
    end

    def resolve_ip_address(hostname, ems)
      ems.ipaddress = Resolv.getaddress(hostname)
      $log.info("EMS ID: #{ems.id}" + " Resolved ip address successfully.")
    rescue => err
      $log.warn("EMS ID: #{ems.id}" + " It's not possible resolve ip address of the physical infra, #{err}.")
    end
  end
end
