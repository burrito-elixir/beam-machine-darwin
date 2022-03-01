#! elixir
#### Beam Machine
#### MacOS

################################################

orig_cwd = File.cwd!()

temp_workdir = System.tmp_dir!() |> Path.join(:crypto.strong_rand_bytes(8) |> Base.encode16())
File.mkdir_p!(temp_workdir)
File.cd!(temp_workdir)
Path.join(temp_workdir, "sysroot") |> File.mkdir!()

defmodule ScriptUtils do
  def get_current_cpu do
    :erlang.system_info(:system_architecture)
    |> to_string()
    |> String.downcase()
    |> String.split("-")
    |> List.first()
  end

  def get_current_os do
    case :os.type() do
      {:win32, _} -> :windows
      {:unix, :darwin} -> :darwin
      {:unix, :linux} -> :linux
    end
  end

  def fetch_and_extract(base_url, file_name) do
    "wget #{base_url}/#{file_name}" |> String.to_charlist() |> :os.cmd()
    [] = "tar xzf #{file_name}" |> String.to_charlist() |> :os.cmd()
  end

  def print_fatal(val) do
    IO.puts("[!] #{val}")
    System.halt(1)
  end

  def exec_command_in_cwd(command, env) do
    System.cmd(
      "/bin/bash",
      [
        "-c",
        command
      ],
      cd: File.cwd!(),
      into: IO.stream(),
      env: env,
      stderr_to_stdout: true
    )
  end

  def arch_to_atom("x86_64"), do: :x86_64
  def arch_to_atom("aarch64"), do: :aarch64
  def arch_to_atom(_), do: get_current_cpu() |> arch_to_atom()

  def openssl_target(:x86_64), do: "darwin64-x86_64-cc"
  def openssl_target(:aarch64), do: "darwin64-arm64-cc"

  def ncurses_target(:x86_64), do: "x86_64-macos"
  def ncurses_target(:aarch64), do: "aarch64-macos"

  def erlang_target(:x86_64), do: "x86_64-apple-darwin"
  def erlang_target(:aarch64), do: "aarch64-apple-darwin"

  def clang_target(:x86_64), do: "x86_64-apple-macos11"
  def clang_target(:aarch64), do: "arm64-apple-macos11"
end

################################################

script_version = "0.1.0"
default_openssl_version = "1.1.1m"
default_ncurses_version = "6.3"

usage = """
  mkerlang v#{script_version} - build a static Erlang release for MacOS (aarch64 or x86_64)

  args:
    --otp-version=[x.y.z] (The OTP version that will be built) [REQUIRED]
    --arch=[aarch64, x86_64] (The arch to build erlang for, defualts to the current host arch)
    --openssl-version=[x.y.z(w)] (OpenSSL version to statically link into the release, defualts to #{default_openssl_version})
    --ncurses-version=[x.y.z] (NCurses version to statically link into the release, defualts to #{default_ncurses_version})
"""

options = [
  otp_version: :string,
  arch: :string,
  openssl_version: :string,
  ncurses_version: :string
]

required_path_commands = ["wget", "clang", "make", "autoconf", "perl", "tar"]

if Enum.any?(required_path_commands, fn command ->
     match?({_, 1}, System.cmd("which", [command]))
   end) do
  ScriptUtils.print_fatal(
    "Required programs (#{inspect(required_path_commands)}) were missing from path"
  )
end

{args, _rest} = OptionParser.parse!(System.argv(), switches: options)

if !Keyword.has_key?(args, :otp_version) do
  IO.puts(usage)
  ScriptUtils.print_fatal("Required parameter --otp_version was not provided!")
end

IO.puts("Host OS: #{ScriptUtils.get_current_os()}")
IO.puts("Host Arch: #{ScriptUtils.get_current_cpu()}")
IO.puts("Build Dir: #{temp_workdir}")
IO.puts("----------")

target_erlang_version = Keyword.get(args, :otp_version)
target_openssl_version = Keyword.get(args, :openssl_version, default_openssl_version)
target_ncurses_version = Keyword.get(args, :ncurses_version, default_ncurses_version)

target_arch =
  Keyword.get(args, :arch, ScriptUtils.get_current_cpu()) |> ScriptUtils.arch_to_atom()

