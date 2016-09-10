require 'spec_helper'
require 'imas/producer_schedule'

describe Imas::ProducerSchedule do
  def generate_calendar(dir, yml)
    c = Imas::ProducerSchedule::Client.new yml
    c.output_cal(dir)
  end

  def normalize(str)
    str.each_line.reject{|l| %w(UID DTSTAMP).any? { |word| l.start_with?(word) } }
  end

  before do
    generate_calendar out_dir, yml_path
  end

  after do
   FileUtils.remove_entry_secure out_dir
  end

  let(:yml_path) { File.expand_path('../months.yml', __FILE__) }

  let(:out_dir) do
    Dir.mktmpdir(nil, File.expand_path('..', __FILE__))
  end

  let(:expected) do
    filepath = File.join(File.expand_path('../expected', __FILE__), 'producer_schedule.ics')
    content = open(filepath).read
    normalize(content)
  end

  subject(:actual) do
    content = open(File.join(out_dir, "schedule.ics")).read
    normalize(content)
  end

  it do
    actual.zip(expected).each {|a, e| expect(e).to eq a }
  end
end
