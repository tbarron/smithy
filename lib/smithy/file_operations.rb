module Smithy
  class FileOperations

    class << self

      def make_executable(f, options = {})
        unless options[:noop]
          p = File.stat(f).mode | 0111
          FileUtils.chmod p, f, options
        end
      end

      def set_group(f, group, options = {})
        method = :chown
        if options.has_key? :recursive
          options.reject!{|k,v| k.eql?(:recursive)}
          method = :chown_R
        end
        FileUtils.send method, nil, group, f, options
      end

      def make_group_writable(f, options = {})
        f = f.path if f.class == File
        # FileUtils.chmod_R doesn't work well for combinations of files
        # with different bitmasks, it sets everything the same
        if options.has_key? :recursive
          `chmod -R g+w #{f}` unless options[:noop]
        else
          `chmod g+w #{f}` unless options[:noop]
        end
      end

      def make_directory(d, options = {})
        if File.directory?(d)
          puts "exist ".rjust(12).bright + d
        else
          FileUtils.mkdir d, options
          puts "create ".rjust(12).bright + d
        end
      end

      def install_file(source, dest, options = {})
        if File.exists?(dest)
          if FileUtils.identical?(source, dest)
            puts "identical ".rjust(12).bright + dest
          else
            puts "conflict ".rjust(12).color(:red) + dest
            overwrite = nil
            while overwrite.nil? do
              prompt = Readline.readline("Overwrite #{dest}? (enter \"h\" for help) [ynqdh] ")
              case prompt.downcase
              when "y"
                overwrite = true
              when "n"
                overwrite = false
              when "d"
                puts `diff -w #{source} #{dest}`
              when "h"
                puts %{Y - yes, overwrite
    n - no, do not overwrite
    q - quit, abort
    d - diff, show the differences between the old and the new
    h - help, show this help}
              when "q"
                raise "Abort new package"
              #else
                #overwrite = true
              end
            end

            if overwrite == true
              puts "force ".rjust(12).bright + dest
              FileUtils.install source, dest, options
            else
              puts "skip ".rjust(12).bright + dest
            end
          end
        else
          FileUtils.install source, dest, options
          puts "create ".rjust(12).bright + dest
        end
      end

    end

  end
end
