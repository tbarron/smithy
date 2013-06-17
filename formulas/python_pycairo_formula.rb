class PythonPycairoFormula < Formula
  homepage "http://cairographics.org/pycairo/"
  url "http://cairographics.org/releases/pycairo-1.2.0.tar.gz"

  depends_on do
    case build_name
    when /python3.3/
      [ "python/3.3.0", "python_pygobject"]
    when /python2.7/
      [ "python/2.7.3", "python_pygobject", "python_pygtk" ]
    when /python2.6/
      [ ]
    end
  end

  modules do
    case build_name
    when /python3.3/
      [ "python/3.3.0" ]
    when /python2.7/
      [ "python/2.7.3", "python_pygtk", "python_pygobject"]
    when /python2.6/
      [ ]
    end
  end


  def install
    module_list

    python_binary = "python"
    libdirs = []
    case build_name
    when /python3.3/
      python_binary = "python3.3"
      libdirs << "#{prefix}/lib/python3.3/site-packages"
      # libdirs << "#{python_pygobject.prefix}/lib/python3.3/site-packages"
    when /python2.7/
      libdirs << "#{prefix}/lib/python2.7/site-packages"
      # libdirs << "#{python_pygobject.prefix}/lib/python2.7/site-packages"
    when /python2.6/
      libdirs << "#{prefix}/lib64/python2.6/site-packages"
      libdirs << "#{python_pygobject.prefix}/lib64/python2.6/site-packages"
    end
    FileUtils.mkdir_p libdirs.first

    system "PYTHONPATH=$PYTHONPATH:#{libdirs.join(":")} ./configure --prefix=#{prefix} && make && make install"
  end

  modulefile <<-MODULEFILE.strip_heredoc
    #%Module
    proc ModulesHelp { } {
       puts stderr "<%= @package.name %> <%= @package.version %>"
       puts stderr ""
    }
    # One line description
    module-whatis "<%= @package.name %> <%= @package.version %>"

    if [ is-loaded python/3.3.0 ] {
      set BUILD python3.3.0
      set LIBDIR python3.3
    } elseif { [ is-loaded python/2.7.3 ] || [ is-loaded python/2.7.2 ] } {
      set BUILD python2.7.3
      set LIBDIR python2.7
    } else {
      set BUILD python2.6.8
      set LIBDIR python2.6
    }
    set PREFIX <%= @package.version_directory %>/$BUILD

    prepend-path PKG_CONFIG_PATH $PREFIX/lib/pkgconfig
    prepend-path PYTHONPATH      $PREFIX/lib/$LIBDIR/site-packages
  MODULEFILE
end
