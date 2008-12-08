#!/usr/bin/ruby -w

#
# Test command line options to etch client
#

require 'test/unit'
require 'etchtest'
require 'tempfile'
require 'fileutils'

class EtchOptionTests < Test::Unit::TestCase
  include EtchTests

  def setup
    # Generate a file to use as our etch target/destination
    @targetfile = Tempfile.new('etchtest').path
    #puts "Using #{@targetfile} as target file"
    
    # Generate a directory for our test repository
    @repodir = initialize_repository
    @port = start_server(@repodir)
    
    # Create a directory to use as a working directory for the client
    @testbase = tempdir
    #puts "Using #{@testbase} as client working directory"
  end
  
  def test_dryrun
    #
    # Test killswitch (not really a command-line option, but seems to
    # fit best in this file)
    #

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end
    
    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end
    
    File.open("#{@repodir}/killswitch", 'w') do |file|
      file.write('killswitch test')
    end
    
    # Run etch
    #puts "Running killswitch test"
    sleep 3
    puts "#"
    puts "# Errors expected here"
    puts "#"
    sleep 3
    run_etch(@port, @testbase, true)

    assert_equal(origcontents, get_file_contents(@targetfile), 'killswitch')
    
    File.delete("#{@repodir}/killswitch")
    
    #
    # Test --dry-run
    #

    # Put some text into the original file so that we can make sure it is
    # not touched.
    origcontents = "This is the original text\n"
    File.open(@targetfile, 'w') do |file|
      file.write(origcontents)
    end

    FileUtils.mkdir_p("#{@repodir}/source/#{@targetfile}")
    File.open("#{@repodir}/source/#{@targetfile}/config.xml", 'w') do |file|
      file.puts <<-EOF
        <config>
          <file>
            <warning_file/>
            <source>
              <plain>source</plain>
            </source>
          </file>
        </config>
      EOF
    end

    sourcecontents = "This is a test\n"
    File.open("#{@repodir}/source/#{@targetfile}/source", 'w') do |file|
      file.write(sourcecontents)
    end

    # Run etch
    #puts "Running --dry-run test"
    run_etch(@port, @testbase, false, '--dry-run')

    assert_equal(origcontents, get_file_contents(@targetfile), '--dry-run')
  end

  def teardown
    stop_server
    remove_repository(@repodir)
    FileUtils.rm_rf(@testbase)
    FileUtils.rm_rf(@targetfile)
  end
end

