require File.expand_path("../rspec_helper", __FILE__)

describe GetPomo do
  it "has a VERSION" do
    GetPomo::VERSION.should =~ /^\d+\.\d+\.\d+$/
  end
end
