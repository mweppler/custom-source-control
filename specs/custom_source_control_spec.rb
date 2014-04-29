require 'helper'

describe CustomSourceControl do
  after do
    FileUtils.rm_rf '.esc' if Dir.exists? '.esc'
  end

  before do
    repo_dir = File.join(File.dirname(__FILE__), 'test_dir')
    Dir.chdir repo_dir
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
      Time.stub :now, '2014-03-07 23:59:59 -0800' do
        @csc.snapshot
      end
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
      Time.stub :now, '2014-03-07 23:59:59 -0800' do
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
    end

    it 'copies files from the manifest into the current working directory' do
      @csc.checkout '485ac882b4e89e929584acdfed522499f0a45464'
      restored_hash = @csc.hash_for_file 'test_file_2.txt'
      restored_hash.must_equal '5d3140359919315ea06e3755cdc81860e9d7c556'
    end
  end
end
