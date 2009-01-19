require "yaml"
require "thread"

# This is a drop in replacement for Hash.
# It does act just the same but reads/writes from a yaml
# file whenever the hash or the file changes.
# This is much slower than a hash, as you might guess.
# A StoredHash is thread-safe.
class StoredHash

  attr_reader :file

  class << self
    alias load new
  end

  def initialize file, *args, &block
    @data  = Hash.new(*args, &block)
    @file  = file
    @mutex = Mutex.new
  end

  def == other
    super or @data == other
  end

  [:to_yaml, :inspect, :eql?, :hash].each do |name|
    define_method(name) do |*args|
      method_missing(name, *args)
    end
  end

  [:dup, :clone].each do |name|
    define_method(name) do
      @mutex.synchronize do
        super.instance_eval do
          @mutex = Mutex.new
          @data  = @data.send name
          self
        end
      end
    end
  end

  # Here is where the magic happens. Before any method is called on the hash
  # we'll check the file for changes (of course only reading the file if it
  # has been changed). After the method terminated we check whether the hash
  # has been changed and if so, we write it to the file.
  def method_missing(*args, &blk)
    synchronize do |file|
      update file if should_update? file
      @old_data ||= duplicate_data
      result = @data.send(*args, &blk)
      write if should_write?
      return self if result == @data
      result
    end
  end

  def to_hash
    @data.dup
  end

  def is_a? whatever
    super whatever or @data.is_a? whatever
  end

  private

  def should_update? file
    not @mtime or file.mtime >= @mtime
  end

  def update file
    @data.replace YAML.load(file.read)
    @mtime    = file.mtime
    @old_data = duplicate_data
  end

  def duplicate_data
    @data.respond_to?(:deep_clone) ? @data.deep_clone : @data.dup
  end

  def should_write?
    @data != @old_data
  end

  def write
    yaml = @data.to_yaml
    begin
      YAML.load yaml
    rescue ArgumentError
      @data.replace @old_data
      raise ArgumentError, "Unable to store object as yaml."
    end
    File.open(@file, "w") { |f| f.write(yaml) }
    @mtime = File.mtime(@file)
    @old_data = duplicate_data
  end

  # Not only do we want to synchronize threads, but processes, too.
  def synchronize
    @mutex.synchronize do
      unless File.exists?(@file)
        File.open(@file, "w") { |f| f.write(Hash.new.to_yaml) }
      end
      File.open(@file, "r") do |file|
        begin
          file.flock(File::LOCK_EX)
          result = yield(file)
        ensure
          file.flock(File::LOCK_UN)
        end
        result
      end
    end
  end

end

class Hash
  def store file
    StoredHash.new(file).replace self
  end
end

