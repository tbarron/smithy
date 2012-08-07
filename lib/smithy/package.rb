module Smithy
  class Package
    attr_accessor :arch, :root, :name, :version, :build_name
    attr_accessor :group

    def self.normalize_name(args = {})
      # Remove root and arch from the path if necessary
      p = args[:name].dup
      if args[:swroot]
        root = File.dirname args[:swroot]
        arch = File.basename args[:swroot]
      else
        root = args[:root]
        arch = args[:arch]
      end
      p.gsub! /\/?#{root}\/?/, ''
      p.gsub! /\/?#{arch}\/?/, ''
      return p
    end

    def initialize(args = {})
      @root = File.dirname(Smithy::Config.full_root)
      @arch = File.basename(Smithy::Config.full_root)

      if args[:path].try(:downcase) == 'last'
        @path = Smithy::Config.last_prefix
      else
        @path = Package.normalize_name(:name => args[:path], :root => @root, :arch => @arch)
      end
      @path =~ /(.*)\/(.*)\/(.*)$/
      @name = $1
      @version = $2
      @build_name = $3
      @group = Smithy::Config.file_group

      @group_writeable = Smithy::Config.group_writeable?
    end

    def get_binding
      binding
    end

    PackageFileNames = {
      :exception   => ".exceptions",
      :description => "description.markdown",
      :support     => "support",
      :versions    => "versions" }

    def package_support_files
      file_list = PackageFileNames.values
      file_list.collect! do |f|
        { :name => f,
          :src  => File.join(@@smithy_bin_root, "etc/templates/package", f),
          :dest => File.join(application_directory, f) }
      end
      return file_list
    end

    BuildFileNames = {
      :notes        => "build-notes",
      :dependencies => "dependencies",
      :build        => "rebuild",
      :test         => "retest",
      :env          => "remodule" }
    ExecutableBuildFileNames = [
      BuildFileNames[:build],
      BuildFileNames[:link],
      BuildFileNames[:test],
      BuildFileNames[:env]
    ]
    BuildFileERBs = [
      BuildFileNames[:env] ]

    def build_support_files
      file_list = BuildFileNames.values
      file_list.collect! do |f|
        src = File.join(@@smithy_bin_root, "etc/templates/build", f)
        src += ".erb" if BuildFileERBs.include?(f)
        { :name => f, :src => src, :dest => File.join(prefix, f) }
      end
      return file_list
    end

    def group_writeable?
      @group_writeable
    end

    def valid?
      # Name format validation
      if @name.nil? || @version.nil? || @build_name.nil? || @name.include?('/') || @version.include?('/') || @build_name.include?('/')
        raise "The package name \"#{@path}\" must be of the form: NAME/VERSION/BUILD"
        return false
      end

      # If good, save as last prefix
      Smithy::Config.save_last_prefix(qualified_name)
			return true
    end

    def qualified_name
      [@name, @version, @build_name].join('/')
    end

    def prefix
      File.join(@root, @arch, @name, @version, @build_name)
    end
    def prefix_exists?
      Dir.exist? prefix
    end
    def prefix_exists!
      raise "The package #{prefix} does not exist!" unless prefix_exists?
    end

    def rebuild_script
      File.join(prefix, BuildFileNames[:build])
    end
    def rebuild_script_exists?
      File.exist?(rebuild_script)
    end
    def rebuild_script_exists!
      raise "The script #{rebuild_script} does not exist!" unless rebuild_script_exists?
    end

    def retest_script
      File.join(prefix, BuildFileNames[:test])
    end
    def retest_script_exists?
      File.exist?(retest_script)
    end
    def retest_script_exists!
      raise "The script #{retest_script} does not exist!" unless retest_script_exists?
    end

    def remodule_script
      File.join(prefix, BuildFileNames[:env])
    end
    def remodule_script_exists?
      File.exist?(remodule_script)
    end
    def remodule_script_exists!
      raise "The script #{remodule_script} does not exist!" unless remodule_script_exists?
    end

    def application_directory
      File.join(@root, @arch, @name)
    end

    def version_directory
      File.join(@root, @arch, @name, @version)
    end

    def directories
      [ application_directory, version_directory, prefix ]
    end

    def software_root
      File.join(@root, @arch)
    end

    def lock_file
      File.join(prefix, ".lock")
    end

    def create_lock_file
      if File.exists? lock_file
        notice_fail "#{lock_file} exists, is someone else building this package? If not, use --force or delete and rerun."
        return false
      else
        FileUtils.touch(lock_file)
        FileOperations.set_group(lock_file, group)
        FileOperations.make_group_writable(lock_file) if group_writeable?
        return true
      end
    end

    def delete_lock_file
      FileUtils.rm_f(lock_file)
    end

    def run_script(args ={})
      case args[:script]
      when :build
        rebuild_script_exists!
        script = rebuild_script
        notice "Building #{prefix}"
      when :test
        retest_script_exists!
        script = retest_script
        notice "Testing #{prefix}"
      else
        return nil
      end

      notice_warn "Dry Run! (scripts will not run)" if args[:dry_run]

      ENV['SMITHY_PREFIX'] = prefix
      ENV['SW_BLDDIR'] = prefix

      unless args[:disable_logging]
        if args[:log_name]
          log_file_path = File.join(prefix, args[:log_name])
          log_file = File.open(log_file_path, 'w') unless args[:dry_run]

          FileOperations.set_group(log_file, group)
          FileOperations.make_group_writable(log_file) if group_writeable?
        end
        if args[:dry_run] || log_file != nil
          notice "Logging to #{log_file_path}"
        end
      end

      unless args[:dry_run]
        if args[:force]
          delete_lock_file
          create_lock_file
        else
          return unless create_lock_file
        end

        stdout, stderr = '',''
        exit_status = 0

        begin
          t = Open4.background(script, 0=>'', 1=>stdout, 2=>stderr)
          while t.status do
            process_ouput(stdout, stderr, args[:suppress_stdout], log_file)
            sleep 0.25
          end

          exit_status = t.exitstatus # this will throw an exception if != 0
        rescue => exception
          exit_status = exception.exitstatus
        end
        # There is usually some leftover output
        process_ouput(stdout, stderr, args[:suppress_stdout], log_file)

        log_file.close unless log_file.nil?

        if exit_status == 0
          notice_success "SUCCESS #{prefix}"
        else
          notice_fail "FAILED #{prefix}"
        end

        case args[:script]
        when :build
          if exit_status == 0
            notice "Setting permissions on installed files"
            FileOperations.set_group prefix, @group, :recursive => true
            FileOperations.make_group_writable prefix, :recursive => true if group_writeable?
          end
        when :test
        end

        delete_lock_file
      end
    end

    def extract(args = {})
      archive = args[:archive]
      temp_dir = File.join(prefix,"tmp")
      source_dir = File.join(prefix,"source")

      notice "Extracting #{archive} to #{source_dir}"

      return if args[:dry_run]

      overwrite = nil
      if File.exists?(source_dir)
        while overwrite.nil? do
          prompt = Readline.readline("Overwrite #{source_dir}? (enter \"h\" for help) [ynh] ")
          case prompt.downcase
          when "y"
            overwrite = true
          when "n"
            overwrite = false
          when "h"
            puts %{y - yes, delete existing folder and re-extract
n - no, do not overwrite
h - help, show this help}
          when "q"
            raise "Abort new package"
          end
        end
      else
        overwrite = true
      end

      if overwrite
        FileUtils.rm_rf temp_dir
        FileUtils.rm_rf source_dir
        FileUtils.mkdir temp_dir
        FileUtils.cd temp_dir

        magic_bytes = nil
        File.open(archive) do |f|
          magic_bytes = f.read(4)
        end
        case magic_bytes
        when /^PK\003\004/ # .zip archive
          `unzip #{tarfile}`
        when /^\037\213/, /^BZh/, /^\037\235/  # gzip/bz2/compress compressed
          `tar xf #{archive}`
        end

        extracted_files = Dir.glob('*')
        if extracted_files.count == 1
          FileUtils.mv extracted_files.first, source_dir
        else
          FileUtils.cd prefix
          FileUtils.mv temp_dir, source_dir
        end

        FileUtils.rm_rf temp_dir

        FileOperations.set_group source_dir, @group, :recursive => true
        FileOperations.make_group_writable source_dir, :recursive => true if group_writeable?
      end
    end

    def create(args = {})
      notice "New #{args[:stub] ? "stub " : ""}#{prefix}"
      notice_warn "Dry Run! (no files will be created or changed)" if args[:dry_run]
      options = {:noop => false, :verbose => false}
      options[:noop] = true if args[:dry_run]

      if args[:stub]
        [application_directory].each do |dir|
          FileOperations.make_directory dir, options
          FileOperations.set_group dir, group, options
          FileOperations.make_group_writable dir, options if group_writeable?
        end

        version_table_file = File.join(application_directory, ".versions")
        version_table = YAML.load_file(version_table_file) rescue {}
        version_table.merge!({version => build_name})

        FileOperations.install_from_string version_table.to_yaml, version_table_file, options.merge({:force => true})
        FileOperations.set_group version_table_file, group, options
        FileOperations.make_group_writable version_table_file, options if group_writeable?
      else

        directories.each do |dir|
          #if dir == prefix
            FileOperations.make_directory dir, options
            FileOperations.set_group dir, group, options
            FileOperations.make_group_writable dir, options if group_writeable?
          #end
        end

        all_files = build_support_files
        all_files = package_support_files + all_files if args[:web] || args[:stub]

        all_files.each do |file|
          if file[:src] =~ /\.erb$/
            FileOperations.render_erb :erb => file[:src], :binding => get_binding, :options => options, :destination => file[:dest]
          else
            FileOperations.install_file file[:src], file[:dest], options
          end
          FileOperations.set_group file[:dest], group, options
          FileOperations.make_group_writable file[:dest], options if group_writeable?
          FileOperations.make_executable file[:dest], options if file[:dest] =~ /(#{ExecutableBuildFileNames.join('|')})/
        end

      end
    end

    def module_load_prgenv
      output = ""
      ModuleFile::Environments.each do |e|
        if build_name =~ e[:regex]
          output = "module load #{e[:prg_env]}"
          break
        end
      end
      return output
    end

    def repair(args = {})
      notice "Repair #{prefix} #{args[:dry_run] ? "(dry run)" : ""}"
      options = {:noop => false, :verbose => false}
      options[:noop] = true if args[:dry_run]
      options[:verbose] = true if args[:dry_run] || args[:verbose]

      missing_package   = []
      missing_build = []

      notice "Checking support files"
      (package_support_files+build_support_files).each do |file|
        f = file[:dest]

        if File.exists?(f)
          if File.size(f) == 0
            puts "empty ".rjust(12).color(:yellow) + f
          else
            puts "exists ".rjust(12).bright + f
          end
          FileOperations.make_executable file[:dest], options if f =~ /#{ExecutableBuildFileNames.join('|')}/
        else
          puts "missing ".rjust(12).color(:red) + f

          missing_package << File.basename(f) if PackageFileNames.values.include?(File.basename(f))
          missing_build << File.basename(f) if BuildFileNames.values.include?(File.basename(f))
        end
      end

      notice "Creating missing files" if !missing_package.empty? || !missing_build.empty?

      if !missing_package.empty?
        package_support_files.each do |file|
          if missing_package.include?(file[:name])
            FileOperations.install_file file[:src], file[:dest], options
            FileOperations.set_group file[:dest], group, options
            FileOperations.make_group_writable file[:dest], options if group_writeable?
          end
        end
      end

      if !missing_build.empty?
        build_support_files.each do |file|
          if missing_build.include?(file[:name])
            FileOperations.install_file file[:src], file[:dest], options
            FileOperations.set_group file[:dest], group, options
            FileOperations.make_group_writable file[:dest], options if group_writeable?
          end
        end
      end

      notice "Setting permissions for #{prefix}"

      FileOperations.set_group prefix, group, options.merge(:recursive => true)
      FileOperations.make_group_writable prefix, options.merge(:recursive => true) if group_writeable?

      [version_directory, application_directory].each do |dir|
        FileOperations.set_group dir, group, options
        FileOperations.make_group_writable dir, options if group_writeable?
      end
    end

    def alternate_builds
      Package.alternate_builds(self.version_directory)
    end

    def self.alternate_builds(version_directory)
      version = File.basename(version_directory)
      builds = Dir.glob(version_directory+"/*")
      # Delete anything that isn't a directory
      builds.reject! { |b| ! File.directory?(b) }
      builds.reject! { |b| b =~ /#{ModuleFile::PackageModulePathName}/ }
      # Get the directory name from the full path
      builds.collect! { |b| File.basename(b) }

      stubbed_builds = YAML.load_file(File.join(File.dirname(version_directory), ".versions")) rescue {}
      if stubbed_builds[version]
        if stubbed_builds[version].class == String
          builds += [ stubbed_builds[version] ]
        else
          builds += stubbed_builds[version]
        end
      end
      builds.uniq!

      return builds.sort
    end

    def alternate_versions
      Package.alternate_builds(self.application_directory)
    end

    def self.alternate_versions(application_directory)
      versions = Dir.glob(application_directory+"/*")
      # Delete anything that isn't a directory
      versions.reject! { |b| ! File.directory?(b) }
      # Get the directory name from the full path
      versions.collect! { |b| File.basename(b) }

      stubbed_builds = YAML.load_file(File.join(application_directory, ".versions")) rescue {}
      versions += stubbed_builds.keys
      versions.uniq!

      return versions.sort
    end

    def publishable?
      Description.publishable?(application_directory)
    end

    def self.all(args = {})
      # Array of full paths to rebuild scripts
      software = Dir.glob(args[:root]+"/*/*/*/#{BuildFileNames[:build]}")
      # Remove rebuild from each path
      software.collect!{|s| s.gsub(/\/#{BuildFileNames[:build]}$/, '')}
      #TODO allow sorting?
      software.sort!
    end

    def self.all_web(args = {})
      # Find all software with descriptions
      software = Dir.glob(Smithy::Config.full_root+"/*/description*")
      software.collect!{|s| s.gsub(/\/description.*$/, '')}
      software.uniq!
      # Remove any with noweb in their exceptions file
      software.reject! do |s|
        ! Description.publishable?(s)
      end
			software.sort!
      return software
    end

    def self.create_stubs_from_modules(args = {})
      notice "Generating stubs for the following modules:"
      Format.print_column_list(stub_packages)
      proceed = nil
      while proceed.nil? do
        prompt = Readline.readline("Generate the above packages? [yn] ")
        case prompt.downcase
        when "y"
          proceed = true
        when "n"
          proceed = false
        end
      end

      raise "aborting package generation" if proceed == false

      stub_packages.each do |module_name|
        name, version = module_name.split("/")
        p = Package.new :path => "#{name}/#{version}/universal",
                        :root => global_options[:full_software_root_path],
                  :file_group => global_options[:"file-group-name"],
               :disable_group => global_options[:"disable-group-writable"]
        p.create :stub => true, :dry_run => options[:"dry-run"]

        default_module = ""
        possible_defaults = system_module_defaults.select{ |m| m =~ %r{\/#{name}\/} }
        defaulted = possible_defaults.select{ |m| m =~ %r{\(default\)$} }
        if defaulted.size > 0
          default_module = defaulted.first
        else
          default_module = possible_defaults.last
        end

        help_content = modulehelp(name)
        #help_content.gsub!(/^[\t ]+/, '')
        help_content.gsub!(/^--* Module Specific Help.*-$/, '')
        help_content.gsub!(/^===================================================================$/, '')
        help_content.gsub!(/\A\n*/, '')
        help_content = """# #{name}

Categories:

## Description

The following information is available by running `module help #{name}`

~~~~~~~~~~~~~~~~~~~~~
#{help_content}
~~~~~~~~~~~~~~~~~~~~~
"""

        help_dest = File.join(p.application_directory, "description.markdown")

        ops = {:noop => options[:"dry-run"] ? true : false}
        FileOperations.install_from_string(help_content, help_dest, ops)
        FileOperations.set_group help_dest, p.group, ops
        FileOperations.make_group_writable help_dest, ops if p.group_writeable?
      end
    end

  end
end
