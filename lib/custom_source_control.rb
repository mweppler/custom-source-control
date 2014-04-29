#!/usr/bin/env ruby

require 'fileutils'
require 'openssl'

class CustomSourceControl

  ['manifest', 'metadata'].each do |method|
    define_method("hash_and_copy_#{method}") do
      file = File.join('.esc', "__#{method}__")
      hash = hash_for_file(file)
      FileUtils.cp(file, File.join('.esc', hash))
      hash
    end
  end

  ['__manifest__', '__metadata__', 'HEAD'].each do |ctl_file|
    define_method("#{ctl_file.downcase.gsub('_', '')}_exists?") do
      File.exists? File.join('.esc', ctl_file)
    end
  end

  def checkout(snapshot = nil)
    manifest_hash = ''
    File.open(File.join('.esc', snapshot), 'r') do |file|
      file.readlines.each do |entry|
        manifest_hash = $1 if entry =~ /Snapshot Manifest: (\w{40})/
      end
    end

    entries = []
    File.open(File.join('.esc', manifest_hash), 'r') do |file|
      file.readlines.each do |entry|
        entry =~ /(.*?) => (.*?) \(new\)\n?/
        entries << { :hash => $1, :pathname => $2 } if $1
      end
    end
    entries.each do |entry|
      copy_entry_to_working_directory entry
    end
  end

  def copy_entry_to_repository(manifest_entry)
    FileUtils.cp(manifest_entry[:pathname], File.join('.esc', manifest_entry[:hash]), { :preserve => true })
  end

  def copy_entry_to_working_directory(manifest_entry)
    FileUtils.cp(File.join('.esc', manifest_entry[:hash]), manifest_entry[:pathname], { :preserve => true })
  end

  def copy_manifest_files_to_repository
    entries = []
    File.open(File.join('.esc', '__manifest__'), 'r') do |file|
      file.readlines.each do |entry|
        entry =~ /(.*?) => (.*?) \(new\)\n?/
        entries << { :hash => $1, :pathname => $2 } if $1
      end
    end
    entries.each do |entry|
      copy_entry_to_repository entry
    end
  end

  def cwd_files
    all_files_wildcard = File.join '**', '*'
    Dir.glob(all_files_wildcard)
  end

  def cwd_hashes
    cwd_files.inject({}) { |hash, file| hash[file] = hash_for_file(file); hash }
  end
  alias_method :refactor_cwd_hashes, :cwd_hashes

  def initial_cwd_hashes
    sha1 = OpenSSL::Digest::SHA1.new
    hashes = {}
    cwd_files.each do |file|
      hashes[file] = sha1.hexdigest(File.read(file))
      sha1.reset
    end
    hashes
  end

  def deltas
    new, existing = [], []
    cwd_hashes.each do |key, value|
      if repository_file_list.include? key
        existing << key
      else
        new << key
      end
    end
    { :new => new, :existing => existing }
  end

  def hash_for_file(file = nil)
    sha1 = OpenSSL::Digest::SHA1.new
    sha1.hexdigest(File.read(file))
  end

  def head_contents
    File.open('.esc/HEAD', 'r') { |f| f.read }
  end

  def initialize_repository
    Dir.mkdir '.esc'
    File.new(File.join('.esc', 'HEAD'), 'w')
  end

  def manifest_contents(manifest = nil)
    manifest ||= '__manifest__'
    File.open(".esc/#{manifest}", 'r') { |f| f.read }
  end

  def repository_exists?
    Dir.exists? '.esc'
  end

  def repository_file_exists?(filename = nil)
    File.exists? File.join('.esc', filename)
  end

  def repository_file_list
    all_files_wildcard = File.join '.esc', '*'
    Dir.glob(all_files_wildcard).map { |pathname| File.basename pathname }
  end

  def snapshot
    write_manifest
    copy_manifest_files_to_repository
    manifest_hash = hash_and_copy_manifest
    write_metadata manifest_hash
    metadata_hash = hash_and_copy_metadata
    update_head metadata_hash
  end

  def update_head(metadata_hash = nil)
    File.open(File.join('.esc', 'HEAD'), 'w') do |file|
      file.write metadata_hash
    end
  end

  def verify_manifest(manifest = nil)
    manifest ||= '__manifest__'
    File.open(File.join('.esc', manifest)) do |file|
      repo_files = repository_file_list()
      file.readlines.each do |entry|
        return false unless repo_files.include? entry[0...40]
      end
    end
    true
  end

  def write_manifest
    file_deltas = deltas
    file_list   = []
    file_deltas[:new].each      { |filename| file_list << "#{hash_for_file filename} => #{filename} (new)"}
    file_deltas[:existing].each { |filename| file_list << "#{hash_for_file filename} => #{filename} (existing)"}
    File.open(File.join('.esc', '__manifest__'), 'w') do |file|
      file_list.sort!.each { |entry| file.puts entry }
    end
  end

  def write_metadata(manifest_hash = nil)
    File.open(File.join('.esc', '__metadata__'), 'w') do |file|
      file.puts "Snapshot Manifest: #{manifest_hash}"
      file.puts "Snapshot Parent:   #{(head_contents.empty?) ? 'root' : head_contents}"
      file.puts "Snapshot Taken:    #{Time.now}"
    end
  end
end


# Benchmark the cwd_hashes methods
def benchmark_cwd_hashes
  repo_dir = File.join(File.dirname(__FILE__), '../', 'specs', 'test_dir')
  Dir.chdir repo_dir

  10000.times do |idx|
    File.open("file_#{idx}", 'w') do |f|
      f.write "I am file #{idx}"
    end
  end

  csc = CustomSourceControl.new
  csc.initialize_repository
  csc.snapshot

  require 'benchmark'
  Benchmark.bmbm do |x|
    x.report("initial:")  { csc.initial_cwd_hashes }
    x.report("refactor:") { csc.refactor_cwd_hashes }
  end

  if Dir.exists? '.esc'
    FileUtils.rm_rf '.esc'
    FileUtils.rm Dir.glob('file_*')
  end
end


if __FILE__ == $0
  unless ['--benchmark', '--checkout', '--initialize', '--snapshot'].include? ARGV[0]
    puts "#{ARGV[0]} is not a subcommand."
    exit 1
  end

  csc = CustomSourceControl.new
  case ARGV[0]
  when '--benchmark'
    benchmark_cwd_hashes
  when '--checkout'
    if ARGV[1]
      csc.checkout ARGV[1]
    else
      puts "'checkout' subcommand takes a second argument, SHA1 of the metadata file to checkout."
      exit 1
    end
  when '--initialize'
    csc.initialize_repository
  when '--snapshot'
    csc.snapshot
  end
end
