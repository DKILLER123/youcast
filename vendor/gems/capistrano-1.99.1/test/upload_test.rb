require "#{File.dirname(__FILE__)}/utils"
require 'capistrano/upload'

class UploadTest < Test::Unit::TestCase
  def setup
    @mode = IO::WRONLY | IO::CREAT | IO::TRUNC
  end

  def test_initialize_should_raise_error_if_data_is_missing
    assert_raises(ArgumentError) do
      Capistrano::Upload.new([], "test.txt", :foo => "bar")
    end
  end

  def test_initialize_should_get_sftp_for_each_session
    new_sftp = Proc.new do |state|
      sftp = mock("sftp", :state => state, :open => nil)
      sftp.expects(:connect) unless state == :open
      chan = mock("channel")
      chan.expects(:[]=).with(:done, false)
      sftp.expects(:channel).returns(chan)
      sftp
    end

    sessions = [mock("session", :xserver => server("a"), :sftp => new_sftp[:closed]),
                mock("session", :xserver => server("b"), :sftp => new_sftp[:closed]),
                mock("session", :xserver => server("c"), :sftp => new_sftp[:open])]
    Capistrano::Upload.new(sessions, "test.txt", :data => "data")
  end

  def test_self_process_should_instantiate_uploader_and_start_process
    Capistrano::Upload.expects(:new).with([:s1, :s2], "test.txt", :data => "data").returns(mock(:process! => nil))
    Capistrano::Upload.process([:s1, :s2], "test.txt", :data => "data")
  end

  def test_process_when_sftp_open_fails_should_raise_error
    channel = mock("channel")
    channel.expects(:[]=).with(:done, false) # initialized to false
    channel.expects(:[]=).with(:done, true)  # set to true when done
    sftp = mock("sftp", :state => :open)
    sftp.expects(:channel).times(2).returns(channel)
    sftp.expects(:open).with("test.txt", @mode, 0660).yields(mock("status", :code => "bad status", :message => "bad status"), :file_handle)
    session = mock("session", :sftp => sftp, :xserver => server("capistrano"))
    upload = Capistrano::Upload.new([session], "test.txt", :data => "data", :logger => stub_everything)
    assert_raises(Capistrano::UploadError) { upload.process! }
    assert_equal 1, upload.failed
    assert_equal 1, upload.completed
  end

  def test_process_when_sftp_write_fails_should_raise_error
    channel = mock("channel")
    channel.expects(:[]=).with(:done, false)
    channel.expects(:[]=).with(:done, true)
    sftp = mock("sftp", :state => :open)
    sftp.expects(:channel).times(2).returns(channel)
    sftp.expects(:open).with("test.txt", @mode, 0660).yields(mock("status1", :code => Net::SFTP::Session::FX_OK), :file_handle)
    sftp.expects(:write).with(:file_handle, "data").yields(mock("status2", :code => "bad status", :message => "bad status"))
    session = mock("session", :sftp => sftp, :xserver => server("capistrano"))
    upload = Capistrano::Upload.new([session], "test.txt", :data => "data", :logger => stub_everything)
    assert_raises(Capistrano::UploadError) { upload.process! }
    assert_equal 1, upload.failed
    assert_equal 1, upload.completed
  end

  def test_process_when_sftp_succeeds_should_raise_nothing
    channel = mock("channel")
    channel.expects(:[]=).with(:done, false)
    channel.expects(:[]=).with(:done, true)
    sftp = mock("sftp", :state => :open)
    sftp.expects(:channel).times(2).returns(channel)
    sftp.expects(:open).with("test.txt", @mode, 0660).yields(mock("status1", :code => Net::SFTP::Session::FX_OK), :file_handle)
    sftp.expects(:write).with(:file_handle, "data").yields(mock("status2", :code => Net::SFTP::Session::FX_OK))
    sftp.expects(:close_handle).with(:file_handle).yields
    session = mock("session", :sftp => sftp, :xserver => server("capistrano"))
    upload = Capistrano::Upload.new([session], "test.txt", :data => "data", :logger => stub_everything)
    assert_nothing_raised { upload.process! }
    assert_equal 0, upload.failed
    assert_equal 1, upload.completed
  end

  def test_process_should_loop_while_running
    con = mock("connection")
    con.expects(:process).with(true).times(10)
    channel = mock("channel")
    channel.expects(:[]=).with(:done, false)
    channel.expects(:[]).with(:done).returns(false).times(10)
    channel.expects(:connection).returns(con).times(10)
    sftp = mock("sftp", :state => :open, :open => nil)
    sftp.expects(:channel => channel).times(21)
    session = mock("session", :sftp => sftp, :xserver => server("capistrano"))
    upload = Capistrano::Upload.new([session], "test.txt", :data => "data")
    upload.expects(:running?).times(11).returns(*([true]*10 + [false]))
    upload.process!
  end

  def test_process_should_loop_but_not_process_done_channels
    new_sftp = Proc.new do |done|
      if !done
        con = mock("connection")
        con.expects(:process).with(true).times(10)
      end
      channel = mock("channel")
      channel.expects(:[]=).with(:done, false)
      channel.expects(:[]).with(:done).returns(done).times(10)
      channel.expects(:connection).returns(con).times(10) if !done
      sftp = mock("sftp", :state => :open, :open => nil)
      sftp.expects(:channel => channel).times(done ? 11 : 21)
      sftp
    end

    sessions = [mock("session", :sftp => new_sftp[true], :xserver => server("capistrano")),
                mock("session", :sftp => new_sftp[false], :xserver => server("cap2"))]
    upload = Capistrano::Upload.new(sessions, "test.txt", :data => "data")
    upload.expects(:running?).times(11).returns(*([true]*10 + [false]))
    upload.process!
  end
end
