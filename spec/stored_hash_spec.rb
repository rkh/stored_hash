$: << File.join(File.dirname(__FILE__), "..", "lib")

require 'stored_hash'
require 'fileutils'

describe StoredHash do

  before :each do
    @stored_hash = StoredHash.new "/tmp/test#{Time.now.to_i}.yml"
    @some_hashes = [ {}, {0 => 1, 2 => 3, 4 => 5}, {"foo" => [{:bar => "blah"}]} ]
    def with_some_hash
      @some_hashes.each do |a_hash|
        @stored_hash.replace a_hash
        yield a_hash
        @stored_hash.replace Hash.new
      end
    end
  end

  after :each do
    FileUtils.rm @stored_hash.file
  end

  it "should write and read correctly" do
    10.times do |i|
      ["i", "i.to_s", "i.to_s.to_sym", "'abc ' * i"].each do |code|
        value = eval(code)
        [i, code, value].each do |key|
          @stored_hash[key] = value
          @stored_hash[key].should == value
        end
      end
    end
  end

  it "should behave like a Hash#inspect" do
    with_some_hash { |a_hash| @stored_hash.inspect.should == a_hash.inspect }
  end

  it "should behave like a Hash#to_yaml" do
    with_some_hash { |a_hash| @stored_hash.to_yaml.should == a_hash.to_yaml }
  end

  it "should behave like a Hash#inspect" do
    with_some_hash { |a_hash| @stored_hash.inspect.should == a_hash.inspect }
  end

  it "should behave like a Hash#hash" do
    with_some_hash { |a_hash| @stored_hash.hash.should == a_hash.hash }
  end

  it "should behave like a Hash#eql?" do
    with_some_hash do |a_hash|
      @some_hashes.each do |another_hash|
        @stored_hash.eql?(another_hash).should == a_hash.eql?(another_hash)
      end
    end
  end

  it "should behave like a Hash#== for other hashes" do
    with_some_hash do |a_hash|
      @some_hashes.each do |another_hash|
        @stored_hash.==(another_hash).should == a_hash.==(another_hash)
      end
    end
  end

  it "should return true for #is_a?(Hash)" do
    with_some_hash { @stored_hash.is_a?(Hash).should == true }
  end

  it "should equal an empty hash after #clear" do
    with_some_hash do
      @stored_hash.clear
      @stored_hash.should == {}
      @stored_hash.size.should == 0
      @stored_hash.empty?.should == true
    end
  end

  it "should properly delete items" do
    with_some_hash do
      a_key = @stored_hash.keys.first
      @stored_hash.delete(a_key).should @stored_hash[a_key]
      @stored_hash.include?(a_key).should == false
    end
  end

  it "should be thread safe" do
    thread_number = 5
    max_count     = 10
    threads       = []
    thread_number.times do |tnum|
      threads << Thread.new(tnum) do |t|
        max_count.times do |i|
          @stored_hash["#{t} #{i}"] = 0
        end
      end
    end
    threads.each { |t| t.join }
    @stored_hash.size.should == (thread_number * max_count)
  end

end

