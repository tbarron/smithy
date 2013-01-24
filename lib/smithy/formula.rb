module Smithy
  class Formula
    attr_accessor :package, :module_setup, :formula_file_path

    def initialize(args = {})
      if args[:package]
        @package    = args[:package]
        @name       = @package.name
        @version    = @package.version
        @build_name = @package.build_name
        @prefix     = @package.prefix
      end

      @formula_file_path = args[:path] if args[:path]

      @module_setup = ''

      if ENV['MODULESHOME']
        @modulecmd = "modulecmd sh"
        @modulecmd = "#{ENV['MODULESHOME']}/bin/modulecmd sh" if File.exists?("#{ENV['MODULESHOME']}/bin/modulecmd")
        @module_setup << `#{@module_setup} #{@modulecmd} purge`
        @module_setup << ' '
        if modules
          @module_setup << `#{@module_setup} #{@modulecmd} load #{@modules.join(' ')}`
          @module_setup << ' '
        end
      end

      check_dependencies if depends_on
    end

    def check_dependencies
      @depends_on = [depends_on] if depends_on.is_a? String
      depends_on.each do |package|
        name_version_build = package.split('/')
        path = Package.all(:name => name_version_build[0], :version => name_version_build[1], :build => name_version_build[2]).first
        if path
          p = Package.new(:path => path)
          class_eval %Q{
            def #{p.name}
              @#{p.name} = Package.new(:path => "#{path}") if @#{p.name}.nil?
              @#{p.name}
            end
          }
        else
          raise "Formula #{name} depends on #{package}"
          #TODO build package instead?
        end
      end
    end

    def system(*args)
      notice args.join(' ')
      Kernel.system @module_setup + args.join(' ')
      if $?.exitstatus != 0
        raise <<-EOF.strip_heredoc
          The last command exited with status: #{$?.exitstatus}
            Formula: #{formula_file_path}
            Build Directory: #{@package.source_directory}
        EOF
      end
    end

    def run_install
      install
      notice_success "SUCCESS #{@package.prefix}"
      return true
    end

    def module_list
      if ENV['MODULESHOME']
        notice "module list"
        Kernel.system @module_setup + "#{@modulecmd} list 2>&1"
      end
    end

    # DSL and instance methods

    %w{depends_on url homepage md5 sha1 sha2 sha256 version name build_name prefix modules}.each do |attr|
      class_eval %Q{
        def self.#{attr}(value = nil, &block)
          if block_given?
            @#{attr} = block
          elsif value
            @#{attr} = value
          end

          @#{attr}
        end

        def #{attr}
          unless @#{attr}
            if self.class.#{attr}.is_a?(Proc)
              @#{attr} = instance_eval(&self.class.#{attr})
            else
              @#{attr} = self.class.#{attr}
            end
          end

          @#{attr}
        end
      }
    end

  end #class Formula
end #module Smithy
