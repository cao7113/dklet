require 'tempfile'
require 'socket'

module Dklet::Util
  module_function

  def tmpfile_for(str, prefix: 'kc-tmp')
    file = Tempfile.new(prefix)
    file.write str
    file.close # save to disk
    # unlink清理问题：引用进程结束时自动删除？👍 
    file.path
  end

  def human_timestamp(t = Time.now)
    t.strftime("%Y%m%d%H%M%S")
  end

  def host_ip
    Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
  end
end
