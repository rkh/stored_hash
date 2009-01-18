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

  def to_yaml
    method_missing(:to_yaml)
  end

  def inspect
    method_missing(:inspect)
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
      update if should_update?
      @old_data ||= @data.deep_clone
      result = @data.send(*args, &blk)
      write if should_write?
      return self if result == @data
      result
    end
  end

  def to_hash
    @data.dup
  end

  private

  def should_update?
    not @mtime or file.mtime >= @mtime
  end

  def update
    @data.replace YAML.load(file.read)
    @mtime    = file.mtime
    @old_data = @data.deep_clone
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
    @old_data = @data.deep_clone
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

