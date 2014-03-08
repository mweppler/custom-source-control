#!/usr/bin/env ruby

require 'fileutils'

class CustomSourceControl
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

  def repository_exists?
    Dir.exists? '.esc'
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
end
