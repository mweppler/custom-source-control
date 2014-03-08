#!/usr/bin/env ruby

require 'fileutils'
require 'openssl'

class CustomSourceControl

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

  def hash_and_copy_manifest
    manifest_file = File.join('.esc', '__manifest__')
    hash = hash_for_file(manifest_file)
    FileUtils.cp(manifest_file, File.join('.esc', hash))
    hash
  end

  def hash_and_copy_metadata
    metadata_file = File.join('.esc', '__metadata__')
    hash = hash_for_file(metadata_file)
    FileUtils.cp(metadata_file, File.join('.esc', hash))
    hash
  end

  def hash_for_file(file = nil)
    sha1 = OpenSSL::Digest::SHA1.new
    sha1.hexdigest(File.read(file))
  end

  def head_contents
    File.open('.esc/HEAD', 'r') { |f| f.read }
  end

  def head_exists?
    File.exists? File.join('.esc', 'HEAD')
  end

  def initialize_repository
    Dir.mkdir '.esc'
    File.new(File.join('.esc', 'HEAD'), 'w')
  end

  def manifest_contents(manifest = nil)
    manifest ||= '__manifest__'
    File.open(".esc/#{manifest}", 'r') { |f| f.read }
  end

  def manifest_exists?
    File.exists? File.join('.esc', '__manifest__')
  end

  def metadata_exists?
    File.exists? File.join('.esc', '__metadata__')
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
    File.new(File.join('.esc', '__metadata__'), 'w')
    File.new(File.join('.esc', '__manifest__'), 'w')
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
      file.puts "Snapshot Taken:    #{'2014-03-07 23:59:59 -0800' || Time.now}"
    end
  end
end

require 'minitest/autorun'

describe CustomSourceControl do
  after do
    FileUtils.rm_rf '.esc' if Dir.exists? '.esc'
  end

  before do
    @csc = CustomSourceControl.new
    @csc.initialize_repository
  end

  describe 'when a repository is initialized' do
    it 'must create a new hidden directory named .esc' do
      @csc.repository_exists?.must_equal true
    end

    it 'must create an empty HEAD file' do
      @csc.head_exists?.must_equal true
      @csc.head_contents.empty?.must_equal true
    end
  end

  describe 'when we take a snapshot' do
    before do
      @csc.snapshot
    end

    it 'must create a metadata file' do
      @csc.metadata_exists?.must_equal true
    end

    it 'must create a manifest file' do
      @csc.manifest_exists?.must_equal true
    end

    it 'gets a list of files in the current working directory' do
      @csc.cwd_files.must_equal ['test_file_1.txt', 'test_file_2.txt']
    end

    it 'creates a file hash for all files in the current working directory' do
      actual_hashes = {
        'test_file_1.txt' => 'bb4d8995cfa843effc83d6ddcea1a8351c09497f',
        'test_file_2.txt' => '5d3140359919315ea06e3755cdc81860e9d7c556'
      }
      @csc.cwd_hashes.must_equal actual_hashes
    end

    it 'gets a list of files in the current working directory' do
      ['__manifest__', '__metadata__', 'HEAD'].each do |filename|
        @csc.repository_file_list.must_include filename
      end
    end

    it 'returns a list of new and existing files' do
      deltas = @csc.deltas
      deltas[:new].must_equal ['test_file_1.txt', 'test_file_2.txt']
      deltas[:existing].must_equal []
    end

    it 'adds entries to the manifest file' do
      expected_content = %Q{5d3140359919315ea06e3755cdc81860e9d7c556 => test_file_2.txt (new)\nbb4d8995cfa843effc83d6ddcea1a8351c09497f => test_file_1.txt (new)}
      manifest_contents = @csc.manifest_contents
      manifest_contents.chomp.must_equal expected_content
    end

    it 'copies files listed in the manifest to the repository' do
      @csc.verify_manifest('__manifest__').must_equal true
    end

    it 'calculates the hash of the manifest file and renames it to the hash' do
      manifest_hash = @csc.hash_for_file File.join('.esc', '__manifest__')
      @csc.repository_file_exists?(manifest_hash).must_equal true
    end

    it 'adds the snapshot info to the metadata file, calculates its file hash, and renames it to the hash' do
      manifest_hash = @csc.hash_for_file File.join('.esc', '__manifest__')
      metadata_hash = @csc.hash_for_file File.join('.esc', '__metadata__')
      @csc.repository_file_exists?(metadata_hash).must_equal true
    end

    it 'updates HEAD to the latest snapshot' do
      metadata_hash = @csc.hash_for_file File.join('.esc', '__metadata__')
      @csc.head_contents.must_equal metadata_hash
    end
  end

  describe 'when we checkout a previous snapshot' do
    after do
      File.open('test_file_2.txt', 'w') do |file|
        file.write "this is test_file_2.text\n"
      end
      File.delete('test_file_3.txt')
    end

    before do
      @csc.snapshot

      # make some edits
      File.open('test_file_3.txt', 'w') do |file|
        file.write "this is test_file_3.text\n"
      end
      File.open('test_file_2.txt', 'a') do |file|
        file.write "this is an update to test_file_2.text\n"
      end

      # take our second snapshot
      @csc.snapshot
    end

    it 'copies files from the manifest into the current working directory' do
      @csc.checkout '485ac882b4e89e929584acdfed522499f0a45464'
      restored_hash = @csc.hash_for_file 'test_file_2.txt'
      restored_hash.must_equal '5d3140359919315ea06e3755cdc81860e9d7c556'
    end
  end
end
