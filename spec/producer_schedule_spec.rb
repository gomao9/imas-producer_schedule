require 'spec_helper'
require 'imas/producer_schedule'

describe Imas::ProducerSchedule do
  def generate_calendar(dir)
    c = Imas::ProducerSchedule::Client.new
    c.output_cal(dir)
  end

  def remove_line(str)
    str.each_line.reject{|l| %w(UID DTSTAMP).any? { |word| l.start_with?(word) } }
  end

  before do
    generate_calendar out_dir
  end

  after do
   FileUtils.remove_entry_secure out_dir
  end

  let(:out_dir) do
    Dir.mktmpdir(nil, File.expand_path('..', __FILE__))
  end

  let(:expected) do
    filepath = File.join(File.expand_path('../expected', __FILE__), 'producer_schedule.ics')
    content = open(filepath).read
    remove_line(content)
  end

  subject(:actual) do
    content = open(File.join(out_dir, "schedule.ics")).read
    remove_line(content)
  end

  it { is_expected.to eq expected }
end
