require 'tempfile'
require 'socket'

module Dklet::Util
  module_function

  def human_timestamp(t = Time.now)
    t.strftime("%Y%m%d%H%M%S")
  end

  def tmpfile_for(str, prefix: 'dklet-tmp')
    file = Tempfile.new(prefix)
    file.write str
    file.close # save to disk
    # unlink清理问题：引用进程结束时自动删除？👍 
    file.path
  end

  def host_ip
    Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
  end

  def single_line?(cmds, pattern: /.+[\n;]/)
    return false if cmds.is_a? Array
    return true if cmds =~ /^\s*(bash|sh)/ 
    cmds !~ pattern
  end
end