IO.puts("Targe Arch: #{target_arch}")
IO.puts("Target Erlang Version: #{target_erlang_version}")
IO.puts("Target OpenSSL Version: #{target_openssl_version}")
IO.puts("Target NCurses Version: #{target_ncurses_version}")
IO.puts("----------")

IO.puts("-> Fetch & Extract: OpenSSL...")

ScriptUtils.fetch_and_extract(
  "https://www.openssl.org/source",
  "openssl-#{target_openssl_version}.tar.gz"
)

IO.puts("-> Fetch & Extract: NCurses...")

ScriptUtils.fetch_and_extract(
  "https://ftp.gnu.org/pub/gnu/ncurses",
  "ncurses-#{target_ncurses_version}.tar.gz"
)

IO.puts("-> Fetch & Extract: Erlang...")

ScriptUtils.fetch_and_extract(
  "https://github.com/erlang/otp/releases/download/OTP-#{target_erlang_version}",
  "otp_src_#{target_erlang_version}.tar.gz"
)

IO.puts("----------")

target_sysroot = Path.join(temp_workdir, "sysroot")
compiler_env = [
  {"CC", "clang -target #{ScriptUtils.clang_target(target_arch)}"},
  {"CXX", "clang++ -target #{ScriptUtils.clang_target(target_arch)}"}
]

IO.puts("-> Build: OpenSSL...")
Path.join(temp_workdir, "openssl-#{target_openssl_version}") |> File.cd!()
ScriptUtils.exec_command_in_cwd("./Configure #{ScriptUtils.openssl_target(target_arch)} no-shared --prefix=#{target_sysroot} && make -j && make install_sw", compiler_env)

IO.puts("-> Build: NCurses...")
Path.join(temp_workdir, "ncurses-#{target_ncurses_version}") |> File.cd!()
ScriptUtils.exec_command_in_cwd("./configure --host=#{ScriptUtils.ncurses_target(target_arch)} --with-normal --without-shared --prefix=#{target_sysroot} && make -j && make install", compiler_env)

IO.puts("-> Build: Erlang...")

erlang_configure_flags = "--disable-parallel-configure --without-megaco --without-javac --without-jinterface --without-hipe --disable-dynamic-ssl-lib --with-ssl='#{target_sysroot}'"

IO.puts("--> Boostrap...")
Path.join(temp_workdir, "otp_src_#{target_erlang_version}") |> File.cd!()
ScriptUtils.exec_command_in_cwd("./configure --enable-bootstrap-only --without-javac --without-jinterface && make -j", [])

IO.puts("--> Final Build...")
erlang_env = [
  {"erl_xcomp_sysroot", target_sysroot},
  {"CC", "clang -target #{ScriptUtils.clang_target(target_arch)}"},
  {"CXX", "clang++ -target #{ScriptUtils.clang_target(target_arch)}"},
  {"LDFLAGS", "-L#{target_sysroot}/lib"},
  {"CFLAGS", "-O2 -g -L#{target_sysroot}/lib -I#{target_sysroot}/include -I#{target_sysroot}/include/ncurses"},
  {"CXXFLAGS", "-O2 -g -L#{target_sysroot}/lib -I#{target_sysroot}/include -I#{target_sysroot}/include/ncurses"},
]
ScriptUtils.exec_command_in_cwd("./configure #{erlang_configure_flags} --host=#{ScriptUtils.erlang_target(target_arch)} --build=$(erts/autoconf/config.guess) && make -j", erlang_env)

IO.puts("-> Build & Pack Release...")
release_name = "otp_#{target_erlang_version}_macos_#{target_arch}_ssl_#{target_openssl_version}"
release_root = Path.join(orig_cwd, release_name)
ScriptUtils.exec_command_in_cwd("make release -j", [{"RELEASE_ROOT", release_root}])

File.cd!(orig_cwd)
ScriptUtils.exec_command_in_cwd("tar czf #{release_name}.tar.gz ./#{release_name}/", [])

IO.puts("-> Cleaning Up")
File.rm_rf!(temp_workdir)
File.rm_rf!(release_root)

IO.puts("-> Done!")
