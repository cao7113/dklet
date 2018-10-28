RSpec.describe Dklet::Util do
  it "check and recognize singline-line commands" do
    cmd = "bash -c 'echo hi'"
    expect(Dklet::Util.single_line?(cmd)).to eq(true)

    cmd = "bash -c 'echo hi'; not support this case"
    expect(Dklet::Util.single_line?(cmd)).to eq(true)

    cmd = "echo a; echo b"
    expect(Dklet::Util.single_line?(cmd)).to eq(false)

    cmd = <<~Desc
      echo a
      echo c
    Desc
    expect(Dklet::Util.single_line?(cmd)).to eq(false)

    cmd = <<~Desc
      echo a
      sh
    Desc
    expect(Dklet::Util.single_line?(cmd)).to eq(false)

    cmd = <<~Desc
      psql -c '\\du'
    Desc
    expect(Dklet::Util.single_line?(cmd)).to eq(true)
  end
end
