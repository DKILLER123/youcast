module Capistrano
  class Configuration
    module Servers
      # Identifies all servers that the given task should be executed on.
      # The options hash accepts the same arguments as #find_servers, and any
      # preexisting options there will take precedence over the options in
      # the task.
      def find_servers_for_task(task, options={})
        find_servers(task.options.merge(options))
      end

      # Attempts to find all defined servers that match the given criteria.
      # The options hash may include a :hosts option (which should specify
      # an array of host names or ServerDefinition instances), a :roles
      # option (specifying an array of roles), an :only option (specifying
      # a hash of key/value pairs that any matching server must match), and
      # an :exception option (like :only, but the inverse).
      #
      # Additionally, if the HOSTS environment variable is set, it will take
      # precedence over any other options. Similarly, the ROLES environment
      # variable will take precedence over other options. If both HOSTS and
      # ROLES are given, HOSTS wins.
      #
      # Usage:
      #
      #   # return all known servers
      #   servers = find_servers
      #
      #   # find all servers in the app role that are not exempted from
      #   # deployment
      #   servers = find_servers :roles => :app,
      #                :except => { :no_release => true }
      #
      #   # returns the given hosts, translated to ServerDefinition objects
      #   servers = find_servers :hosts => "jamis@example.host.com"
      def find_servers(options={})
        hosts  = server_list_from(ENV['HOSTS'] || options[:hosts])
        roles  = role_list_from(ENV['ROLES'] || options[:roles] || self.roles.keys)
        only   = options[:only] || {}
        except = options[:except] || {}

        if hosts.any?
          hosts.uniq
        else
          servers = roles.inject([]) { |list, role| list.concat(self.roles[role]) }
          servers = servers.select { |server| only.all? { |key,value| server.options[key] == value } }
          servers = servers.reject { |server| except.any? { |key,value| server.options[key] == value } }
          servers.uniq
        end
      end

    protected

      def server_list_from(hosts)
        hosts = hosts.split(/,/) if String === hosts
        Array(hosts).map { |s| String === s ? ServerDefinition.new(s.strip) : s }
      end

      def role_list_from(roles)
        roles = roles.split(/,/) if String === roles
        Array(roles).map do |role|
          role = String === role ? role.strip.to_sym : role
          raise ArgumentError, "unknown role `#{role}'" unless self.roles.key?(role)
          role
        end
      end
    end
  end
end